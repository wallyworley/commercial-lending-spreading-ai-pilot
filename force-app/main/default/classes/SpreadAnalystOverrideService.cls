public with sharing class SpreadAnalystOverrideService {
    @AuraEnabled
    public static void setReviewedValue(Id pathResultId, Decimal reviewedValue, String reason) {
        if (pathResultId == null) {
            throw new AuraHandledException('Path result ID is required.');
        }
        if (reviewedValue == null) {
            throw new AuraHandledException('Reviewed value is required.');
        }
        if (String.isBlank(reason)) {
            throw new AuraHandledException('A reason is required when setting an analyst override.');
        }

        Savepoint checkpoint = Database.setSavepoint();
        try {
            Spread_Path_Result__c result = [
                SELECT Id, Reviewed_Value__c, Reviewed_Reason__c, Reviewed_By__c, Reviewed_At__c,
                       Candidate_Value__c, Manual_Value__c, Certification_Status__c, Certified_By__c,
                       Certified_At__c, Spread_Line_Item__r.Normalized_Line__c
                FROM Spread_Path_Result__c
                WHERE Id = :pathResultId
                WITH USER_MODE
                FOR UPDATE
            ];

            Decimal previousReviewedValue = result.Reviewed_Value__c;
            String previousCertificationStatus = result.Certification_Status__c;

            result.Reviewed_Value__c = reviewedValue;
            result.Reviewed_Reason__c = reason.trim();
            result.Reviewed_By__c = UserInfo.getUserId();
            result.Reviewed_At__c = System.now();
            result.Certification_Status__c = 'Uncertified';
            result.Certified_By__c = null;
            result.Certified_At__c = null;
            update result;

            String lineName = result.Spread_Line_Item__r == null
                ? 'unknown line'
                : result.Spread_Line_Item__r.Normalized_Line__c;

            insert new Spread_Audit_Log__c(
                Event_Type__c = 'Analyst Override Updated',
                Record_Id__c = result.Id,
                Object_Name__c = 'Spread_Path_Result__c',
                Notes__c =
                    'Reviewed override updated for ' + lineName +
                    '. Previous reviewed=' + String.valueOf(previousReviewedValue) +
                    ', New reviewed=' + String.valueOf(reviewedValue) +
                    ', Candidate=' + String.valueOf(result.Candidate_Value__c) +
                    ', Manual baseline=' + String.valueOf(result.Manual_Value__c) +
                    ', Previous certification status=' + String.valueOf(previousCertificationStatus) +
                    ', Reason=' + reason.trim()
            );
        } catch (Exception error) {
            Database.rollback(checkpoint);
            throw new AuraHandledException('Analyst override update failed: ' + error.getMessage());
        }
    }
}
