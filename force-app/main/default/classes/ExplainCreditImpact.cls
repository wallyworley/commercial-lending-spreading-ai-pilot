public with sharing class ExplainCreditImpact {
    private static final Integer MAX_RESULTS = 20;

    @InvocableMethod(
        label='Explain Credit Impact'
        description='Returns Apex-sourced spread facts for up to 20 certified path results. Use these facts to explain how specific spread variances affect repayment capacity, leverage, or liquidity. Explain only using the facts returned — do not introduce financial context from outside this response.'
        category='Commercial Lending Spreading'
    )
    public static List<SpreadingCreditImpactOutput> explain(List<SpreadingCreditImpactInput> requests) {
        List<SpreadingCreditImpactOutput> outputs = new List<SpreadingCreditImpactOutput>();
        for (SpreadingCreditImpactInput request : requests) {
            outputs.add(buildOutput(request));
        }
        return outputs;
    }

    private static SpreadingCreditImpactOutput buildOutput(SpreadingCreditImpactInput request) {
        SpreadingCreditImpactOutput output = new SpreadingCreditImpactOutput();
        if (request == null || request.pathResultIds == null || request.pathResultIds.isEmpty()) {
            output.errorMessage = 'At least one path result Id is required.';
            output.factCount = 0;
            return output;
        }

        List<Id> resolvedIds = new List<Id>();
        for (String rawId : request.pathResultIds) {
            try {
                resolvedIds.add(Id.valueOf(rawId));
            } catch (Exception error) {
                // skip invalid IDs — don't fail the whole batch
            }
        }

        if (resolvedIds.isEmpty()) {
            output.errorMessage = 'No valid Salesforce Ids were provided.';
            output.factCount = 0;
            return output;
        }

        Integer rowLimit = Math.min(resolvedIds.size(), MAX_RESULTS);
        List<String> facts = new List<String>();

        for (Spread_Path_Result__c result : [
            SELECT Id, Path_Key__c, Manual_Value__c, Candidate_Value__c, Variance_Amount__c,
                   Variance_Pct__c, Certification_Status__c, Exception_Flag__c, Error_Type__c,
                   Spread_Line_Item__r.Normalized_Line__c, Spread_Line_Item__r.Material__c,
                   Spread_Line_Item__r.Statement_Type__c, Spread_Line_Item__r.Fiscal_Period__c,
                   Spread_Document__r.Borrower__r.Name
            FROM Spread_Path_Result__c
            WHERE Id IN :resolvedIds
            AND Certification_Status__c IN ('Certified', 'Exception Approved')
            WITH USER_MODE
            ORDER BY Spread_Line_Item__r.Normalized_Line__c, Path_Key__c
            LIMIT :rowLimit
        ]) {
            facts.add(
                '[source:apex]'
                + ' id=' + result.Id
                + ' | borrower=' + safeName(result.Spread_Document__r == null || result.Spread_Document__r.Borrower__r == null
                    ? null : result.Spread_Document__r.Borrower__r.Name)
                + ' | line=' + safeName(result.Spread_Line_Item__r == null ? null : result.Spread_Line_Item__r.Normalized_Line__c)
                + ' | period=' + safeName(result.Spread_Line_Item__r == null ? null : result.Spread_Line_Item__r.Fiscal_Period__c)
                + ' | statement=' + safeName(result.Spread_Line_Item__r == null ? null : result.Spread_Line_Item__r.Statement_Type__c)
                + ' | material=' + String.valueOf(result.Spread_Line_Item__r != null && result.Spread_Line_Item__r.Material__c)
                + ' | path=' + safeName(result.Path_Key__c)
                + ' | manual=' + String.valueOf(result.Manual_Value__c)
                + ' | candidate=' + String.valueOf(result.Candidate_Value__c)
                + ' | variance=' + String.valueOf(result.Variance_Amount__c)
                + ' | variance_pct=' + String.valueOf(result.Variance_Pct__c)
                + ' | status=' + safeName(result.Certification_Status__c)
                + ' | error_type=' + safeName(result.Error_Type__c)
            );
        }

        output.factCount = facts.size();
        output.facts = facts.isEmpty()
            ? 'No certified path results were found for the provided Ids.'
            : String.join(facts, '\n');
        output.narrativePrompt = facts.isEmpty()
            ? 'No facts are available. Do not generate a credit impact explanation.'
            : 'Explain the credit impact of the spread variances above using only the facts marked [source:apex]. '
                + 'Do not introduce financial ratios, sector benchmarks, or credit conclusions from outside these facts. '
                + 'Do not certify, approve, or make a credit decision.';
        return output;
    }

    private static String safeName(String value) {
        return String.isBlank(value) ? 'Unspecified' : value;
    }
}
