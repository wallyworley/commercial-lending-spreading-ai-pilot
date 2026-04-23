public class DoclingKeepWarmSchedulable implements Schedulable, Database.AllowsCallouts {
    private static final String DOCLING_SERVICE = 'Spread_Docling_Service_V2';

    public void execute(SchedulableContext ctx) {
        try {
            HttpRequest req = new HttpRequest();
            req.setMethod('GET');
            req.setEndpoint('callout:' + DOCLING_SERVICE + '/health');
            req.setTimeout(30000);
            new Http().send(req);
        } catch (Exception e) {
            // Silent — this is best-effort keep-warm, not critical path
        }
    }
}
