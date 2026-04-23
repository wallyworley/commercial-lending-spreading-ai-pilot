public with sharing class ParseExtractedFinancialEvidence {
    @InvocableMethod(
        label='Parse Extracted Financial Evidence'
        description='Parses stored extraction evidence for a document into draft spread candidates. Use this only after extraction is complete. The action creates draft line items and path results; analysts must still certify material values.'
        category='Commercial Lending Spreading'
    )
    public static List<SpreadingParseOutput> parse(List<SpreadingParseInput> requests) {
        List<SpreadingParseOutput> outputs = new List<SpreadingParseOutput>();
        for (SpreadingParseInput request : requests) {
            Id spreadDocumentId = null;
            if (request != null && !String.isBlank(request.spreadDocumentId)) {
                try {
                    spreadDocumentId = Id.valueOf(request.spreadDocumentId);
                } catch (Exception error) {
                    SpreadingParseOutput invalid = new SpreadingParseOutput();
                    invalid.spreadDocumentId = request.spreadDocumentId;
                    invalid.pathKey = request.pathKey;
                    invalid.parsingStatus = 'Failed';
                    invalid.errorMessage = 'A valid Spread_Document__c Id is required.';
                    outputs.add(invalid);
                    continue;
                }
            }
            outputs.add(SpreadEvidenceParserService.parseDocument(spreadDocumentId, request == null ? null : request.pathKey));
        }
        return outputs;
    }
}
