public with sharing class GetSelectedReportFacts {
    @InvocableMethod(
        label='Get Selected Report Facts'
        description='Retrieves certified spread line items explicitly selected for report inclusion. Only returns facts marked Include_In_Report__c = true. Use this to ground a credit memo narrative — do not generate narrative content from outside these facts.'
        category='Commercial Lending Spreading'
    )
    public static List<SpreadingReportFactsOutput> getFacts(List<SpreadingPilotContextInput> requests) {
        List<SpreadingReportFactsOutput> outputs = new List<SpreadingReportFactsOutput>();
        for (SpreadingPilotContextInput request : requests) {
            outputs.add(buildFacts(request));
        }
        return outputs;
    }

    private static SpreadingReportFactsOutput buildFacts(SpreadingPilotContextInput request) {
        SpreadingReportFactsOutput output = new SpreadingReportFactsOutput();
        if (request == null || String.isBlank(request.pilotRunId)) {
            output.errorMessage = 'Pilot Run Id is required.';
            output.factCount = 0;
            return output;
        }

        Id pilotRunId = resolveRunId(request.pilotRunId);
        if (pilotRunId == null) {
            output.errorMessage = 'No pilot run found for: ' + request.pilotRunId + '. Verify the name or ID in the Spread Review workbench.';
            output.factCount = 0;
            return output;
        }

        List<String> facts = new List<String>();
        Set<Id> lineItemIds = new Set<Id>();

        for (Spread_Line_Item__c line : [
            SELECT Id, Normalized_Line__c, Statement_Type__c, Fiscal_Period__c, Material__c, Review_Note__c
            FROM Spread_Line_Item__c
            WHERE Pilot_Run__c = :pilotRunId
            AND Include_In_Report__c = true
            WITH USER_MODE
            ORDER BY Normalized_Line__c
            LIMIT 200
        ]) {
            lineItemIds.add(line.Id);
        }

        if (lineItemIds.isEmpty()) {
            output.pilotRunId = String.valueOf(pilotRunId);
            output.factCount = 0;
            output.selectedFactsSummary = 'No line items have been selected for report inclusion. Ask an analyst to mark Include_In_Report__c on the relevant certified lines before generating a narrative.';
            output.narrativePrompt = 'No facts are available. Do not generate a credit narrative.';
            return output;
        }

        Map<Id, List<Spread_Path_Result__c>> resultsByLine = new Map<Id, List<Spread_Path_Result__c>>();
        for (Spread_Path_Result__c result : [
            SELECT Id, Path_Key__c, Manual_Value__c, Candidate_Value__c, Variance_Amount__c,
                   Certification_Status__c, Error_Type__c, Spread_Line_Item__c,
                   Spread_Line_Item__r.Normalized_Line__c, Spread_Line_Item__r.Statement_Type__c,
                   Spread_Line_Item__r.Fiscal_Period__c, Spread_Line_Item__r.Material__c
            FROM Spread_Path_Result__c
            WHERE Spread_Line_Item__c IN :lineItemIds
            AND Certification_Status__c IN ('Certified', 'Exception Approved')
            WITH USER_MODE
            ORDER BY Spread_Line_Item__r.Normalized_Line__c, Path_Key__c
        ]) {
            if (!resultsByLine.containsKey(result.Spread_Line_Item__c)) {
                resultsByLine.put(result.Spread_Line_Item__c, new List<Spread_Path_Result__c>());
            }
            resultsByLine.get(result.Spread_Line_Item__c).add(result);
        }

        for (Id lineId : lineItemIds) {
            List<Spread_Path_Result__c> results = resultsByLine.get(lineId);
            if (results == null || results.isEmpty()) {
                continue;
            }
            Spread_Path_Result__c first = results[0];
            String lineFact = '[source:apex]'
                + ' line=' + safeName(first.Spread_Line_Item__r.Normalized_Line__c)
                + ' | period=' + safeName(first.Spread_Line_Item__r.Fiscal_Period__c)
                + ' | statement=' + safeName(first.Spread_Line_Item__r.Statement_Type__c)
                + ' | material=' + String.valueOf(first.Spread_Line_Item__r.Material__c);
            for (Spread_Path_Result__c result : results) {
                lineFact += ' | path=' + safeName(result.Path_Key__c)
                    + ' manual=' + String.valueOf(result.Manual_Value__c)
                    + ' candidate=' + String.valueOf(result.Candidate_Value__c)
                    + ' variance=' + String.valueOf(result.Variance_Amount__c)
                    + ' status=' + safeName(result.Certification_Status__c);
            }
            facts.add(lineFact);
        }

        output.pilotRunId = String.valueOf(pilotRunId);
        output.factCount = facts.size();
        output.selectedFactsSummary = facts.isEmpty()
            ? 'Selected line items have no certified path results. Ensure path results are certified before generating a narrative.'
            : String.join(facts, '\n');
        output.narrativePrompt = 'Generate a credit memo narrative using only the facts marked [source:apex] above. '
            + 'Do not introduce financial context, ratios, or conclusions from outside these facts. '
            + 'Do not certify, approve, or recommend credit decisions.';
        return output;
    }

    private static Id resolveRunId(String input) {
        try {
            Id runId = Id.valueOf(input);
            List<Spread_Pilot_Run__c> rows = [SELECT Id FROM Spread_Pilot_Run__c WHERE Id = :runId WITH USER_MODE LIMIT 1];
            return rows.isEmpty() ? null : rows[0].Id;
        } catch (Exception e) {
            String nameLike = '%' + input + '%';
            List<Spread_Pilot_Run__c> rows = [SELECT Id FROM Spread_Pilot_Run__c WHERE Name LIKE :nameLike WITH USER_MODE ORDER BY CreatedDate DESC LIMIT 1];
            return rows.isEmpty() ? null : rows[0].Id;
        }
    }

    private static String safeName(String value) {
        return String.isBlank(value) ? 'Unspecified' : value;
    }
}
