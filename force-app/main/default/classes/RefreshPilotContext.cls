public with sharing class RefreshPilotContext {
    @InvocableMethod(
        label='Refresh Pilot Context'
        description='Re-queries live pilot run summary, scorecard results, and counts. Call this before answering any state-dependent question such as how many items remain uncertified, current scorecard pass/fail, or latest exception status. Agentforce does not automatically refresh context between turns.'
        category='Commercial Lending Spreading'
    )
    public static List<SpreadingPilotRunSummaryOutput> refresh(List<SpreadingPilotContextInput> requests) {
        return GetSpreadingPilotRunSummary.getSummary(requests);
    }
}
