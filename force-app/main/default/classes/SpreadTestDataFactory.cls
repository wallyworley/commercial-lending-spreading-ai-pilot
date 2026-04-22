@IsTest
public class SpreadTestDataFactory {
    public static Spread_Pilot_Run__c createPilotRun() {
        Spread_Pilot_Run__c run = new Spread_Pilot_Run__c(
            Status__c = 'Review',
            Portfolio__c = 'C&I',
            Started_At__c = System.now()
        );
        insert run;
        return run;
    }

    public static Spread_Document__c createDocument(Id runId) {
        Account borrower = new Account(Name = 'Synthetic Borrower');
        insert borrower;

        Spread_Document__c document = new Spread_Document__c(
            Name = 'Synthetic Financial Statement',
            Pilot_Run__c = runId,
            Borrower__c = borrower.Id,
            Document_Type__c = 'audited_financials',
            Statement_Type__c = 'income_statement',
            Fiscal_Period__c = 'FY2025',
            Scenario_Type__c = 'clean_native_pdf',
            Source_System__c = 'Synthetic Demo',
            Extraction_Status__c = 'Complete',
            Page_Count__c = 2
        );
        insert document;
        return document;
    }

    public static Spread_Line_Item__c createLineItem(Id runId, Id documentId, String normalizedLine, Boolean material) {
        Spread_Line_Item__c line = new Spread_Line_Item__c(
            Name = normalizedLine,
            Pilot_Run__c = runId,
            Spread_Document__c = documentId,
            Normalized_Line__c = normalizedLine,
            Statement_Type__c = 'income_statement',
            Fiscal_Period__c = 'FY2025',
            Source_Page__c = 1,
            Material__c = material,
            Include_In_Report__c = true
        );
        insert line;
        return line;
    }

    public static Spread_Path_Result__c createPathResult(
        Id runId,
        Id documentId,
        Id lineItemId,
        String pathKey,
        Decimal manualValue,
        Decimal candidateValue,
        Boolean exceptionFlag,
        String certificationStatus
    ) {
        Spread_Path_Result__c result = new Spread_Path_Result__c(
            Pilot_Run__c = runId,
            Spread_Document__c = documentId,
            Spread_Line_Item__c = lineItemId,
            Path_Key__c = pathKey,
            Manual_Value__c = manualValue,
            Candidate_Value__c = candidateValue,
            Exception_Flag__c = exceptionFlag,
            Certification_Status__c = certificationStatus,
            Baseline_Minutes__c = 12,
            Candidate_Minutes__c = pathKey == 'manual_ncino_control' ? 12 : 7
        );
        insert result;
        return result;
    }
}

