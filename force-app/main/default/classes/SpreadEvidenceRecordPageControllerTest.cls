@IsTest
private class SpreadEvidenceRecordPageControllerTest {
    @IsTest
    static void returnsParentDocumentAndSourceFileContext() {
        Spread_Pilot_Run__c run = SpreadTestDataFactory.createPilotRun();
        Spread_Document__c document = SpreadTestDataFactory.createDocument(run.Id);

        ContentVersion version = new ContentVersion(
            Title = 'Evidence Source',
            PathOnClient = 'evidence-source.pdf',
            VersionData = Blob.valueOf('Synthetic PDF body')
        );
        insert version;
        version = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :version.Id];
        document.ContentDocumentId__c = version.ContentDocumentId;
        update document;

        SpreadEvidenceService.EvidenceImportResult result = SpreadEvidenceService.createTextEvidence(
            document.Id,
            'Revenue: $8,450,000',
            1,
            'Docling',
            'native_pdf'
        );

        Test.startTest();
        SpreadEvidenceRecordPageController.EvidenceView view =
            SpreadEvidenceRecordPageController.getEvidenceView(result.evidenceId);
        Test.stopTest();

        Assert.areEqual(result.evidenceId, view.evidenceId);
        Assert.areEqual(document.Id, view.spreadDocumentId);
        Assert.areEqual(document.Name, view.spreadDocumentName);
        Assert.areEqual(version.ContentDocumentId, view.contentDocumentId);
        Assert.areEqual('Revenue: $8,450,000', view.rawText);
    }

    @IsTest
    static void rejectsMissingRecordId() {
        Test.startTest();
        try {
            SpreadEvidenceRecordPageController.getEvidenceView(null);
            Assert.fail('Expected a handled exception for a missing evidence id.');
        } catch (AuraHandledException expected) {
            Assert.isTrue(true);
        }
        Test.stopTest();
    }
}
