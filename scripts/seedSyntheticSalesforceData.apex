Spread_Pilot_Run__c run = new Spread_Pilot_Run__c(
    Status__c = 'Review',
    Portfolio__c = 'C&I',
    Started_At__c = System.now(),
    Notes__c = 'Synthetic C&I spreading evidence pilot seeded from local project.'
);
insert run;

Account borrower = new Account(
    Name = 'Northstar Precision Components LLC',
    Industry = 'Manufacturing'
);
insert borrower;

Spread_Document__c document = new Spread_Document__c(
    Name = 'Northstar FY2025 Audited Financials',
    Pilot_Run__c = run.Id,
    Borrower__c = borrower.Id,
    Document_Type__c = 'audited_financials',
    Statement_Type__c = 'multi_statement',
    Fiscal_Period__c = 'FY2025',
    Scenario_Type__c = 'clean_native_pdf',
    Source_System__c = 'Salesforce Files',
    Extraction_Status__c = 'Complete',
    Page_Count__c = 18,
    Contains_Confidential_Data__c = true
);
insert document;

List<String> labels = new List<String>{
    'revenue',
    'cost_of_goods_sold',
    'gross_profit',
    'operating_expenses',
    'ebitda',
    'cash',
    'current_assets',
    'current_liabilities',
    'total_liabilities',
    'net_worth_equity'
};

Map<String, Decimal> manualValues = new Map<String, Decimal>{
    'revenue' => 5250000,
    'cost_of_goods_sold' => 3180000,
    'gross_profit' => 2070000,
    'operating_expenses' => 1670000,
    'ebitda' => 400000,
    'cash' => 620000,
    'current_assets' => 1740000,
    'current_liabilities' => 510000,
    'total_liabilities' => 1825000,
    'net_worth_equity' => 2490000
};

Map<String, Spread_Line_Item__c> linesByName = new Map<String, Spread_Line_Item__c>();
List<Spread_Line_Item__c> lines = new List<Spread_Line_Item__c>();
Integer sourcePage = 4;
for (String label : labels) {
    Spread_Line_Item__c line = new Spread_Line_Item__c(
        Name = label,
        Pilot_Run__c = run.Id,
        Spread_Document__c = document.Id,
        Normalized_Line__c = label,
        Statement_Type__c = label.contains('assets') || label.contains('liabilities') || label.contains('equity') || label == 'cash'
            ? 'balance_sheet'
            : 'income_statement',
        Fiscal_Period__c = 'FY2025',
        Source_Page__c = sourcePage,
        Source_Coordinates__c = 'x=128;y=' + String.valueOf(120 + (sourcePage * 18)) + ';w=240;h=16',
        Material__c = true,
        Include_In_Report__c = true,
        Review_Note__c = 'Synthetic gold-standard spread line.'
    );
    lines.add(line);
    sourcePage++;
}
insert lines;
for (Spread_Line_Item__c line : lines) {
    linesByName.put(line.Normalized_Line__c, line);
}

List<Spread_Path_Result__c> results = new List<Spread_Path_Result__c>();
for (String label : labels) {
    Decimal manualValue = manualValues.get(label);

    results.add(new Spread_Path_Result__c(
        Pilot_Run__c = run.Id,
        Spread_Document__c = document.Id,
        Spread_Line_Item__c = linesByName.get(label).Id,
        Path_Key__c = 'manual_ncino_control',
        Manual_Value__c = manualValue,
        Candidate_Value__c = manualValue,
        Confidence__c = 1,
        Exception_Flag__c = false,
        Certification_Status__c = 'Certified',
        Baseline_Minutes__c = 12,
        Candidate_Minutes__c = 12
    ));

    Decimal ncinoCandidate = manualValue;
    Boolean ncinoException = false;
    String ncinoStatus = 'Certified';
    String ncinoErrorType;
    String ncinoExceptionReason;
    if (label == 'ebitda') {
        ncinoCandidate = 370000;
        ncinoErrorType = 'mapping';
    } else if (label == 'current_liabilities') {
        ncinoCandidate = 500000;
        ncinoException = true;
        ncinoStatus = 'Exception Approved';
        ncinoErrorType = 'ambiguous_label';
        ncinoExceptionReason = 'Synthetic ambiguous current portion of long-term debt presentation.';
    }

    results.add(new Spread_Path_Result__c(
        Pilot_Run__c = run.Id,
        Spread_Document__c = document.Id,
        Spread_Line_Item__c = linesByName.get(label).Id,
        Path_Key__c = 'ncino_automated_spreading',
        Manual_Value__c = manualValue,
        Candidate_Value__c = ncinoCandidate,
        Confidence__c = label == 'current_liabilities' ? 0.61 : 0.92,
        Exception_Flag__c = ncinoException,
        Exception_Reason__c = ncinoExceptionReason,
        Error_Type__c = ncinoErrorType,
        Certification_Status__c = ncinoStatus,
        Baseline_Minutes__c = 12,
        Candidate_Minutes__c = 7
    ));

    results.add(new Spread_Path_Result__c(
        Pilot_Run__c = run.Id,
        Spread_Document__c = document.Id,
        Spread_Line_Item__c = linesByName.get(label).Id,
        Path_Key__c = 'salesforce_native_staging',
        Manual_Value__c = manualValue,
        Candidate_Value__c = manualValue,
        Confidence__c = 0.95,
        Exception_Flag__c = false,
        Certification_Status__c = 'Certified',
        Baseline_Minutes__c = 12,
        Candidate_Minutes__c = 6
    ));
}
insert results;

List<SpreadScorecardService.ScorecardSummary> summaries = SpreadScorecardService.calculateForRun(run.Id);

System.debug('SEEDED_SPREAD_PILOT_RUN_ID=' + run.Id);
System.debug('SEEDED_SPREAD_DOCUMENT_ID=' + document.Id);
System.debug('SEEDED_SCORECARD_COUNT=' + summaries.size());
