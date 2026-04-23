public class SpreadingParseOutput {
    @AuraEnabled @InvocableVariable public String spreadDocumentId;
    @AuraEnabled @InvocableVariable public String pathKey;
    @AuraEnabled @InvocableVariable public String parserVersion;
    @AuraEnabled @InvocableVariable public Integer evidenceBlockCount;
    @AuraEnabled @InvocableVariable public Integer lineItemCount;
    @AuraEnabled @InvocableVariable public Integer pathResultCount;
    @AuraEnabled @InvocableVariable public Integer exceptionCount;
    @AuraEnabled @InvocableVariable public String parsingStatus;
    @AuraEnabled @InvocableVariable public String errorMessage;
}
