@JsonAccess(serializable='always' deserializable='always')
global class SpreadingMaterialErrorsOutput {
    @AuraEnabled
    @InvocableVariable(label='Pilot Run Id')
    global String pilotRunId;

    @AuraEnabled
    @InvocableVariable(label='Material Error Count')
    global Integer materialErrorCount;

    @AuraEnabled
    @InvocableVariable(label='Material Error Summary')
    global String materialErrorSummary;

    @AuraEnabled
    @InvocableVariable(label='Error Message')
    global String errorMessage;
}
