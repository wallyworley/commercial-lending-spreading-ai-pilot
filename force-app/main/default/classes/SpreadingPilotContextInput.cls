@JsonAccess(serializable='always' deserializable='always')
global class SpreadingPilotContextInput {
    @AuraEnabled
    @InvocableVariable(
        label='Pilot Run Id'
        description='Salesforce Id for the Spread Pilot Run to review.'
        required=true
    )
    global String pilotRunId;

    @AuraEnabled
    @InvocableVariable(
        label='Maximum Rows'
        description='Maximum material error rows to summarize. Defaults to 10.'
        required=false
    )
    global Integer maxRows;
}
