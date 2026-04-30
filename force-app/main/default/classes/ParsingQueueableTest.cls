@IsTest
private class ParsingQueueableTest {
    @IsTest
    static void delegatesToDeterministicEvidenceParser() {
        Spread_Pilot_Run__c run = SpreadTestDataFactory.createPilotRun();
        Spread_Document__c document = SpreadTestDataFactory.createDocument(run.Id);
        document.Statement_Type__c = 'income_statement';
        update document;

        SpreadEvidenceService.createTextEvidence(
            document.Id,
            'Revenue: $8,450,000',
            1,
            'Docling',
            'native_pdf'
        );

        Test.startTest();
        System.enqueueJob(new ParsingQueueable(document.Id));
        Test.stopTest();

        Spread_Document__c parsedDocument = [
            SELECT Parsing_Status__c
            FROM Spread_Document__c
            WHERE Id = :document.Id
        ];
        Assert.areEqual('Complete', parsedDocument.Parsing_Status__c);

        List<Spread_Path_Result__c> results = [
            SELECT Path_Key__c, Candidate_Value__c, Certification_Status__c
            FROM Spread_Path_Result__c
            WHERE Spread_Document__c = :document.Id
        ];
        Assert.areEqual(1, results.size(), 'Queueable should create one parsed path result.');
        Assert.areEqual(SpreadEvidenceParserService.DEFAULT_PATH_KEY, results[0].Path_Key__c);
        Assert.areEqual(8450000, results[0].Candidate_Value__c);
        Assert.areEqual('Uncertified', results[0].Certification_Status__c);
    }
}
