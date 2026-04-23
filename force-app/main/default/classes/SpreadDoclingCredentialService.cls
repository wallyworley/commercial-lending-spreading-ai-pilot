public with sharing class SpreadDoclingCredentialService {
    private static final String DOCLING_SERVICE = 'Spread_Docling_Service_V2';

    public class CredentialCheckResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public Integer statusCode;
        @AuraEnabled public String body;
    }

    @AuraEnabled(cacheable=false)
    public static CredentialCheckResult checkAuthorizedConnection() {
        HttpRequest request = new HttpRequest();
        request.setMethod('GET');
        request.setEndpoint('callout:' + DOCLING_SERVICE + '/auth-check');
        request.setTimeout(30000);

        HttpResponse response = new Http().send(request);

        CredentialCheckResult result = new CredentialCheckResult();
        result.statusCode = response.getStatusCode();
        result.body = response.getBody();
        result.success = response.getStatusCode() >= 200 && response.getStatusCode() < 300;
        return result;
    }
}
