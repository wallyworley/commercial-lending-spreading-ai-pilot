@IsTest
private class SpreadManualBaselineServiceTest {
    @IsTest
    static void updatesManualBaselineAndWritesAuditLog() {
        Spread_Pilot_Run__c run = SpreadTestDataFactory.createPilotRun();
        Spread_Document__c document = SpreadTestDataFactory.createDocument(run.Id);
        Spread_Line_Item__c revenue = SpreadTestDataFactory.createLineItem(run.Id, document.Id, 'revenue', true);
        Spread_Path_Result__c result = SpreadTestDataFactory.createPathResult(
            run.Id,
            document.Id,
            revenue.Id,
            'salesforce_native_staging',
            null,
            8450000,
            false,
            'Uncertified'
        );

        Test.startTest();
        SpreadManualBaselineService.setManualBaseline(result.Id, 8400000, 'Validated against analyst spread workbook.');
        Test.stopTest();

        Spread_Path_Result__c updated = [
            SELECT Manual_Value__c
            FROM Spread_Path_Result__c
            WHERE Id = :result.Id
        ];
        System.assertEquals(8400000, updated.Manual_Value__c);

        Spread_Audit_Log__c log = [
            SELECT Event_Type__c, Notes__c
            FROM Spread_Audit_Log__c
            WHERE Record_Id__c = :result.Id
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals('Manual Baseline Updated', log.Event_Type__c);
        System.assert(log.Notes__c.contains('Validated against analyst spread workbook.'));
    }

    @IsTest
    static void requiresReason() {
        Spread_Pilot_Run__c run = SpreadTestDataFactory.createPilotRun();
        Spread_Document__c document = SpreadTestDataFactory.createDocument(run.Id);
        Spread_Line_Item__c revenue = SpreadTestDataFactory.createLineItem(run.Id, document.Id, 'revenue', true);
        Spread_Path_Result__c result = SpreadTestDataFactory.createPathResult(
            run.Id,
            document.Id,
            revenue.Id,
            'salesforce_native_staging',
            null,
            8450000,
            false,
            'Uncertified'
        );

        try {
            SpreadManualBaselineService.setManualBaseline(result.Id, 8400000, ' ');
            System.assert(false, 'Expected an AuraHandledException when reason is blank.');
        } catch (AuraHandledException error) {
            System.assert(true, 'Expected path: blank reason throws.');
        }
    }
}
