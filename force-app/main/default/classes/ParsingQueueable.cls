public class ParsingQueueable implements Queueable {
    private Id spreadDocumentId;
    private static final String PROMPT_TEMPLATE = 'SpreadLineNormalization';

    public ParsingQueueable(Id spreadDocumentId) {
        this.spreadDocumentId = spreadDocumentId;
    }

    public void execute(QueueableContext ctx) {
        try {
            Spread_Document__c doc = [
                SELECT Id, Pilot_Run__c, Statement_Type__c, Fiscal_Period__c
                FROM Spread_Document__c
                WHERE Id = :spreadDocumentId
                WITH USER_MODE
                LIMIT 1
            ];

            List<Spread_Extraction_Evidence__c> evidences = [
                SELECT Id, Raw_Text__c
                FROM Spread_Extraction_Evidence__c
                WHERE Spread_Document__c = :spreadDocumentId
                AND Extraction_Status__c = 'Success'
                WITH USER_MODE
                ORDER BY CreatedDate ASC
                LIMIT 1
            ];

            if (evidences.isEmpty()) {
                markParsingStatus(spreadDocumentId, 'Failed');
                return;
            }

            Spread_Extraction_Evidence__c evidence = evidences[0];
            String promptResponse = callEinsteinPromptTemplate(
                evidence.Raw_Text__c,
                doc.Statement_Type__c,
                doc.Fiscal_Period__c
            );

            if (String.isBlank(promptResponse)) {
                markParsingStatus(spreadDocumentId, 'Needs Review');
                return;
            }

            String parserJson = translateToParserJson(
                doc.Id,
                doc.Statement_Type__c,
                doc.Fiscal_Period__c,
                promptResponse,
                evidence.Id
            );

            if (String.isBlank(parserJson)) {
                markParsingStatus(spreadDocumentId, 'Needs Review');
                return;
            }

            SpreadCandidateParserService.importParserOutput(spreadDocumentId, parserJson, null);

        } catch (Exception e) {
            markParsingStatus(spreadDocumentId, 'Failed');
        }
    }

    private String callEinsteinPromptTemplate(String extractedText, String statementType, String fiscalPeriod) {
        Map<String, ConnectApi.WrappedValue> inputParams = new Map<String, ConnectApi.WrappedValue>{
            'Input:extracted_tables' => wrapValue(extractedText),
            'Input:statement_type' => wrapValue(String.isBlank(statementType) ? 'unknown' : statementType),
            'Input:fiscal_period' => wrapValue(String.isBlank(fiscalPeriod) ? 'unknown' : fiscalPeriod)
        };

        ConnectApi.EinsteinPromptTemplateGenerationsInput executeTemplateInput =
            new ConnectApi.EinsteinPromptTemplateGenerationsInput();
        executeTemplateInput.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
        executeTemplateInput.additionalConfig.applicationName = 'PromptBuilderPreview';
        executeTemplateInput.additionalConfig.numGenerations = 1;
        executeTemplateInput.additionalConfig.temperature = 0.1;
        executeTemplateInput.isPreview = false;
        executeTemplateInput.inputParams = inputParams;

        ConnectApi.EinsteinPromptTemplateGenerationsRepresentation generationsOutput;
        try {
            generationsOutput = ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
                PROMPT_TEMPLATE,
                executeTemplateInput
            );
        } catch (Exception e) {
            return null;
        }
        if (generationsOutput == null || generationsOutput.generations == null || generationsOutput.generations.isEmpty()) {
            return null;
        }
        return generationsOutput.generations[0].text;
    }

    private ConnectApi.WrappedValue wrapValue(Object value) {
        ConnectApi.WrappedValue wrappedValue = new ConnectApi.WrappedValue();
        wrappedValue.value = value;
        return wrappedValue;
    }

    private String translateToParserJson(
        Id docId,
        String statementType,
        String fiscalPeriod,
        String promptResponse,
        Id evidenceId
    ) {
        List<Object> rawItems;
        try {
            rawItems = (List<Object>) JSON.deserializeUntyped(promptResponse);
        } catch (Exception e) {
            return null;
        }

        if (rawItems == null || rawItems.isEmpty()) {
            return null;
        }

        List<Map<String, Object>> candidates = new List<Map<String, Object>>();
        String resolvedStatementType = statementType;
        String resolvedFiscalPeriod = fiscalPeriod;

        for (Object item : rawItems) {
            Map<String, Object> raw = (Map<String, Object>) item;
            String normalizedLine = (String) raw.get('normalized_line');
            if (String.isBlank(normalizedLine)) {
                continue;
            }

            Object valueObj = raw.get('value');
            Decimal normalizedValue = null;
            if (valueObj instanceof Decimal) {
                normalizedValue = (Decimal) valueObj;
            } else if (valueObj instanceof Integer) {
                normalizedValue = Decimal.valueOf((Integer) valueObj);
            } else if (valueObj instanceof Long) {
                normalizedValue = Decimal.valueOf((Long) valueObj);
            }

            Object pageObj = raw.get('source_page');
            Integer sourcePage = pageObj instanceof Integer ? (Integer) pageObj : 1;

            Object confObj = raw.get('confidence');
            Decimal confidence = 0.8;
            if (confObj instanceof Decimal) {
                confidence = (Decimal) confObj;
            } else if (confObj instanceof Integer) {
                confidence = Decimal.valueOf((Integer) confObj);
            }

            String itemStatementType = (String) raw.get('statement_type');
            String itemFiscalPeriod = (String) raw.get('fiscal_period');
            if (String.isBlank(resolvedStatementType) && !String.isBlank(itemStatementType)) {
                resolvedStatementType = itemStatementType;
            }
            if (String.isBlank(resolvedFiscalPeriod) && !String.isBlank(itemFiscalPeriod)) {
                resolvedFiscalPeriod = itemFiscalPeriod;
            }

            candidates.add(new Map<String, Object>{
                'normalized_line' => normalizedLine,
                'raw_label' => normalizedLine,
                'raw_value' => normalizedValue != null ? String.valueOf(normalizedValue) : '',
                'normalized_value' => normalizedValue,
                'evidence_id' => String.valueOf(evidenceId),
                'source_page' => sourcePage,
                'source_coordinates' => '',
                'confidence' => confidence,
                'exception_reason' => null,
                'status' => 'draft'
            });
        }

        if (candidates.isEmpty()) {
            return null;
        }

        return JSON.serialize(new Map<String, Object>{
            'document_id' => String.valueOf(docId),
            'statement_type' => resolvedStatementType,
            'fiscal_period' => resolvedFiscalPeriod,
            'parser_version' => 'einstein-flex-v1',
            'candidates' => candidates,
            'exceptions' => new List<Object>()
        });
    }

    private void markParsingStatus(Id docId, String status) {
        try {
            update new Spread_Document__c(
                Id = docId,
                Parsing_Status__c = status,
                Parsed_At__c = System.now()
            );
        } catch (Exception e) {
            // silent fail on status update
        }
    }
}
