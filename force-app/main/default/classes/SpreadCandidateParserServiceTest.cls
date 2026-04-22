@IsTest
private class SpreadCandidateParserServiceTest {
    @IsTest
    static void importsParserJsonIntoDraftLineAndPathResults() {
        Spread_Pilot_Run__c run = SpreadTestDataFactory.createPilotRun();
        Spread_Document__c document = SpreadTestDataFactory.createDocument(run.Id);
        SpreadEvidenceService.EvidenceImportResult evidenceResult = SpreadEvidenceService.createTextEvidence(
            document.Id,
            'Revenue: $8,450,000\nEBITDA: $1,530,000',
            1,
            'Docling',
            'native_pdf'
        );

        String parserJson = JSON.serialize(new Map<String, Object>{
            'document_id' => String.valueOf(document.Id),
            'statement_type' => 'income_statement',
            'fiscal_period' => 'FY2025',
            'parser_version' => 'test-v1',
            'candidates' => new List<Object>{
                new Map<String, Object>{
                    'normalized_line' => 'revenue',
                    'raw_label' => 'Revenue',
                    'raw_value' => '$8,450,000',
                    'normalized_value' => 8450000,
                    'evidence_id' => String.valueOf(evidenceResult.evidenceId),
                    'source_page' => 1,
                    'source_coordinates' => '',
                    'confidence' => 0.96,
                    'exception_reason' => null,
                    'status' => 'draft'
                },
                new Map<String, Object>{
                    'normalized_line' => 'ebitda',
                    'raw_label' => 'EBITDA',
                    'raw_value' => '$1,530,000',
                    'normalized_value' => 1530000,
                    'evidence_id' => String.valueOf(evidenceResult.evidenceId),
                    'source_page' => 1,
                    'source_coordinates' => '',
                    'confidence' => 0.96,
                    'exception_reason' => null,
                    'status' => 'draft'
                }
            },
            'exceptions' => new List<Object>()
        });

        Test.startTest();
        SpreadCandidateParserService.ParserImportResult result = SpreadCandidateParserService.importParserOutput(
            document.Id,
            parserJson,
            'salesforce_native_staging'
        );
        Test.stopTest();

        Assert.areEqual(2, result.lineItemCount);
        Assert.areEqual(2, result.pathResultCount);
        Assert.areEqual(0, result.exceptionCount);
        Assert.areEqual('Complete', result.parsingStatus);

        List<Spread_Line_Item__c> lines = [
            SELECT Normalized_Line__c, Primary_Evidence__c, Material__c
            FROM Spread_Line_Item__c
            WHERE Spread_Document__c = :document.Id
            ORDER BY Normalized_Line__c
        ];
        Assert.areEqual(2, lines.size());
        Assert.areEqual(evidenceResult.evidenceId, lines[0].Primary_Evidence__c);
        Assert.areEqual(true, lines[0].Material__c);

        List<Spread_Path_Result__c> pathResults = [
            SELECT Path_Key__c, Candidate_Value__c, Raw_Label__c, Raw_Value__c,
                   Primary_Evidence__c, Certification_Status__c
            FROM Spread_Path_Result__c
            WHERE Spread_Document__c = :document.Id
            ORDER BY Raw_Label__c
        ];
        Assert.areEqual(2, pathResults.size());
        Assert.areEqual('salesforce_native_staging', pathResults[0].Path_Key__c);
        Assert.areEqual(evidenceResult.evidenceId, pathResults[0].Primary_Evidence__c);
        Assert.areEqual('Uncertified', pathResults[0].Certification_Status__c);

        Spread_Document__c updatedDocument = [
            SELECT Parsing_Status__c, Parsed_At__c
            FROM Spread_Document__c
            WHERE Id = :document.Id
        ];
        Assert.areEqual('Complete', updatedDocument.Parsing_Status__c);
        Assert.isNotNull(updatedDocument.Parsed_At__c);
    }

    @IsTest
    static void parserExceptionsMarkDocumentNeedsReview() {
        Spread_Pilot_Run__c run = SpreadTestDataFactory.createPilotRun();
        Spread_Document__c document = SpreadTestDataFactory.createDocument(run.Id);

        String parserJson = JSON.serialize(new Map<String, Object>{
            'document_id' => String.valueOf(document.Id),
            'statement_type' => 'income_statement',
            'fiscal_period' => 'FY2025',
            'parser_version' => 'test-v1',
            'candidates' => new List<Object>{
                new Map<String, Object>{
                    'normalized_line' => 'revenue',
                    'raw_label' => 'Revenue',
                    'raw_value' => '$8,450,000',
                    'normalized_value' => 8450000,
                    'source_page' => 1,
                    'confidence' => 0.96,
                    'exception_reason' => null,
                    'status' => 'draft'
                }
            },
            'exceptions' => new List<Object>{
                new Map<String, Object>{
                    'reason' => 'Duplicate candidate for revenue',
                    'severity' => 'warning',
                    'source_page' => 1,
                    'raw_text' => 'Revenue: $8,460,000'
                }
            }
        });

        Test.startTest();
        SpreadCandidateParserService.ParserImportResult result = SpreadCandidateParserService.importParserOutput(
            document.Id,
            parserJson,
            null
        );
        Test.stopTest();

        Assert.areEqual(1, result.exceptionCount);
        Assert.areEqual('Needs Review', result.parsingStatus);

        List<Spread_Exception__c> exceptions = [
            SELECT Exception_Reason__c, Severity__c
            FROM Spread_Exception__c
            WHERE Spread_Document__c = :document.Id
        ];
        Assert.areEqual(1, exceptions.size());
        Assert.isTrue(exceptions[0].Exception_Reason__c.contains('Duplicate candidate'));
        Assert.areEqual('Warning', exceptions[0].Severity__c);
    }

    @IsTest
    static void invalidJsonCreatesExceptionAndFailsParsing() {
        Spread_Pilot_Run__c run = SpreadTestDataFactory.createPilotRun();
        Spread_Document__c document = SpreadTestDataFactory.createDocument(run.Id);

        Test.startTest();
        SpreadCandidateParserService.ParserImportResult result = SpreadCandidateParserService.importParserOutput(
            document.Id,
            'not-json',
            null
        );
        Test.stopTest();

        Assert.isTrue(result.errorMessage.contains('could not be deserialized'));
        Assert.areEqual(1, result.exceptionCount);

        Spread_Document__c updated = [
            SELECT Parsing_Status__c
            FROM Spread_Document__c
            WHERE Id = :document.Id
        ];
        Assert.areEqual('Failed', updated.Parsing_Status__c);
    }

    @IsTest
    static void missingCandidatesCreatesNeedsReviewException() {
        Spread_Pilot_Run__c run = SpreadTestDataFactory.createPilotRun();
        Spread_Document__c document = SpreadTestDataFactory.createDocument(run.Id);
        String parserJson = JSON.serialize(new Map<String, Object>{
            'document_id' => String.valueOf(document.Id),
            'statement_type' => 'income_statement',
            'fiscal_period' => 'FY2025',
            'parser_version' => 'test-v1',
            'candidates' => new List<Object>(),
            'exceptions' => new List<Object>()
        });

        Test.startTest();
        SpreadCandidateParserService.ParserImportResult result = SpreadCandidateParserService.importParserOutput(
            document.Id,
            parserJson,
            null
        );
        Test.stopTest();

        Assert.areEqual('Parser JSON did not contain candidate spread lines.', result.errorMessage);
        Assert.areEqual(1, result.exceptionCount);
    }

    @IsTest
    static void skipsInvalidCandidatesAndNormalizesHardStopSeverity() {
        Spread_Pilot_Run__c run = SpreadTestDataFactory.createPilotRun();
        Spread_Document__c document = SpreadTestDataFactory.createDocument(run.Id);
        String parserJson = JSON.serialize(new Map<String, Object>{
            'document_id' => String.valueOf(document.Id),
            'statement_type' => 'income_statement',
            'fiscal_period' => 'FY2025',
            'parser_version' => 'test-v1',
            'candidates' => new List<Object>{
                new Map<String, Object>{
                    'raw_label' => 'Missing normalized line',
                    'raw_value' => '$1'
                },
                new Map<String, Object>{
                    'normalized_line' => 'revenue',
                    'raw_label' => 'Revenue',
                    'raw_value' => '$8,450,000',
                    'normalized_value' => 8450000,
                    'evidence_id' => 'not-a-salesforce-id',
                    'source_page' => 1,
                    'confidence' => 0.96,
                    'exception_reason' => 'Review duplicate revenue labels.',
                    'status' => 'exception'
                }
            },
            'exceptions' => new List<Object>{
                new Map<String, Object>{
                    'reason' => 'Unable to resolve period',
                    'severity' => 'hard_stop'
                }
            }
        });

        Test.startTest();
        SpreadCandidateParserService.ParserImportResult result = SpreadCandidateParserService.importParserOutput(
            document.Id,
            parserJson,
            'custom_test_path'
        );
        Test.stopTest();

        Assert.areEqual(1, result.lineItemCount);
        Assert.areEqual(1, result.pathResultCount);
        Assert.areEqual(1, result.exceptionCount);
        Assert.areEqual('Needs Review', result.parsingStatus);

        Spread_Path_Result__c pathResult = [
            SELECT Path_Key__c, Exception_Flag__c, Exception_Status__c, Certification_Status__c, Error_Type__c
            FROM Spread_Path_Result__c
            WHERE Spread_Document__c = :document.Id
            LIMIT 1
        ];
        Assert.areEqual('custom_test_path', pathResult.Path_Key__c);
        Assert.areEqual(true, pathResult.Exception_Flag__c);
        Assert.areEqual('Open', pathResult.Exception_Status__c);
        Assert.areEqual('Exception Pending', pathResult.Certification_Status__c);
        Assert.areEqual('mapping', pathResult.Error_Type__c);

        Spread_Exception__c exceptionRecord = [
            SELECT Severity__c
            FROM Spread_Exception__c
            WHERE Spread_Document__c = :document.Id
            LIMIT 1
        ];
        Assert.areEqual('Critical', exceptionRecord.Severity__c);
    }
}
