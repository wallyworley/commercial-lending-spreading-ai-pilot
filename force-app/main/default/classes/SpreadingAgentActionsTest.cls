@IsTest
private class SpreadingAgentActionsTest {
    @IsTest
    static void returnsSummaryAndMaterialErrorsForAgent() {
        Spread_Pilot_Run__c run = SpreadTestDataFactory.createPilotRun();
        Spread_Document__c document = SpreadTestDataFactory.createDocument(run.Id);
        Spread_Line_Item__c revenue = SpreadTestDataFactory.createLineItem(run.Id, document.Id, 'revenue', true);
        Spread_Line_Item__c ebitda = SpreadTestDataFactory.createLineItem(run.Id, document.Id, 'ebitda', true);
        SpreadTestDataFactory.createPathResult(run.Id, document.Id, revenue.Id, 'manual_ncino_control', 1000000, 1000000, false, 'Certified');
        SpreadTestDataFactory.createPathResult(run.Id, document.Id, ebitda.Id, 'manual_ncino_control', 300000, 300000, false, 'Certified');
        SpreadTestDataFactory.createPathResult(run.Id, document.Id, revenue.Id, 'ncino_automated_spreading', 1000000, 1000000, false, 'Certified');
        SpreadTestDataFactory.createPathResult(run.Id, document.Id, ebitda.Id, 'ncino_automated_spreading', 300000, 250000, false, 'Certified');
        SpreadScorecardService.calculateForRun(run.Id);

        SpreadingPilotContextInput request = new SpreadingPilotContextInput();
        request.pilotRunId = run.Id;
        request.maxRows = 5;

        Test.startTest();
        List<SpreadingPilotRunSummaryOutput> summaries = GetSpreadingPilotRunSummary.getSummary(
            new List<SpreadingPilotContextInput>{ request }
        );
        List<SpreadingMaterialErrorsOutput> errors = GetSpreadingMaterialErrors.getErrors(
            new List<SpreadingPilotContextInput>{ request }
        );
        Test.stopTest();

        System.assertEquals(1, summaries.size());
        System.assertEquals(run.Id, summaries[0].pilotRunId);
        System.assertEquals(true, summaries[0].hasBlockingIssue);
        System.assert(summaries[0].scorecardSummary.contains('ncino_automated_spreading'), 'Expected nCino path summary.');

        System.assertEquals(1, errors.size());
        System.assertEquals(1, errors[0].materialErrorCount);
        System.assert(errors[0].materialErrorSummary.contains('ebitda'), 'Expected EBITDA material error details.');
    }

    @IsTest
    static void validatesMissingInput() {
        Test.startTest();
        List<SpreadingPilotRunSummaryOutput> summaries = GetSpreadingPilotRunSummary.getSummary(
            new List<SpreadingPilotContextInput>{ new SpreadingPilotContextInput() }
        );
        List<SpreadingMaterialErrorsOutput> errors = GetSpreadingMaterialErrors.getErrors(
            new List<SpreadingPilotContextInput>{ new SpreadingPilotContextInput() }
        );
        Test.stopTest();

        System.assertEquals('Pilot Run Id is required.', summaries[0].errorMessage);
        System.assertEquals('Pilot Run Id is required.', errors[0].errorMessage);
    }
}
