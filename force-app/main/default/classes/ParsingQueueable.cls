public with sharing class ParsingQueueable implements Queueable {
    private final Id spreadDocumentId;
    private final String pathKey;

    public ParsingQueueable(Id spreadDocumentId) {
        this(spreadDocumentId, null);
    }

    public ParsingQueueable(Id spreadDocumentId, String pathKey) {
        this.spreadDocumentId = spreadDocumentId;
        this.pathKey = pathKey;
    }

    public void execute(QueueableContext ctx) {
        SpreadEvidenceParserService.parseDocument(spreadDocumentId, pathKey);
    }
}
