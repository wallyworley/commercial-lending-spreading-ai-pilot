@JsonAccess(serializable='always' deserializable='always')
global class SpreadingReportFactsOutput {
    @AuraEnabled
    @InvocableVariable(label='Pilot Run Id')
    global String pilotRunId;

    @AuraEnabled
    @InvocableVariable(label='Selected Fact Count')
    global Integer factCount;

    @AuraEnabled
    @InvocableVariable(label='Selected Facts Summary')
    global String selectedFactsSummary;

    @AuraEnabled
    @InvocableVariable(label='Narrative Prompt')
    global String narrativePrompt;

    @AuraEnabled
    @InvocableVariable(label='Error Message')
    global String errorMessage;
}
