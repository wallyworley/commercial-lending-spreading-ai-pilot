@IsTest
private class DoclingKeepWarmSchedulableTest {
    private class SuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            System.assertEquals('GET', req.getMethod());
            System.assert(req.getEndpoint().contains('Spread_Docling_Service_V2/health'));
            System.assertEquals('CommercialSpreadingPilotKeepWarm/1.0', req.getHeader('User-Agent'));

            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody('{"status":"ok"}');
            return response;
        }
    }

    private class UnavailableMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(503);
            response.setBody('warming');
            return response;
        }
    }

    @IsTest
    static void executeMakesHealthCallout() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        Test.startTest();
        new DoclingKeepWarmSchedulable().execute(null);
        Test.stopTest();
    }

    @IsTest
    static void executeHandlesNonSuccessResponse() {
        Test.setMock(HttpCalloutMock.class, new UnavailableMock());

        Test.startTest();
        new DoclingKeepWarmSchedulable().execute(null);
        Test.stopTest();
    }
}
