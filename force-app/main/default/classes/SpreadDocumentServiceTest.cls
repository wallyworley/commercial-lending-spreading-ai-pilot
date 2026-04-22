@IsTest
private class SpreadDocumentServiceTest {
    @TestSetup
    static void setup() {
        SpreadTestDataFactory.createPilotRun();
    }

    @IsTest
    static void testOnUploadWithValidContentDocuments() {
        Spread_Pilot_Run__c run = [SELECT Id FROM Spread_Pilot_Run__c LIMIT 1];

        // Create a content document for testing
        ContentVersion version = new ContentVersion();
        version.Title = 'Test Financial Statement';
        version.PathOnClient = 'test-statement.pdf';
        version.VersionData = Blob.valueOf('Test PDF content');
        version.IsMajorVersion = true;
        insert version;

        version = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :version.Id];
        List<String> contentDocIds = new List<String>{ version.ContentDocumentId };

        List<Id> createdDocIds = SpreadDocumentService.onUpload(run.Id, contentDocIds);

        Assert.isTrue(createdDocIds.size() > 0, 'Should return created document IDs');
        Assert.areEqual(1, createdDocIds.size(), 'Should create one document');

        List<Spread_Document__c> docs = [
            SELECT Id, Extraction_Status__c, Source_System__c
            FROM Spread_Document__c
            WHERE Id IN :createdDocIds
        ];

        Assert.areEqual(1, docs.size(), 'One document should be created');
        Assert.areEqual('Analyst Upload', docs[0].Source_System__c, 'Source should be Analyst Upload');
    }

    @IsTest
    static void testOnUploadCreatesContentDocumentLink() {
        Spread_Pilot_Run__c run = [SELECT Id FROM Spread_Pilot_Run__c LIMIT 1];

        ContentVersion version = new ContentVersion();
        version.Title = 'Test Statement';
        version.PathOnClient = 'test.pdf';
        version.VersionData = Blob.valueOf('Test content');
        version.IsMajorVersion = true;
        insert version;

        version = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :version.Id];
        List<String> contentDocIds = new List<String>{ version.ContentDocumentId };

        List<Id> createdDocIds = SpreadDocumentService.onUpload(run.Id, contentDocIds);

        List<ContentDocumentLink> links = [
            SELECT LinkedEntityId, ContentDocumentId
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :version.ContentDocumentId
            AND LinkedEntityId IN :createdDocIds
        ];

        Assert.isTrue(links.size() > 0, 'ContentDocumentLink should be created');
        Assert.areEqual(createdDocIds[0], links[0].LinkedEntityId, 'Link should point to Spread_Document__c');
    }

    @IsTest
    static void testGetDocumentsReturnsEmptyWhenNoRunId() {
        Test.startTest();
        List<SpreadDocumentService.DocumentRow> docs = SpreadDocumentService.getDocuments(null);
        Test.stopTest();

        Assert.areEqual(0, docs.size(), 'Should return empty list when run ID is null');
    }

    @IsTest
    static void testGetDocumentsReturnsCreatedDocuments() {
        Spread_Pilot_Run__c run = SpreadTestDataFactory.createPilotRun();
        Spread_Document__c doc = SpreadTestDataFactory.createDocument(run.Id);

        List<SpreadDocumentService.DocumentRow> rows = SpreadDocumentService.getDocuments(run.Id);

        Assert.areEqual(1, rows.size(), 'Should return one document');
        Assert.areEqual(doc.Id, rows[0].id, 'IDs should match');
    }

    @IsTest
    static void testRetryExtractionUpdatesStatus() {
        Spread_Pilot_Run__c run = SpreadTestDataFactory.createPilotRun();
        Spread_Document__c doc = SpreadTestDataFactory.createDocument(run.Id);
        doc.Extraction_Status__c = 'Failed';
        update doc;

        SpreadDocumentService.retryExtraction(doc.Id);

        Spread_Document__c updated = [SELECT Extraction_Status__c FROM Spread_Document__c WHERE Id = :doc.Id];
        Assert.areEqual('Pending', updated.Extraction_Status__c, 'Status should be reset to Pending');
    }
}
