@IsTest
private class ExtractionQueueableTest {
    private static Integer flakyDoclingCallCount = 0;

    @TestSetup
    static void setup() {
        SpreadTestDataFactory.createPilotRun();
    }

    @IsTest
    static void testExecuteSuccessfulExtraction() {
        Spread_Pilot_Run__c run = [SELECT Id FROM Spread_Pilot_Run__c LIMIT 1];
        Spread_Document__c doc = SpreadTestDataFactory.createDocument(run.Id);

        // Create a content version
        ContentVersion version = new ContentVersion();
        version.Title = 'Test Financial Statement';
        version.PathOnClient = 'test.pdf';
        version.VersionData = Blob.valueOf('Test PDF content');
        version.IsMajorVersion = true;
        insert version;

        version = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :version.Id];
        doc.ContentDocumentId__c = version.ContentDocumentId;
        update doc;

        // Mock HTTP callouts
        Test.setMock(HttpCalloutMock.class, new DoclingMockResponse());

        Test.startTest();
        System.enqueueJob(new ExtractionQueueable(doc.Id));
        Test.stopTest();

        Spread_Document__c updated = [
            SELECT Extraction_Status__c, Parsing_Status__c, Page_Count__c
            FROM Spread_Document__c
            WHERE Id = :doc.Id
        ];
        Assert.areEqual(
            'Complete',
            updated.Extraction_Status__c,
            'Status should be Complete. Extraction exception: ' + getExtractionExceptionReason(doc.Id)
        );
        Assert.areEqual('Pending', updated.Parsing_Status__c, 'Parsing should be pending after evidence import');
        Assert.areEqual(5, updated.Page_Count__c, 'Page count should be set from response');

        List<Spread_Extraction_Evidence__c> evidence = [
            SELECT Raw_Text__c, Raw_Table_Markdown__c, Extraction_Engine__c, Source_Hash__c
            FROM Spread_Extraction_Evidence__c
            WHERE Spread_Document__c = :doc.Id
        ];
        Assert.areEqual(1, evidence.size(), 'Extraction should create one evidence record');
        Assert.isTrue(evidence[0].Raw_Text__c.contains('Revenue'), 'Evidence text should contain extracted content');
        Assert.areEqual('native_pdf', evidence[0].Extraction_Engine__c, 'Engine should come from service response');
        Assert.isNotNull(evidence[0].Source_Hash__c, 'Evidence hash should be set');
    }

    @IsTest
    static void testExecuteWithNullDocument() {
        // Pass an ID that won't exist in the database
        Id fakeDocId = Spread_Document__c.SObjectType.getDescribe().getKeyPrefix() + '000000000000';

        Test.startTest();
        System.enqueueJob(new ExtractionQueueable(fakeDocId));
        Test.stopTest();

        // Should not throw exception, just return early
        Assert.isTrue(true, 'Execution should complete without error');
    }

    @IsTest
    static void testExecuteWithMissingContentVersion() {
        Spread_Pilot_Run__c run = [SELECT Id FROM Spread_Pilot_Run__c LIMIT 1];
        Spread_Document__c doc = SpreadTestDataFactory.createDocument(run.Id);
        doc.ContentDocumentId__c = '0691y00000DT8GAAX'; // Invalid ID
        update doc;

        Test.startTest();
        System.enqueueJob(new ExtractionQueueable(doc.Id));
        Test.stopTest();

        Spread_Document__c updated = [SELECT Extraction_Status__c FROM Spread_Document__c WHERE Id = :doc.Id];
        Assert.areEqual('Failed', updated.Extraction_Status__c, 'Status should be Failed');
    }

    @IsTest
    static void testExecuteWithDoclingHttpError() {
        Spread_Pilot_Run__c run = [SELECT Id FROM Spread_Pilot_Run__c LIMIT 1];
        Spread_Document__c doc = SpreadTestDataFactory.createDocument(run.Id);

        ContentVersion version = new ContentVersion();
        version.Title = 'Test Statement';
        version.PathOnClient = 'test.pdf';
        version.VersionData = Blob.valueOf('Test content');
        version.IsMajorVersion = true;
        insert version;

        version = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :version.Id];
        doc.ContentDocumentId__c = version.ContentDocumentId;
        update doc;

        // Mock HTTP error response
        Test.setMock(HttpCalloutMock.class, new DoclingErrorMockResponse());

        Test.startTest();
        System.enqueueJob(new ExtractionQueueable(doc.Id));
        Test.stopTest();

        Spread_Document__c updated = [SELECT Extraction_Status__c FROM Spread_Document__c WHERE Id = :doc.Id];
        Assert.areEqual('Failed', updated.Extraction_Status__c, 'Status should be Failed on HTTP error');

        List<Spread_Exception__c> exceptions = [
            SELECT Exception_Reason__c
            FROM Spread_Exception__c
            WHERE Spread_Document__c = :doc.Id
        ];
        Assert.areEqual(1, exceptions.size(), 'Exception record should be created');
        Assert.isTrue(exceptions[0].Exception_Reason__c.contains('Extraction Error'), 'Exception reason should be set');
    }

    @IsTest
    static void testExecuteRetriesTransientDoclingLoadingErrorUntilFinalFailure() {
        Spread_Document__c doc = createDocumentWithContentVersion();
        flakyDoclingCallCount = 0;
        Test.setMock(HttpCalloutMock.class, new FlakyDoclingMockResponse());

        Test.startTest();
        System.enqueueJob(new ExtractionQueueable(doc.Id));
        Test.stopTest();

        Spread_Document__c updated = [
            SELECT Extraction_Status__c
            FROM Spread_Document__c
            WHERE Id = :doc.Id
        ];
        Assert.areEqual('Failed', updated.Extraction_Status__c, 'Repeated transient failures should eventually fail.');

        List<Spread_Exception__c> exceptions = [
            SELECT Exception_Reason__c
            FROM Spread_Exception__c
            WHERE Spread_Document__c = :doc.Id
        ];
        Assert.areEqual(1, exceptions.size(), 'Exhausted retries should create one final failure exception.');
        Assert.isTrue(
            exceptions[0].Exception_Reason__c.contains('Extraction Error'),
            'Final exception should be recorded as an extraction error.'
        );
    }

    @IsTest
    static void testExecuteFailsTransientErrorAfterMaxAttempts() {
        Spread_Document__c doc = createDocumentWithContentVersion();
        Test.setMock(HttpCalloutMock.class, new DoclingLoadingMockResponse());

        Test.startTest();
        System.enqueueJob(new ExtractionQueueable(doc.Id, ExtractionQueueable.MAX_TRANSIENT_ATTEMPTS));
        Test.stopTest();

        Spread_Document__c updated = [
            SELECT Extraction_Status__c
            FROM Spread_Document__c
            WHERE Id = :doc.Id
        ];
        Assert.areEqual('Failed', updated.Extraction_Status__c, 'Max retry attempt should fail the document.');

        List<Spread_Exception__c> exceptions = [
            SELECT Exception_Reason__c
            FROM Spread_Exception__c
            WHERE Spread_Document__c = :doc.Id
        ];
        Assert.areEqual(1, exceptions.size(), 'Final retry failure should create an exception.');
        Assert.isTrue(exceptions[0].Exception_Reason__c.contains('HTTP 503'), 'Exception should preserve the HTTP status.');
    }

    @IsTest
    static void testExecuteCreatesEvidenceOnly() {
        Spread_Pilot_Run__c run = [SELECT Id FROM Spread_Pilot_Run__c LIMIT 1];
        Spread_Document__c doc = SpreadTestDataFactory.createDocument(run.Id);
        doc.Statement_Type__c = 'income_statement';
        doc.Fiscal_Period__c = 'FY2025';
        update doc;

        ContentVersion version = new ContentVersion();
        version.Title = 'Test Statement';
        version.PathOnClient = 'test.pdf';
        version.VersionData = Blob.valueOf('Test content');
        version.IsMajorVersion = true;
        insert version;

        version = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :version.Id];
        doc.ContentDocumentId__c = version.ContentDocumentId;
        update doc;

        Test.setMock(HttpCalloutMock.class, new DoclingMockResponse());

        Test.startTest();
        System.enqueueJob(new ExtractionQueueable(doc.Id));
        Test.stopTest();

        List<Spread_Extraction_Evidence__c> items = [
            SELECT Id, Pilot_Run__c, Spread_Document__c, Provider__c, Extraction_Status__c
            FROM Spread_Extraction_Evidence__c
            WHERE Spread_Document__c = :doc.Id
        ];

        Assert.isTrue(items.size() > 0, 'Evidence should be created');
        for (Spread_Extraction_Evidence__c item : items) {
            Assert.areEqual(run.Id, item.Pilot_Run__c, 'Pilot run should match');
            Assert.areEqual(doc.Id, item.Spread_Document__c, 'Document should match');
            Assert.areEqual('Docling', item.Provider__c, 'Provider should be captured');
            Assert.areEqual('Success', item.Extraction_Status__c, 'Evidence status should be Success');
        }
    }

    @IsTest
    static void testExecuteWithInvalidJsonResponse() {
        Spread_Pilot_Run__c run = [SELECT Id FROM Spread_Pilot_Run__c LIMIT 1];
        Spread_Document__c doc = SpreadTestDataFactory.createDocument(run.Id);

        ContentVersion version = new ContentVersion();
        version.Title = 'Test Statement';
        version.PathOnClient = 'test.pdf';
        version.VersionData = Blob.valueOf('Test content');
        version.IsMajorVersion = true;
        insert version;

        version = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :version.Id];
        doc.ContentDocumentId__c = version.ContentDocumentId;
        update doc;

        // Mock invalid JSON response
        Test.setMock(HttpCalloutMock.class, new InvalidJsonMockResponse());

        Test.startTest();
        System.enqueueJob(new ExtractionQueueable(doc.Id));
        Test.stopTest();

        Spread_Document__c updated = [SELECT Extraction_Status__c FROM Spread_Document__c WHERE Id = :doc.Id];
        Assert.areEqual('Failed', updated.Extraction_Status__c, 'Status should be Failed on invalid JSON');
    }

    @IsTest
    static void testExecuteWithBlankTablesResponse() {
        Spread_Document__c doc = createDocumentWithContentVersion();

        Test.setMock(HttpCalloutMock.class, new BlankTablesMockResponse());

        Test.startTest();
        System.enqueueJob(new ExtractionQueueable(doc.Id));
        Test.stopTest();

        assertFailedWithoutEvidence(doc.Id, 'Blank extracted tables should fail extraction');
    }

    @IsTest
    static void testExecuteWithEmptyTablesArrayResponse() {
        Spread_Document__c doc = createDocumentWithContentVersion();

        Test.setMock(HttpCalloutMock.class, new EmptyTablesArrayMockResponse());

        Test.startTest();
        System.enqueueJob(new ExtractionQueueable(doc.Id));
        Test.stopTest();

        assertFailedWithoutEvidence(doc.Id, 'Empty extracted table array should fail extraction');
    }

    @IsTest
    static void testExecuteWithStringPageCountResponse() {
        Spread_Document__c doc = createDocumentWithContentVersion();

        Test.setMock(HttpCalloutMock.class, new StringPageCountMockResponse());

        Test.startTest();
        System.enqueueJob(new ExtractionQueueable(doc.Id));
        Test.stopTest();

        Spread_Document__c updated = [
            SELECT Extraction_Status__c, Parsing_Status__c, Page_Count__c
            FROM Spread_Document__c
            WHERE Id = :doc.Id
        ];
        Assert.areEqual('Complete', updated.Extraction_Status__c, 'String page count responses should still succeed');
        Assert.areEqual('Pending', updated.Parsing_Status__c, 'Parsing should still be queued after successful extraction');
        Assert.areEqual(7, updated.Page_Count__c, 'String page count should be normalized to a number');
    }

    private static Spread_Document__c createDocumentWithContentVersion() {
        Spread_Pilot_Run__c run = [SELECT Id FROM Spread_Pilot_Run__c LIMIT 1];
        Spread_Document__c doc = SpreadTestDataFactory.createDocument(run.Id);

        ContentVersion version = new ContentVersion();
        version.Title = 'Test Statement';
        version.PathOnClient = 'test.pdf';
        version.VersionData = Blob.valueOf('Test content');
        version.IsMajorVersion = true;
        insert version;

        version = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :version.Id];
        doc.ContentDocumentId__c = version.ContentDocumentId;
        update doc;
        return doc;
    }

    private static void assertFailedWithoutEvidence(Id docId, String message) {
        Spread_Document__c updated = [
            SELECT Extraction_Status__c
            FROM Spread_Document__c
            WHERE Id = :docId
        ];
        Assert.areEqual('Failed', updated.Extraction_Status__c, message);

        List<Spread_Extraction_Evidence__c> evidence = [
            SELECT Id
            FROM Spread_Extraction_Evidence__c
            WHERE Spread_Document__c = :docId
        ];
        Assert.areEqual(0, evidence.size(), 'No evidence should be created for empty extraction output');
    }

    private static String getExtractionExceptionReason(Id docId) {
        List<Spread_Exception__c> exceptions = [
            SELECT Exception_Reason__c
            FROM Spread_Exception__c
            WHERE Spread_Document__c = :docId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return exceptions.isEmpty() ? 'none' : exceptions[0].Exception_Reason__c;
    }

    // Mock HTTP responses

    private class DoclingMockResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            if (req.getEndpoint().contains('/extract')) {
                res.setBody('{"tables": "| Revenue | 1000000 |\\n| COGS | 600000 |", "page_count": 5, "job_id": "job_123", "engine": "native_pdf"}');
            } else {
                return null;
            }
            return res;
        }
    }

    private class DoclingErrorMockResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            if (req.getEndpoint().contains('/extract')) {
                HttpResponse res = new HttpResponse();
                res.setStatusCode(500);
                res.setHeader('Content-Type', 'application/json');
                res.setBody('{"error": "Internal server error"}');
                return res;
            }
            return null;
        }
    }

    private class DoclingLoadingMockResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(503);
            res.setHeader('Content-Type', 'text/html');
            res.setBody('<!doctype html><title>Render - Application loading</title>');
            return res;
        }
    }

    private class FlakyDoclingMockResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            flakyDoclingCallCount++;
            HttpResponse res = new HttpResponse();
            if (flakyDoclingCallCount == 1) {
                res.setStatusCode(503);
                res.setHeader('Content-Type', 'text/html');
                res.setBody('<!doctype html><title>Render - Application loading</title>');
                return res;
            }

            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"tables": "| Revenue | 1000000 |", "page_count": 3, "job_id": "job_retry", "engine": "native_pdf"}');
            return res;
        }
    }

    private class InvalidJsonMockResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            if (req.getEndpoint().contains('/extract')) {
                res.setBody('This is not valid JSON');
            } else {
                return null;
            }
            return res;
        }
    }

    private class BlankTablesMockResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            if (req.getEndpoint().contains('/extract')) {
                res.setBody('{"tables": "   ", "page_count": 2, "job_id": "job_blank", "engine": "native_pdf"}');
            } else {
                return null;
            }
            return res;
        }
    }

    private class EmptyTablesArrayMockResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            if (req.getEndpoint().contains('/extract')) {
                res.setBody('{"tables": "[]", "page_count": 2, "job_id": "job_empty", "engine": "native_pdf"}');
            } else {
                return null;
            }
            return res;
        }
    }

    private class StringPageCountMockResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            if (req.getEndpoint().contains('/extract')) {
                res.setBody('{"tables": "| Revenue | 1000000 |", "page_count": "7", "job_id": "job_string_count", "engine": "native_pdf"}');
            } else {
                return null;
            }
            return res;
        }
    }
}
