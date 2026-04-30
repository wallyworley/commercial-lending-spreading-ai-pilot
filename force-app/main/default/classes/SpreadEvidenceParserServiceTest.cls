@IsTest
private class SpreadEvidenceParserServiceTest {
    @IsTest
    static void marksReviewerRequiredMappingsAsNeedsReview() {
        Spread_Pilot_Run__c run = SpreadTestDataFactory.createPilotRun();
        Spread_Document__c document = SpreadTestDataFactory.createDocument(run.Id);
        document.Statement_Type__c = 'income_statement';
        update document;

        SpreadEvidenceService.createTextEvidence(
            document.Id,
            'Adjusted EBITDA: $1,540,000',
            1,
            'Docling',
            'native_pdf'
        );

        Test.startTest();
        SpreadingParseOutput output = SpreadEvidenceParserService.parseDocument(document.Id, null);
        Test.stopTest();

        Assert.areEqual('Needs Review', output.parsingStatus, 'Reviewer-required mappings should block clean completion.');
        Assert.areEqual(1, output.lineItemCount, 'Expected one draft line.');

        Spread_Path_Result__c result = [
            SELECT Certification_Status__c, Exception_Flag__c, Exception_Reason__c
            FROM Spread_Path_Result__c
            WHERE Spread_Document__c = :document.Id
            LIMIT 1
        ];
        Assert.areEqual('Exception Pending', result.Certification_Status__c);
        Assert.areEqual(true, result.Exception_Flag__c);
        Assert.isTrue(result.Exception_Reason__c.contains('Reviewer validation required'));
    }

    @IsTest
    static void blocksSecondParseForSamePath() {
        Spread_Pilot_Run__c run = SpreadTestDataFactory.createPilotRun();
        Spread_Document__c document = SpreadTestDataFactory.createDocument(run.Id);
        SpreadEvidenceService.createTextEvidence(
            document.Id,
            'Revenue: $8,450,000',
            1,
            'Docling',
            'native_pdf'
        );

        Test.startTest();
        SpreadingParseOutput first = SpreadEvidenceParserService.parseDocument(document.Id, 'salesforce_native_staging');
        SpreadingParseOutput second = SpreadEvidenceParserService.parseDocument(document.Id, 'salesforce_native_staging');
        Test.stopTest();

        Assert.areEqual('Complete', first.parsingStatus);
        Assert.isTrue(second.errorMessage.contains('already exist'), 'Second parse should be blocked for the same path.');
    }

    @IsTest
    static void parsesBlankStatementTypeWithKnownExtractedLabelVariants() {
        Spread_Pilot_Run__c run = SpreadTestDataFactory.createPilotRun();
        Spread_Document__c document = SpreadTestDataFactory.createDocument(run.Id);
        document.Statement_Type__c = null;
        update document;

        SpreadEvidenceService.createTextEvidence(
            document.Id,
            'Quarter Revenue: $6,400,000\n'
                + 'Cash and Cash Equivalents: $1,120,000\n'
                + 'Current Assets: $5,900,000\n'
                + 'Stockholders Equity: $6,770,000',
            1,
            'Docling',
            'native_pdf'
        );

        Test.startTest();
        SpreadingParseOutput output = SpreadEvidenceParserService.parseDocument(document.Id, null);
        Test.stopTest();

        Assert.areEqual('Complete', output.parsingStatus);
        Assert.areEqual(4, output.lineItemCount);

        Map<String, Spread_Path_Result__c> resultsByLine = new Map<String, Spread_Path_Result__c>();
        for (Spread_Path_Result__c result : [
            SELECT Spread_Line_Item__r.Normalized_Line__c, Candidate_Value__c, Raw_Label__c
            FROM Spread_Path_Result__c
            WHERE Spread_Document__c = :document.Id
        ]) {
            resultsByLine.put(result.Spread_Line_Item__r.Normalized_Line__c, result);
        }

        Assert.areEqual(4, resultsByLine.size());
        Assert.areEqual(6400000, resultsByLine.get('revenue').Candidate_Value__c);
        Assert.areEqual(1120000, resultsByLine.get('cash').Candidate_Value__c);
        Assert.areEqual(5900000, resultsByLine.get('current_assets').Candidate_Value__c);
        Assert.areEqual(6770000, resultsByLine.get('net_worth_equity').Candidate_Value__c);
    }

    @IsTest
    static void parsesCurrentPeriodFromMultiYearBalanceSheetRows() {
        Spread_Pilot_Run__c run = SpreadTestDataFactory.createPilotRun();
        Spread_Document__c document = SpreadTestDataFactory.createDocument(run.Id);
        document.Statement_Type__c = 'balance_sheet';
        document.Fiscal_Period__c = null;
        update document;

        SpreadEvidenceService.createTextEvidence(
            document.Id,
            'ASSETS December 31, 2025 December 31, 2024\n'
                + 'Cash and cash equivalents $414,000 $372,600\n'
                + 'Total current assets $1,646,000 $1,481,400\n'
                + 'Total current liabilities $473,000 $440,700',
            1,
            'Docling',
            'native_pdf'
        );

        Test.startTest();
        SpreadingParseOutput output = SpreadEvidenceParserService.parseDocument(document.Id, null);
        Test.stopTest();

        Assert.areEqual('Complete', output.parsingStatus);
        Assert.areEqual(6, output.lineItemCount);

        Map<String, Spread_Path_Result__c> resultsByLine = new Map<String, Spread_Path_Result__c>();
        for (Spread_Path_Result__c result : [
            SELECT Spread_Line_Item__r.Normalized_Line__c, Spread_Line_Item__r.Fiscal_Period__c,
                   Spread_Line_Item__r.Statement_Type__c, Candidate_Value__c, Raw_Label__c, Raw_Value__c
            FROM Spread_Path_Result__c
            WHERE Spread_Document__c = :document.Id
        ]) {
            resultsByLine.put(
                result.Spread_Line_Item__r.Normalized_Line__c + '|'
                    + result.Spread_Line_Item__r.Fiscal_Period__c,
                result
            );
        }

        Assert.areEqual(414000, resultsByLine.get('cash|12/31/2025').Candidate_Value__c);
        Assert.areEqual('$414,000', resultsByLine.get('cash|12/31/2025').Raw_Value__c);
        Assert.areEqual(372600, resultsByLine.get('cash|12/31/2024').Candidate_Value__c);
        Assert.areEqual(1646000, resultsByLine.get('current_assets|12/31/2025').Candidate_Value__c);
        Assert.areEqual(1481400, resultsByLine.get('current_assets|12/31/2024').Candidate_Value__c);
        Assert.areEqual(473000, resultsByLine.get('current_liabilities|12/31/2025').Candidate_Value__c);
        Assert.areEqual(440700, resultsByLine.get('current_liabilities|12/31/2024').Candidate_Value__c);
        Assert.areEqual('balance_sheet', resultsByLine.get('cash|12/31/2025').Spread_Line_Item__r.Statement_Type__c);
    }

    @IsTest
    static void infersFiscalYearsWhenDateHeadersAreNotPresent() {
        Spread_Pilot_Run__c run = SpreadTestDataFactory.createPilotRun();
        Spread_Document__c document = SpreadTestDataFactory.createDocument(run.Id);
        document.Statement_Type__c = null;
        document.Fiscal_Period__c = null;
        update document;

        SpreadEvidenceService.createTextEvidence(
            document.Id,
            'CONSOLIDATED BALANCE SHEETS\n'
                + 'LIABILITIES AND EQUITY 2025 2024\n'
                + 'Total current liabilities $473,000 $440,700',
            1,
            'Docling',
            'native_pdf'
        );

        Test.startTest();
        SpreadingParseOutput output = SpreadEvidenceParserService.parseDocument(document.Id, null);
        Test.stopTest();

        Assert.areEqual('Complete', output.parsingStatus);
        Assert.areEqual(2, output.lineItemCount);

        Map<String, Decimal> valuesByPeriod = new Map<String, Decimal>();
        for (Spread_Path_Result__c result : [
            SELECT Candidate_Value__c, Spread_Line_Item__r.Fiscal_Period__c,
                   Spread_Line_Item__r.Statement_Type__c
            FROM Spread_Path_Result__c
            WHERE Spread_Document__c = :document.Id
        ]) {
            valuesByPeriod.put(result.Spread_Line_Item__r.Fiscal_Period__c, result.Candidate_Value__c);
            Assert.areEqual('balance_sheet', result.Spread_Line_Item__r.Statement_Type__c);
        }

        Assert.areEqual(473000, valuesByPeriod.get('FY2025'));
        Assert.areEqual(440700, valuesByPeriod.get('FY2024'));
    }

    @IsTest
    static void handlesMissingEvidenceAndInvocableInputValidation() {
        Spread_Pilot_Run__c run = SpreadTestDataFactory.createPilotRun();
        Spread_Document__c document = SpreadTestDataFactory.createDocument(run.Id);

        Test.startTest();
        SpreadingParseOutput missingId = SpreadEvidenceParserService.parseDocument(null, null);
        SpreadingParseOutput missingEvidence = SpreadEvidenceParserService.parseDocument(document.Id, null);
        SpreadingParseInput invalidRequest = new SpreadingParseInput();
        invalidRequest.spreadDocumentId = 'not-an-id';
        List<SpreadingParseOutput> outputs =
            ParseExtractedFinancialEvidence.parse(new List<SpreadingParseInput>{ invalidRequest });
        Test.stopTest();

        Assert.areEqual('Failed', missingId.parsingStatus);
        Assert.isTrue(missingId.errorMessage.contains('Spread Document Id is required'));
        Assert.areEqual('Needs Review', missingEvidence.parsingStatus);
        Assert.isTrue(missingEvidence.errorMessage.contains('No successful extraction evidence blocks'));
        Assert.areEqual(1, outputs.size());
        Assert.areEqual('Failed', outputs[0].parsingStatus);
        Assert.isTrue(outputs[0].errorMessage.contains('valid Spread_Document__c Id'));
    }
}
