public with sharing class SpreadEvidenceRecordPageController {
    public class EvidenceView {
        @AuraEnabled public Id evidenceId;
        @AuraEnabled public String evidenceName;
        @AuraEnabled public Id spreadDocumentId;
        @AuraEnabled public String spreadDocumentName;
        @AuraEnabled public Id contentDocumentId;
        @AuraEnabled public String provider;
        @AuraEnabled public String extractionEngine;
        @AuraEnabled public String extractionStatus;
        @AuraEnabled public String evidenceType;
        @AuraEnabled public Decimal sourcePage;
        @AuraEnabled public Decimal extractionConfidence;
        @AuraEnabled public String rawText;
        @AuraEnabled public String rawTableMarkdown;
    }

    @AuraEnabled(cacheable=true)
    public static EvidenceView getEvidenceView(Id evidenceId) {
        if (evidenceId == null) {
            throw new AuraHandledException('Spread extraction evidence ID is required.');
        }

        List<Spread_Extraction_Evidence__c> evidences = [
            SELECT Id, Name, Spread_Document__c, Spread_Document__r.Name,
                   Spread_Document__r.ContentDocumentId__c, Provider__c, Extraction_Engine__c,
                   Extraction_Status__c, Evidence_Type__c, Source_Page__c,
                   Extraction_Confidence__c, Raw_Text__c, Raw_Table_Markdown__c
            FROM Spread_Extraction_Evidence__c
            WHERE Id = :evidenceId
            WITH USER_MODE
            LIMIT 1
        ];

        if (evidences.isEmpty()) {
            throw new AuraHandledException('Spread extraction evidence was not found.');
        }

        Spread_Extraction_Evidence__c evidence = evidences[0];
        EvidenceView view = new EvidenceView();
        view.evidenceId = evidence.Id;
        view.evidenceName = evidence.Name;
        view.spreadDocumentId = evidence.Spread_Document__c;
        view.spreadDocumentName = evidence.Spread_Document__r == null ? null : evidence.Spread_Document__r.Name;
        view.contentDocumentId = evidence.Spread_Document__r == null ? null : (Id) evidence.Spread_Document__r.ContentDocumentId__c;
        view.provider = evidence.Provider__c;
        view.extractionEngine = evidence.Extraction_Engine__c;
        view.extractionStatus = evidence.Extraction_Status__c;
        view.evidenceType = evidence.Evidence_Type__c;
        view.sourcePage = evidence.Source_Page__c;
        view.extractionConfidence = evidence.Extraction_Confidence__c;
        view.rawText = evidence.Raw_Text__c;
        view.rawTableMarkdown = evidence.Raw_Table_Markdown__c;
        return view;
    }
}
