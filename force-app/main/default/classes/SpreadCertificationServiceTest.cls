@IsTest
private class SpreadCertificationServiceTest {
    @IsTest
    static void certifiesPathResultsAndWritesAuditLog() {
        Spread_Pilot_Run__c run = SpreadTestDataFactory.createPilotRun();
        Spread_Document__c document = SpreadTestDataFactory.createDocument(run.Id);
        Spread_Line_Item__c cash = SpreadTestDataFactory.createLineItem(run.Id, document.Id, 'cash', true);
        Spread_Path_Result__c result = SpreadTestDataFactory.createPathResult(run.Id, document.Id, cash.Id, 'salesforce_native_staging', 500000, 500000, false, 'Uncertified');

        Test.startTest();
        SpreadCertificationService.certifyPathResults(new List<Id>{ result.Id });
        Test.stopTest();

        Spread_Path_Result__c certified = [
            SELECT Certification_Status__c, Certified_By__c, Certified_At__c
            FROM Spread_Path_Result__c
            WHERE Id = :result.Id
        ];
        System.assertEquals('Certified', certified.Certification_Status__c);
        System.assertNotEquals(null, certified.Certified_By__c);
        System.assertNotEquals(null, certified.Certified_At__c);

        System.assertEquals(1, [
            SELECT count()
            FROM Spread_Audit_Log__c
            WHERE Record_Id__c = :result.Id
            AND Event_Type__c = 'Certification'
        ]);
    }
}

