public with sharing class SpreadEvidenceService {
    public class EvidenceImportResult {
        @AuraEnabled public Id evidenceId;
        @AuraEnabled public Id spreadDocumentId;
        @AuraEnabled public String extractionStatus;
        @AuraEnabled public Integer pageCount;
        @AuraEnabled public String errorMessage;
    }

    public static EvidenceImportResult createTextEvidence(
        Id spreadDocumentId,
        String rawText,
        Integer pageCount,
        String provider,
        String extractionEngine
    ) {
        EvidenceImportResult result = new EvidenceImportResult();
        result.spreadDocumentId = spreadDocumentId;
        result.pageCount = pageCount;

        if (spreadDocumentId == null) {
            result.errorMessage = 'Spread Document Id is required.';
            return result;
        }
        if (String.isBlank(rawText)) {
            result.errorMessage = 'Raw extraction text is required.';
            markDocument(spreadDocumentId, 'Needs Review', pageCount);
            return result;
        }

        Spread_Document__c document = [
            SELECT Id, Pilot_Run__c
            FROM Spread_Document__c
            WHERE Id = :spreadDocumentId
            WITH USER_MODE
            LIMIT 1
        ];

        Spread_Extraction_Evidence__c evidence = new Spread_Extraction_Evidence__c(
            Spread_Document__c = document.Id,
            Pilot_Run__c = document.Pilot_Run__c,
            Provider__c = String.isBlank(provider) ? 'Docling' : provider,
            Extraction_Engine__c = String.isBlank(extractionEngine) ? 'unknown' : extractionEngine,
            Source_Page__c = 1,
            Evidence_Type__c = 'Text',
            Raw_Text__c = rawText,
            Raw_Table_Markdown__c = rawText,
            Extraction_Status__c = 'Success',
            Extraction_Confidence__c = 0.95,
            Source_Hash__c = hash(rawText)
        );
        insert evidence;

        markDocument(document.Id, 'Complete', pageCount);

        result.evidenceId = evidence.Id;
        result.extractionStatus = 'Complete';
        return result;
    }

    private static void markDocument(Id spreadDocumentId, String status, Integer pageCount) {
        Spread_Document__c updateDocument = new Spread_Document__c(
            Id = spreadDocumentId,
            Extraction_Status__c = status,
            Extracted_At__c = System.now(),
            Parsing_Status__c = status == 'Complete' ? 'Pending' : 'Not Started'
        );
        if (pageCount != null) {
            updateDocument.Page_Count__c = pageCount;
        }
        update updateDocument;
    }

    private static String hash(String rawText) {
        Blob digest = Crypto.generateDigest('SHA-256', Blob.valueOf(rawText));
        return EncodingUtil.convertToHex(digest);
    }
}
