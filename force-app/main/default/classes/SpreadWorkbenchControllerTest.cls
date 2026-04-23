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

    @IsTest
    static void filtersReviewPageToSelectedDocument() {
        Spread_Pilot_Run__c run = SpreadTestDataFactory.createPilotRun();
        Spread_Document__c firstDocument = SpreadTestDataFactory.createDocument(run.Id);
        Spread_Document__c secondDocument = SpreadTestDataFactory.createDocument(run.Id);
        secondDocument.Name = 'Second Synthetic Statement';
        update secondDocument;

        Spread_Line_Item__c firstLine = SpreadTestDataFactory.createLineItem(run.Id, firstDocument.Id, 'revenue', true);
        Spread_Line_Item__c secondLine = SpreadTestDataFactory.createLineItem(run.Id, secondDocument.Id, 'ebitda', true);
        SpreadTestDataFactory.createPathResult(run.Id, firstDocument.Id, firstLine.Id, 'salesforce_native_staging', 1000000, 900000, false, 'Certified');
        SpreadTestDataFactory.createPathResult(run.Id, secondDocument.Id, secondLine.Id, 'salesforce_native_staging', 500000, 450000, false, 'Certified');

        Test.startTest();
        SpreadWorkbenchController.SpreadReviewPage page = SpreadWorkbenchController.getSpreadReviewPage(
            run.Id,
            25,
            0,
            false,
            secondDocument.Id
        );
        Test.stopTest();

        System.assertEquals(1, page.lines.size(), 'Expected only rows for the selected document.');
        System.assertEquals(secondDocument.Id, page.lines[0].spreadDocumentId);
        System.assertEquals('Second Synthetic Statement', page.lines[0].documentName);
        System.assertEquals('ebitda', page.lines[0].normalizedLine);
    }
}
