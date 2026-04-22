@IsTest
private class SpreadEvidenceServiceTest {
    @IsTest
    static void createsEvidenceAndMarksDocumentPendingParse() {
        Spread_Pilot_Run__c run = SpreadTestDataFactory.createPilotRun();
        Spread_Document__c document = SpreadTestDataFactory.createDocument(run.Id);

        Test.startTest();
        SpreadEvidenceService.EvidenceImportResult result = SpreadEvidenceService.createTextEvidence(
            document.Id,
            'Revenue: $8,450,000',
            2,
            'Docling',
            'native_pdf'
        );
        Test.stopTest();

        Assert.isNotNull(result.evidenceId, 'Evidence Id should be returned.');
        Assert.areEqual('Complete', result.extractionStatus, 'Extraction status should be complete.');

        Spread_Document__c updatedDocument = [
            SELECT Extraction_Status__c, Parsing_Status__c, Page_Count__c
            FROM Spread_Document__c
            WHERE Id = :document.Id
        ];
        Assert.areEqual('Complete', updatedDocument.Extraction_Status__c);
        Assert.areEqual('Pending', updatedDocument.Parsing_Status__c);
        Assert.areEqual(2, updatedDocument.Page_Count__c);

        Spread_Extraction_Evidence__c evidence = [
            SELECT Spread_Document__c, Pilot_Run__c, Raw_Text__c, Source_Hash__c
            FROM Spread_Extraction_Evidence__c
            WHERE Id = :result.evidenceId
        ];
        Assert.areEqual(document.Id, evidence.Spread_Document__c);
        Assert.areEqual(run.Id, evidence.Pilot_Run__c);
        Assert.isTrue(evidence.Raw_Text__c.contains('Revenue'));
        Assert.isNotNull(evidence.Source_Hash__c);
    }
}
