@IsTest
private class SpreadDocumentRecordPageControllerTest {
    @IsTest
    static void returnsDocumentContextWithChildren() {
        Spread_Pilot_Run__c run = SpreadTestDataFactory.createPilotRun();
        Spread_Document__c document = SpreadTestDataFactory.createDocument(run.Id);
        SpreadEvidenceService.EvidenceImportResult evidence = SpreadEvidenceService.createTextEvidence(
            document.Id,
            'Revenue 100',
            2,
            'Docling',
            'native_pdf'
        );
        Spread_Line_Item__c lineItem = SpreadTestDataFactory.createLineItem(run.Id, document.Id, 'revenue', true);
        lineItem.Primary_Evidence__c = evidence.evidenceId;
        update lineItem;

        Spread_Path_Result__c pathResult = SpreadTestDataFactory.createPathResult(
            run.Id,
            document.Id,
            lineItem.Id,
            'salesforce_native_staging',
            1000000,
            950000,
            false,
            'Certified'
        );
        pathResult.Primary_Evidence__c = evidence.evidenceId;
        update pathResult;

        insert new Spread_Exception__c(
            Spread_Document__c = document.Id,
            Severity__c = 'Warning',
            Exception_Reason__c = 'Synthetic extraction exception'
        );

        Test.startTest();
        SpreadDocumentRecordPageController.DocumentView view = SpreadDocumentRecordPageController.getDocumentView(document.Id);
        Test.stopTest();

        System.assertEquals(document.Id, view.summary.documentId);
        System.assertEquals(document.Name, view.summary.documentName);
        System.assertEquals(run.Id, view.summary.pilotRunId);
        System.assertEquals(1, view.summary.evidenceCount);
        System.assertEquals(1, view.summary.lineItemCount);
        System.assertEquals(1, view.summary.pathResultCount);
        System.assertEquals(1, view.summary.exceptionCount);
        System.assertEquals(1, view.evidences.size());
        System.assertEquals('Docling', view.evidences[0].provider);
        System.assertEquals(1, view.lineItems.size());
        System.assertEquals(evidence.evidenceId, view.lineItems[0].primaryEvidenceId);
        System.assertEquals(1, view.pathResults.size());
        System.assertEquals('salesforce_native_staging', view.pathResults[0].pathKey);
        System.assertEquals(evidence.evidenceId, view.pathResults[0].primaryEvidenceId);
        System.assertEquals(1, view.exceptions.size());
        System.assertEquals('Warning', view.exceptions[0].severity);
    }

    @IsTest
    static void returnsEmptyCollectionsWhenDocumentHasNoChildren() {
        Spread_Pilot_Run__c run = SpreadTestDataFactory.createPilotRun();
        Spread_Document__c document = SpreadTestDataFactory.createDocument(run.Id);

        Test.startTest();
        SpreadDocumentRecordPageController.DocumentView view = SpreadDocumentRecordPageController.getDocumentView(document.Id);
        Test.stopTest();

        System.assertEquals(0, view.summary.evidenceCount);
        System.assertEquals(0, view.summary.lineItemCount);
        System.assertEquals(0, view.summary.pathResultCount);
        System.assertEquals(0, view.summary.exceptionCount);
        System.assertEquals(0, view.evidences.size());
        System.assertEquals(0, view.lineItems.size());
        System.assertEquals(0, view.pathResults.size());
        System.assertEquals(0, view.exceptions.size());
    }
}
