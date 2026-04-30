@IsTest
private class SpreadAnalystOverrideServiceTest {
    @IsTest
    static void updatesReviewedValueResetsCertificationAndWritesAuditLog() {
        Spread_Pilot_Run__c run = SpreadTestDataFactory.createPilotRun();
        Spread_Document__c document = SpreadTestDataFactory.createDocument(run.Id);
        Spread_Line_Item__c revenue = SpreadTestDataFactory.createLineItem(run.Id, document.Id, 'revenue', true);
        Spread_Path_Result__c result = SpreadTestDataFactory.createPathResult(
            run.Id,
            document.Id,
            revenue.Id,
            'salesforce_native_staging',
            8400000,
            8450000,
            false,
            'Certified'
        );
        result.Certified_By__c = UserInfo.getUserId();
        result.Certified_At__c = System.now();
        update result;

        Test.startTest();
        SpreadAnalystOverrideService.setReviewedValue(result.Id, 8425000, 'Tax footnote support confirms one-time normalization.');
        Test.stopTest();

        Spread_Path_Result__c updated = [
            SELECT Reviewed_Value__c, Reviewed_Reason__c, Reviewed_By__c, Reviewed_At__c,
                   Certification_Status__c, Certified_By__c, Certified_At__c
            FROM Spread_Path_Result__c
            WHERE Id = :result.Id
        ];
        Assert.areEqual(8425000, updated.Reviewed_Value__c, 'Reviewed override should be stored on the path result.');
        Assert.areEqual('Tax footnote support confirms one-time normalization.', updated.Reviewed_Reason__c, 'Reviewed reason should be stored.');
        Assert.areEqual(UserInfo.getUserId(), updated.Reviewed_By__c, 'Reviewed by should capture the acting analyst.');
        Assert.isNotNull(updated.Reviewed_At__c, 'Reviewed at should be stamped.');
        Assert.areEqual('Uncertified', updated.Certification_Status__c, 'Any override change should require recertification.');
        Assert.areEqual(null, updated.Certified_By__c, 'Certified by should clear when override changes.');
        Assert.areEqual(null, updated.Certified_At__c, 'Certified at should clear when override changes.');

        Spread_Audit_Log__c log = [
            SELECT Event_Type__c, Notes__c
            FROM Spread_Audit_Log__c
            WHERE Record_Id__c = :result.Id
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        Assert.areEqual('Analyst Override Updated', log.Event_Type__c, 'Audit log should record the override event.');
        Assert.isTrue(
            log.Notes__c.contains('Tax footnote support confirms one-time normalization.'),
            'Audit log should preserve the analyst override reason.'
        );
    }

    @IsTest
    static void requiresReasonAndLeavesRecordUntouched() {
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
            SpreadAnalystOverrideService.setReviewedValue(result.Id, 8425000, ' ');
            Assert.fail('Expected an AuraHandledException when reason is blank.');
        } catch (AuraHandledException error) {
            threwException = true;
        }

        Assert.areEqual(true, threwException, 'Blank reason should be rejected.');

        Spread_Path_Result__c unchanged = [
            SELECT Reviewed_Value__c, Reviewed_Reason__c, Reviewed_By__c, Reviewed_At__c, Certification_Status__c
            FROM Spread_Path_Result__c
            WHERE Id = :result.Id
        ];
        Assert.areEqual(null, unchanged.Reviewed_Value__c, 'Reviewed value should remain unset after validation failure.');
        Assert.areEqual(null, unchanged.Reviewed_Reason__c, 'Reviewed reason should remain unset after validation failure.');
        Assert.areEqual(null, unchanged.Reviewed_By__c, 'Reviewed by should remain unset after validation failure.');
        Assert.areEqual(null, unchanged.Reviewed_At__c, 'Reviewed at should remain unset after validation failure.');
        Assert.areEqual('Uncertified', unchanged.Certification_Status__c, 'Certification status should remain unchanged after validation failure.');

        Integer auditCount = [
            SELECT COUNT()
            FROM Spread_Audit_Log__c
            WHERE Record_Id__c = :result.Id
        ];
        Assert.areEqual(0, auditCount, 'Validation failures should not create audit log entries.');
    }
}
