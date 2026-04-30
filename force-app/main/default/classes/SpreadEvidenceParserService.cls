public with sharing class SpreadEvidenceParserService {
    @TestVisible private static final String DEFAULT_PATH_KEY = 'salesforce_native_staging';
    @TestVisible private static final String PARSER_VERSION = 'deterministic-apex-v1';
    @TestVisible private static final Pattern FINANCIAL_VALUE_TOKEN_PATTERN =
        Pattern.compile('\\(?\\$?[\\d,]+(?:\\.\\d{1,2})?\\)?');
    @TestVisible private static final Pattern PERIOD_DATE_PATTERN =
        Pattern.compile('(?i)(January|February|March|April|May|June|July|August|September|October|November|December)\\s+\\d{1,2},\\s*\\d{4}');
    @TestVisible private static final Pattern YEAR_TOKEN_PATTERN =
        Pattern.compile('\\b(19\\d{2}|20\\d{2})\\b');
    @TestVisible private static SpreadLineMappingSelector lineMappingSelector = new SpreadLineMappingSelector();

    public static SpreadingParseOutput parseDocument(Id spreadDocumentId, String pathKey) {
        SpreadingParseOutput output = new SpreadingParseOutput();
        output.spreadDocumentId = spreadDocumentId == null ? null : String.valueOf(spreadDocumentId);
        output.pathKey = String.isBlank(pathKey) ? DEFAULT_PATH_KEY : pathKey;
        output.parserVersion = PARSER_VERSION;

        if (spreadDocumentId == null) {
            output.parsingStatus = 'Failed';
            output.errorMessage = 'Spread Document Id is required.';
            return output;
        }

        Spread_Document__c document = [
            SELECT Id, Pilot_Run__c, Statement_Type__c, Fiscal_Period__c, Parsing_Status__c, Extraction_Status__c
            FROM Spread_Document__c
            WHERE Id = :spreadDocumentId
            WITH USER_MODE
            LIMIT 1
        ];

        if (document.Extraction_Status__c != 'Complete') {
            output.parsingStatus = 'Failed';
            output.errorMessage = 'Extraction must be Complete before parsing.';
            return output;
        }

        Integer existingResults = [
            SELECT COUNT()
            FROM Spread_Path_Result__c
            WHERE Spread_Document__c = :spreadDocumentId
            AND Path_Key__c = :output.pathKey
            WITH USER_MODE
        ];
        if (existingResults > 0) {
            output.parsingStatus = document.Parsing_Status__c;
            output.errorMessage = 'Draft path results already exist for this document and path.';
            return output;
        }

        List<Spread_Extraction_Evidence__c> evidenceBlocks = [
            SELECT Id, Raw_Text__c, Source_Page__c, Source_Coordinates__c
            FROM Spread_Extraction_Evidence__c
            WHERE Spread_Document__c = :spreadDocumentId
            AND Extraction_Status__c = 'Success'
            WITH USER_MODE
            ORDER BY Source_Page__c ASC, CreatedDate ASC
        ];
        output.evidenceBlockCount = evidenceBlocks.size();

        if (evidenceBlocks.isEmpty()) {
            output.parsingStatus = 'Needs Review';
            output.errorMessage = 'No successful extraction evidence blocks were found for this document.';
            markParsingStatus(spreadDocumentId, output.parsingStatus);
            createParseException(spreadDocumentId, output.errorMessage, 'Warning');
            output.exceptionCount = 1;
            return output;
        }

        markParsingStatus(spreadDocumentId, 'In Progress');

        List<Spread_Line_Mapping__mdt> mappings = lineMappingSelector.getActiveMappings(document.Statement_Type__c);
        String parserJson = buildParserJson(document, evidenceBlocks, mappings, output);
        if (String.isBlank(parserJson)) {
            if (String.isBlank(output.parsingStatus)) {
                output.parsingStatus = 'Needs Review';
            }
            markParsingStatus(spreadDocumentId, output.parsingStatus);
            if (!String.isBlank(output.errorMessage)) {
                createParseException(spreadDocumentId, output.errorMessage, 'Warning');
                output.exceptionCount = Math.max(output.exceptionCount, 1);
            }
            return output;
        }

        SpreadCandidateParserService.ParserImportResult importResult =
            SpreadCandidateParserService.importParserOutput(spreadDocumentId, parserJson, output.pathKey);

        output.lineItemCount = importResult.lineItemCount;
        output.pathResultCount = importResult.pathResultCount;
        output.exceptionCount = importResult.exceptionCount;
        output.parsingStatus = importResult.parsingStatus;
        output.errorMessage = importResult.errorMessage;
        return output;
    }

    private static String buildParserJson(
        Spread_Document__c document,
        List<Spread_Extraction_Evidence__c> evidenceBlocks,
        List<Spread_Line_Mapping__mdt> mappings,
        SpreadingParseOutput output
    ) {
        List<Object> candidates = new List<Object>();
        List<Object> exceptions = new List<Object>();
        Set<String> seenLines = new Set<String>();
        List<String> inferredPeriods = inferFiscalPeriods(document, evidenceBlocks);
        String resolvedStatementType = inferStatementType(document, evidenceBlocks);
        String resolvedFiscalPeriod = String.isBlank(document.Fiscal_Period__c)
            ? (inferredPeriods.isEmpty() ? null : inferredPeriods[0])
            : document.Fiscal_Period__c;

        for (Spread_Extraction_Evidence__c evidence : evidenceBlocks) {
            for (String rawLine : splitLines(evidence.Raw_Text__c)) {
                ParsedEvidenceLine parsedLine = parseEvidenceLine(rawLine);
                if (parsedLine == null) {
                    continue;
                }

                Spread_Line_Mapping__mdt mapping = findMapping(parsedLine.label, mappings);
                if (mapping == null) {
                    continue;
                }

                List<CandidateAmount> amounts = resolveCandidateAmounts(
                    parsedLine,
                    inferredPeriods,
                    resolvedFiscalPeriod
                );

                for (CandidateAmount amount : amounts) {
                    String seenKey = mapping.Normalized_Line__c + '|' + String.valueOf(amount.fiscalPeriod);
                    if (seenLines.contains(seenKey)) {
                        exceptions.add(new Map<String, Object>{
                            'reason' => 'Duplicate candidate for ' + mapping.Normalized_Line__c
                                + ' period ' + String.valueOf(amount.fiscalPeriod),
                            'severity' => mapping.Requires_Reviewer__c ? 'error' : 'warning',
                            'evidence_id' => String.valueOf(evidence.Id),
                            'source_page' => evidence.Source_Page__c,
                            'raw_text' => rawLine.trim()
                        });
                        continue;
                    }

                    Decimal normalizedValue;
                    try {
                        normalizedValue = parseFinancialNumber(amount.valueText);
                    } catch (Exception error) {
                        exceptions.add(new Map<String, Object>{
                            'reason' => 'Unable to parse value for ' + parsedLine.label,
                            'severity' => 'warning',
                            'evidence_id' => String.valueOf(evidence.Id),
                            'source_page' => evidence.Source_Page__c,
                            'raw_text' => rawLine.trim()
                        });
                        continue;
                    }

                    seenLines.add(seenKey);
                    candidates.add(new Map<String, Object>{
                        'normalized_line' => mapping.Normalized_Line__c,
                        'statement_type' => String.isBlank(mapping.Statement_Type__c)
                            ? resolvedStatementType
                            : mapping.Statement_Type__c,
                        'fiscal_period' => amount.fiscalPeriod,
                        'raw_label' => parsedLine.label,
                        'raw_value' => amount.valueText,
                        'normalized_value' => normalizedValue,
                        'evidence_id' => String.valueOf(evidence.Id),
                        'source_page' => evidence.Source_Page__c,
                        'source_coordinates' => evidence.Source_Coordinates__c,
                        'confidence' => confidenceFor(mapping),
                        'exception_reason' => mapping.Requires_Reviewer__c ? 'Reviewer validation required by line mapping policy.' : null,
                        'status' => mapping.Requires_Reviewer__c ? 'exception' : 'draft',
                        'material' => mapping.Material_Default__c
                    });
                }
            }
        }

        if (candidates.isEmpty()) {
            output.parsingStatus = 'Needs Review';
            output.errorMessage = 'No draft spread candidates were produced from the extracted evidence.';
            output.exceptionCount = exceptions.isEmpty() ? 1 : exceptions.size();
            return null;
        }

        return JSON.serialize(new Map<String, Object>{
            'document_id' => String.valueOf(document.Id),
            'statement_type' => resolvedStatementType,
            'fiscal_period' => resolvedFiscalPeriod,
            'parser_version' => PARSER_VERSION,
            'candidates' => candidates,
            'exceptions' => exceptions
        });
    }

    private static List<String> splitLines(String rawText) {
        if (String.isBlank(rawText)) {
            return new List<String>();
        }
        return rawText.split('\\r?\\n');
    }

    private static ParsedEvidenceLine parseEvidenceLine(String rawLine) {
        String trimmed = String.isBlank(rawLine) ? null : rawLine.trim();
        if (String.isBlank(trimmed)) {
            return null;
        }

        Matcher matcher = FINANCIAL_VALUE_TOKEN_PATTERN.matcher(trimmed);
        List<String> valueTexts = new List<String>();
        Integer firstValueIndex;
        while (matcher.find()) {
            if (firstValueIndex == null) {
                firstValueIndex = matcher.start();
            }
            valueTexts.add(matcher.group().trim());
        }

        if (valueTexts.isEmpty() || firstValueIndex == null) {
            return null;
        }

        String label = trimmed.substring(0, firstValueIndex).trim();
        if (String.isBlank(label)) {
            return null;
        }
        return new ParsedEvidenceLine(label, valueTexts);
    }

    private static List<CandidateAmount> resolveCandidateAmounts(
        ParsedEvidenceLine parsedLine,
        List<String> inferredPeriods,
        String fallbackFiscalPeriod
    ) {
        List<CandidateAmount> amounts = new List<CandidateAmount>();
        Integer valueCount = parsedLine.valueTexts.size();
        if (valueCount == 1) {
            String fiscalPeriod = String.isBlank(fallbackFiscalPeriod)
                ? (inferredPeriods.isEmpty() ? null : inferredPeriods[0])
                : fallbackFiscalPeriod;
            amounts.add(new CandidateAmount(parsedLine.valueTexts[0], fiscalPeriod));
            return amounts;
        }

        if (inferredPeriods.size() >= valueCount) {
            for (Integer index = 0; index < valueCount; index++) {
                amounts.add(new CandidateAmount(parsedLine.valueTexts[index], inferredPeriods[index]));
            }
            return amounts;
        }

        amounts.add(new CandidateAmount(parsedLine.valueTexts[0], fallbackFiscalPeriod));
        return amounts;
    }

    private static List<String> inferFiscalPeriods(
        Spread_Document__c document,
        List<Spread_Extraction_Evidence__c> evidenceBlocks
    ) {
        List<String> periods = new List<String>();
        Set<String> seen = new Set<String>();

        for (Spread_Extraction_Evidence__c evidence : evidenceBlocks) {
            Matcher matcher = PERIOD_DATE_PATTERN.matcher(String.valueOf(evidence.Raw_Text__c));
            while (matcher.find()) {
                String period = formatDatePeriod(matcher.group());
                if (!String.isBlank(period) && !seen.contains(period)) {
                    periods.add(period);
                    seen.add(period);
                }
            }
        }

        if (!periods.isEmpty()) {
            return periods;
        }

        if (!String.isBlank(document.Fiscal_Period__c)) {
            periods.add(document.Fiscal_Period__c);
            seen.add(document.Fiscal_Period__c);
            return periods;
        }

        for (Spread_Extraction_Evidence__c evidence : evidenceBlocks) {
            for (String rawLine : splitLines(evidence.Raw_Text__c)) {
                String normalizedLine = normalizeLabel(rawLine);
                Boolean looksLikePeriodHeader = normalizedLine.contains('year')
                    || normalizedLine.contains('period')
                    || normalizedLine.contains('assets')
                    || normalizedLine.contains('liabilities')
                    || normalizedLine.contains('income');
                if (!looksLikePeriodHeader) {
                    continue;
                }

                Matcher yearMatcher = YEAR_TOKEN_PATTERN.matcher(rawLine);
                while (yearMatcher.find()) {
                    String period = 'FY' + yearMatcher.group(1);
                    if (!seen.contains(period)) {
                        periods.add(period);
                        seen.add(period);
                    }
                }
            }
        }

        return periods;
    }

    private static String inferStatementType(
        Spread_Document__c document,
        List<Spread_Extraction_Evidence__c> evidenceBlocks
    ) {
        if (!String.isBlank(document.Statement_Type__c)) {
            return document.Statement_Type__c;
        }

        for (Spread_Extraction_Evidence__c evidence : evidenceBlocks) {
            String normalizedText = normalizeLabel(evidence.Raw_Text__c);
            if (normalizedText.contains('balance sheet')) {
                return 'balance_sheet';
            }
            if (normalizedText.contains('income statement')
                || normalizedText.contains('statements of operations')
                || normalizedText.contains('profit and loss')) {
                return 'income_statement';
            }
        }
        return null;
    }

    private static String formatDatePeriod(String rawDateText) {
        if (String.isBlank(rawDateText)) {
            return null;
        }
        Matcher matcher = Pattern.compile(
            '(?i)^(January|February|March|April|May|June|July|August|September|October|November|December)\\s+(\\d{1,2}),\\s*(\\d{4})$'
        ).matcher(rawDateText.trim());
        if (!matcher.matches()) {
            return rawDateText.trim();
        }

        return monthNumber(matcher.group(1)) + '/'
            + String.valueOf(Integer.valueOf(matcher.group(2))) + '/'
            + matcher.group(3);
    }

    private static String monthNumber(String monthName) {
        String normalized = String.isBlank(monthName) ? '' : monthName.toLowerCase();
        Map<String, Integer> monthsByName = new Map<String, Integer>{
            'january' => 1,
            'february' => 2,
            'march' => 3,
            'april' => 4,
            'may' => 5,
            'june' => 6,
            'july' => 7,
            'august' => 8,
            'september' => 9,
            'october' => 10,
            'november' => 11,
            'december' => 12
        };
        Integer month = monthsByName.get(normalized);
        return String.valueOf(month == null ? 12 : month);
    }

    private static Decimal parseFinancialNumber(String valueText) {
        String raw = String.isBlank(valueText) ? null : valueText.trim();
        if (String.isBlank(raw)) {
            throw new AuraHandledException('Financial value is blank.');
        }
        Boolean negative = raw.startsWith('(') && raw.endsWith(')');
        String normalized = raw.replaceAll('[,$()\\s]', '');
        Decimal value = Decimal.valueOf(normalized);
        return negative ? value * -1 : value;
    }

    private static Spread_Line_Mapping__mdt findMapping(String label, List<Spread_Line_Mapping__mdt> mappings) {
        String normalizedLabel = normalizeLabel(label);
        for (Spread_Line_Mapping__mdt mapping : mappings) {
            if (normalizeLabel(mapping.Accepted_Label__c) == normalizedLabel) {
                return mapping;
            }
        }
        return null;
    }

    private static Decimal confidenceFor(Spread_Line_Mapping__mdt mapping) {
        return mapping.Requires_Reviewer__c ? 0.85 : 0.96;
    }

    private static String normalizeLabel(String value) {
        String normalized = String.isBlank(value) ? '' : value.toLowerCase();
        normalized = normalized.replaceAll('[^a-z0-9]+', ' ').trim();
        while (normalized.contains('  ')) {
            normalized = normalized.replace('  ', ' ');
        }
        return normalized;
    }

    private static void markParsingStatus(Id spreadDocumentId, String status) {
        update new Spread_Document__c(
            Id = spreadDocumentId,
            Parsing_Status__c = status,
            Parsed_At__c = System.now()
        );
    }

    private static void createParseException(Id spreadDocumentId, String reason, String severity) {
        insert new Spread_Exception__c(
            Spread_Document__c = spreadDocumentId,
            Exception_Reason__c = reason,
            Severity__c = severity
        );
    }

    private class ParsedEvidenceLine {
        public String label;
        public List<String> valueTexts;

        public ParsedEvidenceLine(String label, List<String> valueTexts) {
            this.label = label;
            this.valueTexts = valueTexts;
        }
    }

    private class CandidateAmount {
        public String valueText;
        public String fiscalPeriod;

        public CandidateAmount(String valueText, String fiscalPeriod) {
            this.valueText = valueText;
            this.fiscalPeriod = fiscalPeriod;
        }
    }
}
