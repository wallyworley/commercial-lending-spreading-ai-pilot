@IsTest
private class SpreadDoclingCredentialServiceTest {
    @IsTest
    static void checkAuthorizedConnectionReturnsSuccess() {
        Test.setMock(HttpCalloutMock.class, new AuthCheckSuccessMock());

        Test.startTest();
        SpreadDoclingCredentialService.CredentialCheckResult result =
            SpreadDoclingCredentialService.checkAuthorizedConnection();
        Test.stopTest();

        Assert.isTrue(result.success, 'Expected authorized callout to succeed.');
        Assert.areEqual(200, result.statusCode);
        Assert.isTrue(result.body.contains('authorized'));
    }

    @IsTest
    static void checkAuthorizedConnectionReturnsFailurePayload() {
        Test.setMock(HttpCalloutMock.class, new AuthCheckFailureMock());

        Test.startTest();
        SpreadDoclingCredentialService.CredentialCheckResult result =
            SpreadDoclingCredentialService.checkAuthorizedConnection();
        Test.stopTest();

        Assert.isFalse(result.success, 'Expected unauthorized callout to fail.');
        Assert.areEqual(401, result.statusCode);
        Assert.isTrue(result.body.contains('Invalid API key'));
    }

    private class AuthCheckSuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            Assert.isTrue(request.getEndpoint().contains('/auth-check'));
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody('{"status":"authorized"}');
            return response;
        }
    }

    private class AuthCheckFailureMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(401);
            response.setBody('{"detail":"Invalid API key"}');
            return response;
        }
    }
}
