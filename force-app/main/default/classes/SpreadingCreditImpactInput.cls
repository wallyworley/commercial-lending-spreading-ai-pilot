@JsonAccess(serializable='always' deserializable='always')
global class SpreadingCreditImpactInput {
    @AuraEnabled
    @InvocableVariable(
        label='Path Result Ids'
        description='Up to 20 Spread_Path_Result__c Salesforce Ids to explain. Must be certified or exception-approved results from the current pilot run.'
        required=true
    )
    global List<String> pathResultIds;
}
