@IsTest
private class SpreadScorecardServiceTest {
    @IsTest
    static void calculatesPassingManualBaseline() {
        Spread_Pilot_Run__c run = SpreadTestDataFactory.createPilotRun();
        Spread_Document__c document = SpreadTestDataFactory.createDocument(run.Id);
        Spread_Line_Item__c revenue = SpreadTestDataFactory.createLineItem(run.Id, document.Id, 'revenue', true);
        SpreadTestDataFactory.createPathResult(run.Id, document.Id, revenue.Id, 'manual_ncino_control', 1000000, 1000000, false, 'Certified');

        Test.startTest();
        List<SpreadScorecardService.ScorecardSummary> summaries = SpreadScorecardService.calculateForRun(run.Id);
        Test.stopTest();

        System.assertEquals(1, summaries.size(), 'One scorecard should be created.');
        System.assertEquals('manual_ncino_control', summaries[0].pathKey);
        System.assertEquals(true, summaries[0].passed, 'Manual baseline should pass when it matches and is certified.');
        System.assertEquals(0, summaries[0].uncaughtMaterialErrors);
    }

    @IsTest
    static void failsCandidateWithUncaughtMaterialError() {
        Spread_Pilot_Run__c run = SpreadTestDataFactory.createPilotRun();
        Spread_Document__c document = SpreadTestDataFactory.createDocument(run.Id);
        Spread_Line_Item__c debtService = SpreadTestDataFactory.createLineItem(run.Id, document.Id, 'debt_service', true);
        SpreadTestDataFactory.createPathResult(run.Id, document.Id, debtService.Id, 'ncino_automated_spreading', 1160000, 116000, false, 'Certified');

        Test.startTest();
        List<SpreadScorecardService.ScorecardSummary> summaries = SpreadScorecardService.calculateForRun(run.Id);
        Test.stopTest();

        System.assertEquals(1, summaries.size(), 'One scorecard should be created.');
        System.assertEquals(false, summaries[0].passed, 'Uncaught material error should fail the path.');
        System.assertEquals(1, summaries[0].uncaughtMaterialErrors);
    }
}

