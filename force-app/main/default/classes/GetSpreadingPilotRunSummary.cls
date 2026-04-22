public with sharing class GetSpreadingPilotRunSummary {
    @InvocableMethod(
        label='Get Spreading Pilot Run Summary'
        description='Retrieves pilot run counts and current path scorecards for advisory Agentforce review. Does not certify values or write final spreads.'
        category='Commercial Lending Spreading'
    )
    public static List<SpreadingPilotRunSummaryOutput> getSummary(List<SpreadingPilotContextInput> requests) {
        List<SpreadingPilotRunSummaryOutput> outputs = new List<SpreadingPilotRunSummaryOutput>();
        for (SpreadingPilotContextInput request : requests) {
            outputs.add(buildSummary(request));
        }
        return outputs;
    }

    private static SpreadingPilotRunSummaryOutput buildSummary(SpreadingPilotContextInput request) {
        SpreadingPilotRunSummaryOutput output = new SpreadingPilotRunSummaryOutput();
        if (request == null || String.isBlank(request.pilotRunId)) {
            output.errorMessage = 'Pilot Run Id is required.';
            output.hasBlockingIssue = true;
            return output;
        }

        List<Spread_Pilot_Run__c> runs = resolveRun(request.pilotRunId);
        if (runs.isEmpty()) {
            output.errorMessage = 'No pilot run found for: ' + request.pilotRunId + '. Verify the name or ID in the Spread Review workbench.';
            output.hasBlockingIssue = true;
            return output;
        }

        Spread_Pilot_Run__c run = runs[0];
        output.pilotRunId = run.Id;
        output.pilotRunName = run.Name;
        output.status = run.Status__c;
        output.portfolio = run.Portfolio__c;
        output.documentCount = countRecords('Spread_Document__c', run.Id);
        output.lineItemCount = countRecords('Spread_Line_Item__c', run.Id);

        List<String> summaries = new List<String>();
        Boolean hasBlock = false;
        for (Pilot_Scorecard_Result__c scorecard : [
            SELECT Path_Key__c, Passed__c, Exact_Match_Rate__c, Dollar_Weighted_Accuracy__c,
                   Time_Reduction__c, Certification_Rate__c, Uncaught_Material_Errors__c,
                   Line_Item_Count__c
            FROM Pilot_Scorecard_Result__c
            WHERE Pilot_Run__c = :run.Id
            WITH USER_MODE
            ORDER BY Path_Key__c
        ]) {
            if (scorecard.Passed__c != true) {
                hasBlock = true;
            }
            summaries.add(
                scorecard.Path_Key__c +
                ': ' + (scorecard.Passed__c == true ? 'PASS' : 'BLOCK') +
                ', exact=' + formatPercent(scorecard.Exact_Match_Rate__c) +
                ', dollar_accuracy=' + formatPercent(scorecard.Dollar_Weighted_Accuracy__c) +
                ', time_reduction=' + formatPercent(scorecard.Time_Reduction__c) +
                ', certification=' + formatPercent(scorecard.Certification_Rate__c) +
                ', uncaught_material_errors=' + String.valueOf(scorecard.Uncaught_Material_Errors__c) +
                ', lines=' + String.valueOf(scorecard.Line_Item_Count__c)
            );
        }

        output.scorecardSummary = summaries.isEmpty()
            ? 'No scorecards exist yet. Ask an analyst to calculate scorecards before interpreting pilot gates.'
            : String.join(summaries, '\n');
        output.hasBlockingIssue = hasBlock || summaries.isEmpty();
        output.gateDecision = output.hasBlockingIssue
            ? 'Do not recommend production rollout from this run.'
            : 'All current path scorecards pass configured pilot gates, pending model-risk and control approvals.';

        return output;
    }

    private static List<Spread_Pilot_Run__c> resolveRun(String input) {
        try {
            Id runId = Id.valueOf(input);
            return [SELECT Id, Name, Status__c, Portfolio__c FROM Spread_Pilot_Run__c WHERE Id = :runId WITH USER_MODE LIMIT 1];
        } catch (Exception e) {
            String nameLike = '%' + input + '%';
            return [SELECT Id, Name, Status__c, Portfolio__c FROM Spread_Pilot_Run__c WHERE Name LIKE :nameLike WITH USER_MODE ORDER BY CreatedDate DESC LIMIT 1];
        }
    }

    private static Integer countRecords(String objectApiName, Id pilotRunId) {
        String query = 'SELECT COUNT(Id) total FROM ' + objectApiName + ' WHERE Pilot_Run__c = :pilotRunId';
        for (AggregateResult result : Database.query(query, AccessLevel.USER_MODE)) {
            return Integer.valueOf(String.valueOf(result.get('total')));
        }
        return 0;
    }

    private static String formatPercent(Decimal value) {
        if (value == null) {
            return '0.00%';
        }
        return String.valueOf((value * 100).setScale(2)) + '%';
    }
}
