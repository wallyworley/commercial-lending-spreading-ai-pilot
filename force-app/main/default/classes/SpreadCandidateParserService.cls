public with sharing class SpreadCandidateParserService {
    public static final String DEFAULT_PATH_KEY = 'salesforce_native_staging';

    public class ParserImportResult {
        @AuraEnabled public Id spreadDocumentId;
        @AuraEnabled public Integer lineItemCount = 0;
        @AuraEnabled public Integer pathResultCount = 0;
        @AuraEnabled public Integer exceptionCount = 0;
        @AuraEnabled public String parsingStatus;
        @AuraEnabled public String errorMessage;
    }

    public class ParserOutput {
        public String document_id;
        public String borrower;
        public String loan_or_opportunity;
        public String statement_type;
        public String fiscal_period;
        public String parser_version;
        public List<ParserCandidate> candidates;
        public List<ParserExceptionRow> exceptions;
    }

    public class ParserCandidate {
        public String normalized_line;
        public String raw_label;
        public String raw_value;
        public Decimal normalized_value;
        public String evidence_id;
        public Integer source_page;
        public String source_coordinates;
        public Decimal confidence;
        public String exception_reason;
        public String status;
    }

    public class ParserExceptionRow {
        public String reason;
        public String severity;
        public String evidence_id;
        public Integer source_page;
        public String raw_text;
    }

    public static ParserImportResult importParserOutput(Id spreadDocumentId, String parserJson, String pathKey) {
        ParserImportResult result = new ParserImportResult();
        result.spreadDocumentId = spreadDocumentId;

        if (spreadDocumentId == null) {
            result.errorMessage = 'Spread Document Id is required.';
            return result;
        }
        if (String.isBlank(parserJson)) {
            result.errorMessage = 'Parser JSON is required.';
            markParsingStatus(spreadDocumentId, 'Failed');
            return result;
        }

        ParserOutput output;
        try {
            output = (ParserOutput) JSON.deserialize(parserJson, ParserOutput.class);
        } catch (Exception error) {
            result.errorMessage = 'Parser JSON could not be deserialized: ' + error.getMessage();
            markParsingStatus(spreadDocumentId, 'Failed');
            createException(spreadDocumentId, result.errorMessage, 'Error');
            result.exceptionCount = 1;
            return result;
        }

        if (output == null || output.candidates == null || output.candidates.isEmpty()) {
            result.errorMessage = 'Parser JSON did not contain candidate spread lines.';
            markParsingStatus(spreadDocumentId, 'Needs Review');
            createException(spreadDocumentId, result.errorMessage, 'Warning');
            result.exceptionCount = 1;
            return result;
        }

        Spread_Document__c document = [
            SELECT Id, Pilot_Run__c, Statement_Type__c, Fiscal_Period__c
            FROM Spread_Document__c
            WHERE Id = :spreadDocumentId
            WITH USER_MODE
            LIMIT 1
        ];

        String resolvedPathKey = String.isBlank(pathKey) ? DEFAULT_PATH_KEY : pathKey;
        List<Spread_Line_Item__c> lineItems = new List<Spread_Line_Item__c>();
        List<ParserCandidate> acceptedCandidates = new List<ParserCandidate>();

        for (ParserCandidate candidate : output.candidates) {
            if (candidate == null || String.isBlank(candidate.normalized_line)) {
                continue;
            }
            acceptedCandidates.add(candidate);
            Id evidenceId = resolveEvidenceId(candidate.evidence_id);
            lineItems.add(new Spread_Line_Item__c(
                Name = candidate.normalized_line,
                Pilot_Run__c = document.Pilot_Run__c,
                Spread_Document__c = document.Id,
                Normalized_Line__c = candidate.normalized_line,
                Statement_Type__c = String.isBlank(output.statement_type) ? document.Statement_Type__c : output.statement_type,
                Fiscal_Period__c = String.isBlank(output.fiscal_period) ? document.Fiscal_Period__c : output.fiscal_period,
                Source_Page__c = candidate.source_page,
                Source_Coordinates__c = candidate.source_coordinates,
                Primary_Evidence__c = evidenceId,
                Material__c = true,
                Include_In_Report__c = false,
                Review_Note__c = 'Draft parser candidate. Requires analyst certification.'
            ));
        }

        if (lineItems.isEmpty()) {
            result.errorMessage = 'Parser JSON did not contain valid normalized candidate lines.';
            markParsingStatus(spreadDocumentId, 'Needs Review');
            createException(spreadDocumentId, result.errorMessage, 'Warning');
            result.exceptionCount = 1;
            return result;
        }

        insert lineItems;

        List<Spread_Path_Result__c> pathResults = new List<Spread_Path_Result__c>();
        for (Integer index = 0; index < lineItems.size(); index++) {
            ParserCandidate candidate = acceptedCandidates[index];
            Boolean exceptionFlag = candidate.status == 'exception' || !String.isBlank(candidate.exception_reason);
            pathResults.add(new Spread_Path_Result__c(
                Pilot_Run__c = document.Pilot_Run__c,
                Spread_Document__c = document.Id,
                Spread_Line_Item__c = lineItems[index].Id,
                Path_Key__c = resolvedPathKey,
                Candidate_Value__c = candidate.normalized_value,
                Raw_Label__c = candidate.raw_label,
                Raw_Value__c = candidate.raw_value,
                Primary_Evidence__c = lineItems[index].Primary_Evidence__c,
                Confidence__c = candidate.confidence,
                Exception_Flag__c = exceptionFlag,
                Exception_Reason__c = candidate.exception_reason,
                Exception_Status__c = exceptionFlag ? 'Open' : 'None',
                Certification_Status__c = exceptionFlag ? 'Exception Pending' : 'Uncertified',
                Error_Type__c = exceptionFlag ? 'mapping' : null
            ));
        }

        insert pathResults;

        Integer createdExceptions = createParserExceptions(document.Id, output.exceptions);
        result.lineItemCount = lineItems.size();
        result.pathResultCount = pathResults.size();
        result.exceptionCount = createdExceptions;
        result.parsingStatus = createdExceptions > 0 ? 'Needs Review' : 'Complete';
        markParsingStatus(document.Id, result.parsingStatus);
        return result;
    }

    private static Integer createParserExceptions(Id spreadDocumentId, List<ParserExceptionRow> exceptionRows) {
        if (exceptionRows == null || exceptionRows.isEmpty()) {
            return 0;
        }

        List<Spread_Exception__c> exceptions = new List<Spread_Exception__c>();
        for (ParserExceptionRow row : exceptionRows) {
            if (row == null || String.isBlank(row.reason)) {
                continue;
            }
            exceptions.add(new Spread_Exception__c(
                Spread_Document__c = spreadDocumentId,
                Exception_Reason__c = 'Parser Exception: ' + row.reason,
                Severity__c = normalizeSeverity(row.severity)
            ));
        }
        if (!exceptions.isEmpty()) {
            insert exceptions;
        }
        return exceptions.size();
    }

    private static void createException(Id spreadDocumentId, String reason, String severity) {
        Spread_Exception__c exceptionRecord = new Spread_Exception__c(
            Spread_Document__c = spreadDocumentId,
            Exception_Reason__c = reason,
            Severity__c = severity
        );
        insert exceptionRecord;
    }

    private static void markParsingStatus(Id spreadDocumentId, String status) {
        Spread_Document__c document = new Spread_Document__c(
            Id = spreadDocumentId,
            Parsing_Status__c = status,
            Parsed_At__c = System.now()
        );
        update document;
    }

    private static Id resolveEvidenceId(String rawId) {
        if (String.isBlank(rawId)) {
            return null;
        }
        try {
            Id resolved = Id.valueOf(rawId);
            if (resolved.getSObjectType() == Spread_Extraction_Evidence__c.SObjectType) {
                return resolved;
            }
        } catch (Exception error) {
            return null;
        }
        return null;
    }

    private static String normalizeSeverity(String severity) {
        if (String.isBlank(severity)) {
            return 'Warning';
        }
        String normalized = severity.trim().toLowerCase();
        if (normalized == 'hard_stop' || normalized == 'critical') {
            return 'Critical';
        }
        if (normalized == 'error') {
            return 'Error';
        }
        if (normalized == 'info') {
            return 'Info';
        }
        return 'Warning';
    }
}
