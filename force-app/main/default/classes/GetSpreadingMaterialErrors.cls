public with sharing class GetSpreadingMaterialErrors {
    @InvocableMethod(
        label='Get Spreading Material Errors'
        description='Retrieves uncaught material spread variances for advisory Agentforce review. Does not approve exceptions or update final spreads.'
        category='Commercial Lending Spreading'
    )
    public static List<SpreadingMaterialErrorsOutput> getErrors(List<SpreadingPilotContextInput> requests) {
        List<SpreadingMaterialErrorsOutput> outputs = new List<SpreadingMaterialErrorsOutput>();
        for (SpreadingPilotContextInput request : requests) {
            outputs.add(buildErrors(request));
        }
        return outputs;
    }

    private static SpreadingMaterialErrorsOutput buildErrors(SpreadingPilotContextInput request) {
        SpreadingMaterialErrorsOutput output = new SpreadingMaterialErrorsOutput();
        if (request == null || String.isBlank(request.pilotRunId)) {
            output.errorMessage = 'Pilot Run Id is required.';
            output.materialErrorCount = 0;
            return output;
        }

        Id pilotRunId = resolveRunId(request.pilotRunId);
        if (pilotRunId == null) {
            output.errorMessage = 'No pilot run found for: ' + request.pilotRunId + '. Verify the name or ID in the Spread Review workbench.';
            output.materialErrorCount = 0;
            return output;
        }

        Integer rowLimit = request.maxRows == null || request.maxRows <= 0 ? 10 : Math.min(request.maxRows, 50);
        List<String> details = new List<String>();
        Integer totalCount = 0;

        for (Spread_Path_Result__c result : [
            SELECT Path_Key__c, Manual_Value__c, Candidate_Value__c, Error_Type__c, Certification_Status__c,
                   Spread_Document__r.Name, Spread_Document__r.Borrower__r.Name,
                   Spread_Line_Item__r.Normalized_Line__c
            FROM Spread_Path_Result__c
            WHERE Pilot_Run__c = :pilotRunId
            AND Spread_Line_Item__r.Material__c = true
            AND Exception_Flag__c = false
            WITH USER_MODE
            ORDER BY Path_Key__c, Spread_Line_Item__r.Normalized_Line__c
            LIMIT 2000
        ]) {
            Decimal manualValue = valueOrZero(result.Manual_Value__c);
            Decimal candidateValue = valueOrZero(result.Candidate_Value__c);
            if (manualValue == candidateValue) {
                continue;
            }

            totalCount++;
            if (details.size() < rowLimit) {
                details.add(
                    result.Path_Key__c +
                    ' | borrower=' + safeName(result.Spread_Document__r == null || result.Spread_Document__r.Borrower__r == null ? null : result.Spread_Document__r.Borrower__r.Name) +
                    ' | document=' + safeName(result.Spread_Document__r == null ? null : result.Spread_Document__r.Name) +
                    ' | line=' + safeName(result.Spread_Line_Item__r == null ? null : result.Spread_Line_Item__r.Normalized_Line__c) +
                    ' | manual=' + String.valueOf(manualValue) +
                    ' | candidate=' + String.valueOf(candidateValue) +
                    ' | variance=' + String.valueOf(manualValue - candidateValue) +
                    ' | error_type=' + safeName(result.Error_Type__c) +
                    ' | certification=' + safeName(result.Certification_Status__c)
                );
            }
        }

        output.pilotRunId = String.valueOf(pilotRunId);
        output.materialErrorCount = totalCount;
        output.materialErrorSummary = totalCount == 0
            ? 'No uncaught material errors were found for this pilot run.'
            : String.join(details, '\n');
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

    private static Decimal valueOrZero(Decimal value) {
        return value == null ? 0 : value;
    }

    private static String safeName(String value) {
        return String.isBlank(value) ? 'Unspecified' : value;
    }
}
