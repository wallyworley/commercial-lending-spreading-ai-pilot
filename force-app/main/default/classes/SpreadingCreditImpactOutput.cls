@JsonAccess(serializable='always' deserializable='always')
global class SpreadingCreditImpactOutput {
    @AuraEnabled
    @InvocableVariable(label='Fact Count')
    global Integer factCount;

    @AuraEnabled
    @InvocableVariable(label='Facts')
    global String facts;

    @AuraEnabled
    @InvocableVariable(label='Narrative Prompt')
    global String narrativePrompt;

    @AuraEnabled
    @InvocableVariable(label='Error Message')
    global String errorMessage;
}
