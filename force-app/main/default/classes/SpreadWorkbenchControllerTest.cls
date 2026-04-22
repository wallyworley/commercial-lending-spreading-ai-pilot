@IsTest
private class SpreadWorkbenchControllerTest {
    @IsTest
    static void returnsPilotRunsAndMaterialErrors() {
        Spread_Pilot_Run__c run = SpreadTestDataFactory.createPilotRun();
        Spread_Document__c document = SpreadTestDataFactory.createDocument(run.Id);
        Spread_Line_Item__c revenue = SpreadTestDataFactory.createLineItem(run.Id, document.Id, 'revenue', true);
        SpreadTestDataFactory.createPathResult(run.Id, document.Id, revenue.Id, 'salesforce_native_staging', 1000000, 900000, false, 'Certified');

        Test.startTest();
        List<SpreadWorkbenchController.PilotRunOption> runs = SpreadWorkbenchController.getPilotRuns();
        List<SpreadWorkbenchController.MaterialErrorRow> errors = SpreadWorkbenchController.getMaterialErrors(run.Id);
        Test.stopTest();

        System.assert(!runs.isEmpty(), 'Expected at least one pilot run option.');
        System.assertEquals(run.Id, runs[0].id);
        System.assertEquals(1, runs[0].documentCount);
        System.assertEquals(1, runs[0].lineItemCount);
        System.assertEquals(1, errors.size(), 'Expected one material error.');
        System.assertEquals('revenue', errors[0].normalizedLine);
        System.assertEquals(100000, errors[0].varianceAmount);
    }
}

