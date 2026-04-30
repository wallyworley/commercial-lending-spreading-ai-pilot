public with sharing class SpreadManualBaselineService {
    @AuraEnabled
    public static void setManualBaseline(Id pathResultId, Decimal manualValue, String reason) {
        if (pathResultId == null) {
            throw new AuraHandledException('Path result ID is required.');
        }
        if (manualValue == null) {
            throw new AuraHandledException('Manual baseline value is required.');
        }
        if (String.isBlank(reason)) {
            throw new AuraHandledException('A reason is required when setting a manual baseline.');
        }

        Savepoint checkpoint = Database.setSavepoint();
        try {
            Spread_Path_Result__c result = [
                SELECT Id, Manual_Value__c, Candidate_Value__c, Spread_Line_Item__r.Normalized_Line__c
                FROM Spread_Path_Result__c
                WHERE Id = :pathResultId
                WITH USER_MODE
                FOR UPDATE
            ];

            Decimal previousValue = result.Manual_Value__c;
            result.Manual_Value__c = manualValue;
            update result;

            String lineName = result.Spread_Line_Item__r == null
                ? 'unknown line'
                : result.Spread_Line_Item__r.Normalized_Line__c;

            insert new Spread_Audit_Log__c(
                Event_Type__c = 'Manual Baseline Updated',
                Record_Id__c = result.Id,
                Object_Name__c = 'Spread_Path_Result__c',
                Notes__c =
                    'Manual baseline updated for ' + lineName +
                    '. Previous=' + String.valueOf(previousValue) +
                    ', New=' + String.valueOf(manualValue) +
                    ', Candidate=' + String.valueOf(result.Candidate_Value__c) +
                    ', Reason=' + reason.trim()
            );
        } catch (Exception error) {
            Database.rollback(checkpoint);
            throw new AuraHandledException('Manual baseline update failed: ' + error.getMessage());
        }
    }
}
