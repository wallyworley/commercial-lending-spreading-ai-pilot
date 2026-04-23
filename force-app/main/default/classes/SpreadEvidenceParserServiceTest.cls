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
