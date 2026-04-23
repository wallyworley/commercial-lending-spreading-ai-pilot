public class DoclingKeepWarmSchedulable implements Schedulable, Database.AllowsCallouts {
    private static final String DOCLING_SERVICE = 'Spread_Docling_Service_V2';
    private static final Integer REQUEST_TIMEOUT_MS = 10000;
    private static final String KEEP_WARM_PATH = '/health';

    public void execute(SchedulableContext ctx) {
        try {
            HttpRequest req = new HttpRequest();
            req.setMethod('GET');
            req.setEndpoint('callout:' + DOCLING_SERVICE + KEEP_WARM_PATH);
            req.setTimeout(REQUEST_TIMEOUT_MS);
            req.setHeader('User-Agent', 'CommercialSpreadingPilotKeepWarm/1.0');

            HttpResponse response = new Http().send(req);
            Integer statusCode = response.getStatusCode();

            if (statusCode < 200 || statusCode >= 300) {
                System.debug(LoggingLevel.WARN,
                    'Docling keep-warm returned non-success status ' + statusCode +
                    ' with body: ' + response.getBody());
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN,
                'Docling keep-warm failed: ' + e.getTypeName() + ': ' + e.getMessage());
        }
    }
}
