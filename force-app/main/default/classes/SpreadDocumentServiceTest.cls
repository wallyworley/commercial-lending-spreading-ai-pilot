@IsTest
private class SpreadDocumentServiceTest {
    private class MissingVersionSelector extends SpreadDocumentSelector {
        public override List<ContentVersion> getVersionsByDocumentIds(Set<Id> contentDocumentIds) {
            return new List<ContentVersion>();
        }
    }

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
    static void testOnUploadCreatesDocumentWhenVersionMetadataIsNotReady() {
        Spread_Pilot_Run__c run = [SELECT Id FROM Spread_Pilot_Run__c LIMIT 1];

        ContentVersion version = new ContentVersion();
        version.Title = 'Lagging Metadata Statement';
        version.PathOnClient = 'lagging-metadata.pdf';
        version.VersionData = Blob.valueOf('Test content');
        version.IsMajorVersion = true;
        insert version;

        version = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :version.Id];

        SpreadDocumentSelector originalSelector = SpreadDocumentService.documentSelector;
        SpreadDocumentService.documentSelector = new MissingVersionSelector();

        Test.startTest();
        List<Id> createdDocIds = SpreadDocumentService.onUpload(
            run.Id,
            new List<String>{ version.ContentDocumentId }
        );
        Test.stopTest();

        SpreadDocumentService.documentSelector = originalSelector;

        Assert.areEqual(1, createdDocIds.size(), 'The upload should still create a document row.');
        Spread_Document__c createdDocument = [
            SELECT Name, ContentDocumentId__c
            FROM Spread_Document__c
            WHERE Id = :createdDocIds[0]
        ];
        Assert.areEqual(version.ContentDocumentId, createdDocument.ContentDocumentId__c);
        Assert.isTrue(
            createdDocument.Name.startsWith('Uploaded Financial Document'),
            'The fallback document name should be applied when metadata is not ready.'
        );
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
        SpreadEvidenceService.createTextEvidence(
            doc.Id,
            'Revenue: $8,450,000',
            1,
            'Docling',
            'native_pdf'
        );

        List<SpreadDocumentService.DocumentRow> rows = SpreadDocumentService.getDocuments(run.Id);

        Assert.areEqual(1, rows.size(), 'Should return one document');
        Assert.areEqual(doc.Id, rows[0].id, 'IDs should match');
        Assert.areEqual('Pending', rows[0].parsingStatus, 'Parsing status should be surfaced to the workbench.');
        Assert.areEqual(1, rows[0].evidenceCount, 'Evidence count should be included for parse readiness.');
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

    @IsTest
    static void testParseDocumentCreatesDraftCandidates() {
        Spread_Pilot_Run__c run = SpreadTestDataFactory.createPilotRun();
        Spread_Document__c doc = SpreadTestDataFactory.createDocument(run.Id);
        SpreadEvidenceService.createTextEvidence(
            doc.Id,
            'Revenue: $8,450,000\nEBITDA: $1,530,000',
            1,
            'Docling',
            'native_pdf'
        );

        Test.startTest();
        SpreadingParseOutput result = SpreadDocumentService.parseDocument(doc.Id, null);
        Test.stopTest();

        Assert.areEqual('Complete', result.parsingStatus, 'Expected parsing to complete for mapped evidence.');
        Assert.areEqual(2, result.lineItemCount, 'Expected two mapped line items.');
        Assert.areEqual(2, result.pathResultCount, 'Expected two path results.');
    }

    @IsTest
    static void testParseReadyDocumentsParsesOnlyEligibleRows() {
        Spread_Pilot_Run__c run = SpreadTestDataFactory.createPilotRun();

        Spread_Document__c readyDoc = SpreadTestDataFactory.createDocument(run.Id);
        Spread_Document__c pendingDoc = SpreadTestDataFactory.createDocument(run.Id);
        pendingDoc.Name = 'Pending Extraction';
        pendingDoc.Extraction_Status__c = 'Pending';
        update pendingDoc;

        Spread_Document__c parsedDoc = SpreadTestDataFactory.createDocument(run.Id);
        parsedDoc.Name = 'Already Parsed';
        parsedDoc.Parsing_Status__c = 'Complete';
        update parsedDoc;

        SpreadEvidenceService.createTextEvidence(
            readyDoc.Id,
            'Revenue: $8,450,000',
            1,
            'Docling',
            'native_pdf'
        );

        Test.startTest();
        SpreadDocumentService.BulkParseResult result = SpreadDocumentService.parseReadyDocuments(run.Id, null);
        Test.stopTest();

        Assert.areEqual(1, result.attemptedCount, 'Only one document should be eligible.');
        Assert.areEqual(1, result.parsedCount, 'The ready document should be parsed.');
        Assert.areEqual(2, result.skippedCount, 'The non-eligible documents should be skipped.');
        Assert.areEqual(0, result.failedCount, 'No bulk parse failures were expected.');
    }
}
