@JsonAccess(serializable='always' deserializable='always')
global class SpreadingPilotRunSummaryOutput {
    @AuraEnabled
    @InvocableVariable(label='Pilot Run Id')
    global String pilotRunId;

    @AuraEnabled
    @InvocableVariable(label='Pilot Run Name')
    global String pilotRunName;

    @AuraEnabled
    @InvocableVariable(label='Status')
    global String status;

    @AuraEnabled
    @InvocableVariable(label='Portfolio')
    global String portfolio;

    @AuraEnabled
    @InvocableVariable(label='Document Count')
    global Integer documentCount;

    @AuraEnabled
    @InvocableVariable(label='Line Item Count')
    global Integer lineItemCount;

    @AuraEnabled
    @InvocableVariable(label='Scorecard Summary')
    global String scorecardSummary;

    @AuraEnabled
    @InvocableVariable(label='Gate Decision')
    global String gateDecision;

    @AuraEnabled
    @InvocableVariable(label='Has Blocking Issue')
    global Boolean hasBlockingIssue;

    @AuraEnabled
    @InvocableVariable(label='Error Message')
    global String errorMessage;
}
