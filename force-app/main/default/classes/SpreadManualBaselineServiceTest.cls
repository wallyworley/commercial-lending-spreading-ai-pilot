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
        Assert.areEqual(8400000, updated.Manual_Value__c, 'Manual baseline should be stored on the path result.');

        Spread_Audit_Log__c log = [
            SELECT Event_Type__c, Notes__c
            FROM Spread_Audit_Log__c
            WHERE Record_Id__c = :result.Id
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        Assert.areEqual('Manual Baseline Updated', log.Event_Type__c, 'Audit log should record the baseline update event.');
        Assert.isTrue(
            log.Notes__c.contains('Validated against analyst spread workbook.'),
            'Audit log should preserve the analyst reason.'
        );
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

        Boolean threwException = false;

        try {
            SpreadManualBaselineService.setManualBaseline(result.Id, 8400000, ' ');
            Assert.fail('Expected an AuraHandledException when reason is blank.');
        } catch (AuraHandledException error) {
            threwException = true;
        }

        Assert.areEqual(true, threwException, 'Blank reason should be rejected.');

        Spread_Path_Result__c unchanged = [
            SELECT Manual_Value__c
            FROM Spread_Path_Result__c
            WHERE Id = :result.Id
        ];
        Assert.areEqual(null, unchanged.Manual_Value__c, 'Manual baseline should remain unset after validation failure.');

        Integer auditCount = [
            SELECT COUNT()
            FROM Spread_Audit_Log__c
            WHERE Record_Id__c = :result.Id
        ];
        Assert.areEqual(0, auditCount, 'Validation failures should not create audit log entries.');
    }
}
