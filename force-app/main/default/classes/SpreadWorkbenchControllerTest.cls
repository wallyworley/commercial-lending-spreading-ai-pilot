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
    static void createsAndReusesLoanScopedPilotRun() {
        Commercial_Loan__c loan = SpreadTestDataFactory.createCommercialLoan();

        Test.startTest();
        SpreadWorkbenchController.PilotRunOption first =
            SpreadWorkbenchController.getOrCreatePilotRunForLoan(loan.Id);
        SpreadWorkbenchController.PilotRunOption second =
            SpreadWorkbenchController.getOrCreatePilotRunForLoan(loan.Id);
        Test.stopTest();

        System.assertEquals(first.id, second.id, 'The loan cockpit should reuse its existing pilot run.');
        System.assertEquals(loan.Id, first.commercialLoanId);
        System.assertEquals('C&I', first.portfolio);

        Commercial_Loan__c updatedLoan = [
            SELECT Stage__c
            FROM Commercial_Loan__c
            WHERE Id = :loan.Id
        ];
        System.assertEquals('Spreading', updatedLoan.Stage__c, 'Opening the cockpit should move Intake loans to Spreading.');
    }

    @IsTest
    static void rejectsMissingLoanIdForLoanScopedPilotRun() {
        Test.startTest();
        try {
            SpreadWorkbenchController.getOrCreatePilotRunForLoan(null);
            System.assert(false, 'Expected a handled exception when no commercial loan is provided.');
        } catch (AuraHandledException expected) {
            System.assertNotEquals(null, expected.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void filtersReviewPageToSelectedDocument() {
        Spread_Pilot_Run__c run = SpreadTestDataFactory.createPilotRun();
        Spread_Document__c firstDocument = SpreadTestDataFactory.createDocument(run.Id);
        Spread_Document__c secondDocument = SpreadTestDataFactory.createDocument(run.Id);
        secondDocument.Name = 'Second Synthetic Statement';
        update secondDocument;
        SpreadEvidenceService.EvidenceImportResult evidence = SpreadEvidenceService.createTextEvidence(
            secondDocument.Id,
            'Revenue 100',
            1,
            'Docling',
            'native_pdf'
        );

        Spread_Line_Item__c firstLine = SpreadTestDataFactory.createLineItem(run.Id, firstDocument.Id, 'revenue', true);
        Spread_Line_Item__c secondLine = SpreadTestDataFactory.createLineItem(run.Id, secondDocument.Id, 'ebitda', true);
        SpreadTestDataFactory.createPathResult(run.Id, firstDocument.Id, firstLine.Id, 'salesforce_native_staging', 1000000, 900000, false, 'Certified');
        Spread_Path_Result__c secondResult = SpreadTestDataFactory.createPathResult(
            run.Id,
            secondDocument.Id,
            secondLine.Id,
            'salesforce_native_staging',
            500000,
            450000,
            false,
            'Certified'
        );
        secondResult.Primary_Evidence__c = evidence.evidenceId;
        update secondResult;

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
        System.assertEquals(1, page.lines[0].pathResults.size(), 'Expected one path result for the filtered line.');
        System.assertNotEquals(null, page.lines[0].pathResults[0].primaryEvidenceId, 'Expected evidence link to be exposed to the workbench.');
    }

    @IsTest
    static void reviewPageHandlesEmptyAndMaterialFilters() {
        Spread_Pilot_Run__c run = SpreadTestDataFactory.createPilotRun();
        Spread_Document__c document = SpreadTestDataFactory.createDocument(run.Id);
        Spread_Line_Item__c materialLine = SpreadTestDataFactory.createLineItem(run.Id, document.Id, 'cash', true);
        Spread_Line_Item__c immaterialLine = SpreadTestDataFactory.createLineItem(run.Id, document.Id, 'office_supplies', false);
        SpreadTestDataFactory.createPathResult(run.Id, document.Id, materialLine.Id, 'docling_extraction', 250000, 250000, false, 'Certified');
        SpreadTestDataFactory.createPathResult(run.Id, document.Id, immaterialLine.Id, 'manual_ncino_control', 5000, 4500, false, 'Uncertified');

        Test.startTest();
        SpreadWorkbenchController.SpreadReviewPage emptyPage = SpreadWorkbenchController.getSpreadReviewPage(
            null,
            25,
            0,
            false,
            null
        );
        SpreadWorkbenchController.SpreadReviewPage materialDocumentPage = SpreadWorkbenchController.getSpreadReviewPage(
            run.Id,
            10,
            0,
            true,
            document.Id
        );
        SpreadWorkbenchController.SpreadReviewPage materialPage = SpreadWorkbenchController.getSpreadReviewPage(
            run.Id,
            10,
            0,
            true,
            null
        );
        SpreadWorkbenchController.SpreadReviewPage allPage = SpreadWorkbenchController.getSpreadReviewPage(
            run.Id,
            -1,
            -1,
            false,
            null
        );
        Test.stopTest();

        System.assertEquals(0, emptyPage.totalCount, 'Null pilot run requests should return an empty page.');
        System.assertEquals(1, materialDocumentPage.totalCount, 'Material document filter should return only material rows for the document.');
        System.assertEquals(1, materialDocumentPage.lines.size());
        System.assertEquals('cash', materialDocumentPage.lines[0].normalizedLine);
        System.assertEquals(1, materialPage.totalCount, 'Material-only filter should return only material rows.');
        System.assertEquals(2, allPage.totalCount, 'Unfiltered review page should include all spread lines.');
        System.assertEquals(2, allPage.pathKeys.size(), 'Unfiltered page should expose all extraction paths present on the page.');
    }

    @IsTest
    static void omitsMaterialErrorsWithoutManualBaseline() {
        Spread_Pilot_Run__c run = SpreadTestDataFactory.createPilotRun();
        Spread_Document__c document = SpreadTestDataFactory.createDocument(run.Id);
        Spread_Line_Item__c revenue = SpreadTestDataFactory.createLineItem(run.Id, document.Id, 'revenue', true);

        insert new Spread_Path_Result__c(
            Pilot_Run__c = run.Id,
            Spread_Document__c = document.Id,
            Spread_Line_Item__c = revenue.Id,
            Path_Key__c = 'salesforce_native_staging',
            Candidate_Value__c = 8450000,
            Certification_Status__c = 'Uncertified'
        );

        Test.startTest();
        List<SpreadWorkbenchController.MaterialErrorRow> errors = SpreadWorkbenchController.getMaterialErrors(run.Id);
        Test.stopTest();

        System.assertEquals(0, errors.size(), 'Rows without manual baselines should not show as material errors.');
    }

    @IsTest
    static void omitsMaterialErrorsWhenCandidateMatchesManual() {
        Spread_Pilot_Run__c run = SpreadTestDataFactory.createPilotRun();
        Spread_Document__c document = SpreadTestDataFactory.createDocument(run.Id);
        Spread_Line_Item__c revenue = SpreadTestDataFactory.createLineItem(run.Id, document.Id, 'revenue', true);
        SpreadTestDataFactory.createPathResult(run.Id, document.Id, revenue.Id, 'salesforce_native_staging', 8450000, 8450000, false, 'Certified');

        Test.startTest();
        List<SpreadWorkbenchController.MaterialErrorRow> nullErrors = SpreadWorkbenchController.getMaterialErrors(null);
        List<SpreadWorkbenchController.MaterialErrorRow> matchedErrors = SpreadWorkbenchController.getMaterialErrors(run.Id);
        Test.stopTest();

        System.assertEquals(0, nullErrors.size(), 'Null pilot run requests should not return material errors.');
        System.assertEquals(0, matchedErrors.size(), 'Matching manual and candidate values should not be flagged.');
    }

    @IsTest
    static void returnsActivePolicyThresholdsForPortfolio() {
        Test.startTest();
        SpreadWorkbenchController.PolicyThresholdResult noPolicy =
            SpreadWorkbenchController.getActivePolicyThresholds('C&I');
        Test.stopTest();

        System.assertEquals(0, noPolicy.thresholds.size(), 'Portfolios without an active policy should return no thresholds.');
    }

    @IsTest
    static void mapsActivePolicyThresholdsForPortfolio() {
        Spreading_Policy__c policy = new Spreading_Policy__c(
            Name = 'C&I Active Credit Policy',
            Status__c = 'Active',
            Portfolio__c = 'C&I',
            Version__c = '2026.1',
            Effective_Start_Date__c = Date.today().addDays(-10),
            Effective_End_Date__c = Date.today().addDays(10),
            Approved_By__c = UserInfo.getUserId(),
            Approved_At__c = Datetime.now(),
            Secondary_Approved_By__c = UserInfo.getUserId(),
            Secondary_Approved_At__c = Datetime.now()
        );
        insert policy;

        insert new List<Spreading_Threshold__c>{
            new Spreading_Threshold__c(
                Name = 'DSCR Minimum',
                Spreading_Policy__c = policy.Id,
                Metric__c = 'DSCR',
                Operator__c = '>=',
                Minimum_Value__c = 1.25,
                Severity_When_Failed__c = 'Policy Exception',
                Applies_To_Material_Line__c = true,
                Requires_Exception_Approval__c = true,
                Narrative_Guidance__c = 'Explain recurring repayment capacity.'
            ),
            new Spreading_Threshold__c(
                Name = 'AR Days Maximum',
                Spreading_Policy__c = policy.Id,
                Metric__c = 'AR Days',
                Operator__c = '<=',
                Maximum_Value__c = 60,
                Severity_When_Failed__c = 'Warning'
            ),
            new Spreading_Threshold__c(
                Name = 'Current Ratio Band',
                Spreading_Policy__c = policy.Id,
                Metric__c = 'Current Ratio',
                Operator__c = 'Between',
                Minimum_Value__c = 1.0,
                Maximum_Value__c = 3.0,
                Severity_When_Failed__c = 'Warning'
            )
        };

        Test.startTest();
        SpreadWorkbenchController.PolicyThresholdResult result =
            SpreadWorkbenchController.getActivePolicyThresholds('C&I');
        Test.stopTest();

        System.assertEquals(policy.Id, (Id) result.policyId);
        System.assertEquals('2026.1', result.policyVersion);
        System.assertEquals(true, result.dualApproved);
        System.assertEquals(3, result.thresholds.size(), 'Expected all active policy thresholds to be returned.');

        Map<String, SpreadWorkbenchController.ThresholdRow> rowsByMetric =
            new Map<String, SpreadWorkbenchController.ThresholdRow>();
        for (SpreadWorkbenchController.ThresholdRow row : result.thresholds) {
            rowsByMetric.put(row.metric, row);
        }

        System.assertEquals('>= 1.25', rowsByMetric.get('DSCR').displayRange);
        System.assertEquals('<= 60', rowsByMetric.get('AR Days').displayRange);
        System.assert(rowsByMetric.get('Current Ratio').displayRange.startsWith('1'), 'Expected lower bound in display range.');
        System.assert(rowsByMetric.get('Current Ratio').displayRange.endsWith('3'), 'Expected upper bound in display range.');
    }
}
