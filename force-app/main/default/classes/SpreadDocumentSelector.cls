public inherited sharing virtual class SpreadDocumentSelector {

    public virtual List<Spread_Document__c> getByPilotRun(Id pilotRunId) {
        return [
            SELECT Id, Name, Pilot_Run__c, Borrower__c, Loan_Or_Opportunity__c,
                   Document_Type__c, Statement_Type__c, Fiscal_Period__c, Scenario_Type__c,
                   Source_System__c, ContentDocumentId__c,
                   Extraction_Status__c, Extracted_At__c, Page_Count__c, Contains_Confidential_Data__c
            FROM Spread_Document__c
            WHERE Pilot_Run__c = :pilotRunId
            WITH USER_MODE
            ORDER BY CreatedDate DESC
        ];
    }

    public virtual List<ContentVersion> getVersionsByDocumentIds(Set<Id> contentDocumentIds) {
        return [
            SELECT Id, Title, FileType, ContentSize, VersionData, ContentDocumentId
            FROM ContentVersion
            WHERE ContentDocumentId IN :contentDocumentIds
            AND IsLatest = true
            WITH USER_MODE
        ];
    }

    public virtual Spread_Document__c getById(Id documentId) {
        List<Spread_Document__c> docs = [
            SELECT Id, Name, Pilot_Run__c, Borrower__c, Loan_Or_Opportunity__c,
                   Document_Type__c, Statement_Type__c, Fiscal_Period__c, Scenario_Type__c,
                   Source_System__c, ContentDocumentId__c,
                   Extraction_Status__c, Extracted_At__c, Page_Count__c
            FROM Spread_Document__c
            WHERE Id = :documentId
            WITH USER_MODE
            LIMIT 1
        ];
        return docs.isEmpty() ? null : docs[0];
    }
}
