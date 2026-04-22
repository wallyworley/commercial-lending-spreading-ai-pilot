public with sharing class SpreadCertificationService {
    @TestVisible private static SpreadPathResultSelector pathResultSelector = new SpreadPathResultSelector();
    @AuraEnabled
    public static void certifyPathResults(List<Id> pathResultIds) {
        updateCertification(pathResultIds, 'Certified');
    }

    @AuraEnabled
    public static void rejectPathResults(List<Id> pathResultIds) {
        updateCertification(pathResultIds, 'Rejected');
    }

    private static void updateCertification(List<Id> pathResultIds, String status) {
        if (pathResultIds == null || pathResultIds.isEmpty()) {
            throw new AuraHandledException('At least one path result id is required.');
        }

        Savepoint checkpoint = Database.setSavepoint();
        try {
            List<Spread_Path_Result__c> updates = new List<Spread_Path_Result__c>();
            for (Spread_Path_Result__c result : pathResultSelector.getByIds(pathResultIds)) {
                result.Certification_Status__c = status;
                result.Certified_By__c = UserInfo.getUserId();
                result.Certified_At__c = System.now();
                updates.add(result);
            }
            update updates;

            List<Spread_Audit_Log__c> logs = new List<Spread_Audit_Log__c>();
            for (Spread_Path_Result__c result : updates) {
                logs.add(new Spread_Audit_Log__c(
                    Event_Type__c = 'Certification',
                    Record_Id__c = result.Id,
                    Object_Name__c = 'Spread_Path_Result__c',
                    Notes__c = 'Certification status set to ' + status + '.'
                ));
            }
            insert logs;
        } catch (Exception error) {
            Database.rollback(checkpoint);
            throw new AuraHandledException('Certification update failed: ' + error.getMessage());
        }
    }
}

