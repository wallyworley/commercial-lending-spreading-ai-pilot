public with sharing class SpreadWorkbenchController {
    public static final Integer DEFAULT_PAGE_SIZE = 25;
    public static final Integer MAX_PAGE_SIZE = 100;

    public class SpreadReviewPage {
        @AuraEnabled public List<SpreadLineRow> lines;
        @AuraEnabled public Integer totalCount;
        @AuraEnabled public List<String> pathKeys;
    }

    public class SpreadLineRow {
        @AuraEnabled public Id lineItemId;
        @AuraEnabled public Id spreadDocumentId;
        @AuraEnabled public String documentName;
        @AuraEnabled public String normalizedLine;
        @AuraEnabled public String statementType;
        @AuraEnabled public String fiscalPeriod;
        @AuraEnabled public Boolean material;
        @AuraEnabled public Boolean includeInReport;
        @AuraEnabled public List<PathResultRow> pathResults;
    }

    public class PathResultRow {
        @AuraEnabled public Id pathResultId;
        @AuraEnabled public String pathKey;
        @AuraEnabled public Decimal manualValue;
        @AuraEnabled public Decimal candidateValue;
        @AuraEnabled public Decimal reviewedValue;
        @AuraEnabled public String reviewedReason;
        @AuraEnabled public Id reviewedById;
        @AuraEnabled public Datetime reviewedAt;
        @AuraEnabled public Decimal varianceAmount;
        @AuraEnabled public Decimal variancePct;
        @AuraEnabled public String certificationStatus;
        @AuraEnabled public Boolean exceptionFlag;
        @AuraEnabled public String errorType;
        @AuraEnabled public Id primaryEvidenceId;
    }

    public class PilotRunOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String label;
        @AuraEnabled public String status;
        @AuraEnabled public String portfolio;
        @AuraEnabled public Datetime startedAt;
        @AuraEnabled public Integer documentCount;
        @AuraEnabled public Integer lineItemCount;
        @AuraEnabled public Id commercialLoanId;
        @AuraEnabled public String commercialLoanName;
    }

    public class MaterialErrorRow {
        @AuraEnabled public Id pathResultId;
        @AuraEnabled public String pathKey;
        @AuraEnabled public String borrowerName;
        @AuraEnabled public String documentName;
        @AuraEnabled public String normalizedLine;
        @AuraEnabled public Decimal manualValue;
        @AuraEnabled public Decimal candidateValue;
        @AuraEnabled public Decimal varianceAmount;
        @AuraEnabled public String errorType;
        @AuraEnabled public String certificationStatus;
    }

    @AuraEnabled(cacheable=true)
    public static List<PilotRunOption> getPilotRuns() {
        List<Spread_Pilot_Run__c> runs = [
            SELECT Id, Name, Status__c, Portfolio__c, Started_At__c, Commercial_Loan__c, Commercial_Loan__r.Name
            FROM Spread_Pilot_Run__c
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 50
        ];
        Set<Id> runIds = new Map<Id, Spread_Pilot_Run__c>(runs).keySet();
        Map<Id, Integer> documentCounts = countByRun('Spread_Document__c', runIds);
        Map<Id, Integer> lineCounts = countByRun('Spread_Line_Item__c', runIds);

        List<PilotRunOption> options = new List<PilotRunOption>();
        for (Spread_Pilot_Run__c run : runs) {
            options.add(toPilotRunOption(run, documentCounts, lineCounts));
        }
        return options;
    }

    @AuraEnabled
    public static PilotRunOption getOrCreatePilotRunForLoan(Id commercialLoanId) {
        if (commercialLoanId == null) {
            throw new AuraHandledException('Commercial loan ID is required.');
        }

        Commercial_Loan__c loan = [
            SELECT Id, Name, Borrower__c, Borrower__r.Name, Portfolio__c, Stage__c
            FROM Commercial_Loan__c
            WHERE Id = :commercialLoanId
            WITH USER_MODE
            LIMIT 1
        ];

        List<Spread_Pilot_Run__c> runs = [
            SELECT Id, Name, Status__c, Portfolio__c, Started_At__c, Commercial_Loan__c, Commercial_Loan__r.Name
            FROM Spread_Pilot_Run__c
            WHERE Commercial_Loan__c = :commercialLoanId
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        Spread_Pilot_Run__c run;
        if (runs.isEmpty()) {
            String borrowerName = loan.Borrower__r == null ? loan.Name : loan.Borrower__r.Name;
            run = new Spread_Pilot_Run__c(
                Commercial_Loan__c = loan.Id,
                Status__c = 'Spreading',
                Portfolio__c = String.isBlank(loan.Portfolio__c) ? 'C&I' : loan.Portfolio__c,
                Started_At__c = System.now(),
                Notes__c = 'Auto-created spreading workspace for ' + borrowerName + ' commercial loan ' + loan.Name + '.'
            );
            insert run;

            if (loan.Stage__c == 'Intake') {
                update new Commercial_Loan__c(Id = loan.Id, Stage__c = 'Spreading');
            }

            run = [
                SELECT Id, Name, Status__c, Portfolio__c, Started_At__c, Commercial_Loan__c, Commercial_Loan__r.Name
                FROM Spread_Pilot_Run__c
                WHERE Id = :run.Id
                WITH USER_MODE
                LIMIT 1
            ];
        } else {
            run = runs[0];
        }

        Set<Id> runIds = new Set<Id>{ run.Id };
        Map<Id, Integer> documentCounts = countByRun('Spread_Document__c', runIds);
        Map<Id, Integer> lineCounts = countByRun('Spread_Line_Item__c', runIds);
        return toPilotRunOption(run, documentCounts, lineCounts);
    }

    @AuraEnabled(cacheable=true)
    public static List<MaterialErrorRow> getMaterialErrors(Id pilotRunId) {
        if (pilotRunId == null) {
            return new List<MaterialErrorRow>();
        }

        List<MaterialErrorRow> rows = new List<MaterialErrorRow>();
        for (Spread_Path_Result__c result : [
            SELECT Id, Path_Key__c, Manual_Value__c, Candidate_Value__c, Error_Type__c,
                   Certification_Status__c, Spread_Document__r.Name, Spread_Document__r.Borrower__r.Name,
                   Spread_Line_Item__r.Normalized_Line__c, Spread_Line_Item__r.Material__c
            FROM Spread_Path_Result__c
            WHERE Pilot_Run__c = :pilotRunId
            AND Spread_Line_Item__r.Material__c = true
            AND Exception_Flag__c = false
            WITH USER_MODE
            LIMIT 2000
        ]) {
            if (result.Manual_Value__c == null) {
                continue;
            }
            Decimal manualValue = valueOrZero(result.Manual_Value__c);
            Decimal candidateValue = valueOrZero(result.Candidate_Value__c);
            if (manualValue == candidateValue) {
                continue;
            }

            MaterialErrorRow row = new MaterialErrorRow();
            row.pathResultId = result.Id;
            row.pathKey = result.Path_Key__c;
            row.borrowerName = result.Spread_Document__r == null || result.Spread_Document__r.Borrower__r == null
                ? null
                : result.Spread_Document__r.Borrower__r.Name;
            row.documentName = result.Spread_Document__r == null ? null : result.Spread_Document__r.Name;
            row.normalizedLine = result.Spread_Line_Item__r == null ? null : result.Spread_Line_Item__r.Normalized_Line__c;
            row.manualValue = manualValue;
            row.candidateValue = candidateValue;
            row.varianceAmount = manualValue - candidateValue;
            row.errorType = result.Error_Type__c;
            row.certificationStatus = result.Certification_Status__c;
            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled(cacheable=false)
    public static SpreadReviewPage getSpreadReviewPage(
        Id pilotRunId, Integer pageSize, Integer pageOffset, Boolean materialOnly, Id spreadDocumentId
    ) {
        if (pilotRunId == null) {
            SpreadReviewPage empty = new SpreadReviewPage();
            empty.lines = new List<SpreadLineRow>();
            empty.totalCount = 0;
            empty.pathKeys = new List<String>();
            return empty;
        }

        Integer safeSize = (pageSize == null || pageSize <= 0) ? DEFAULT_PAGE_SIZE : Math.min(pageSize, MAX_PAGE_SIZE);
        Integer safeOffset = (pageOffset == null || pageOffset < 0) ? 0 : pageOffset;
        Boolean filterMaterial = materialOnly == true;

        List<Spread_Line_Item__c> lines;
        Integer totalCount;
        Boolean filterDocument = spreadDocumentId != null;

        if (filterMaterial && filterDocument) {
            lines = [
                SELECT Id, Spread_Document__c, Spread_Document__r.Name, Normalized_Line__c, Statement_Type__c,
                       Fiscal_Period__c, Material__c, Include_In_Report__c
                FROM Spread_Line_Item__c
                WHERE Pilot_Run__c = :pilotRunId AND Material__c = true AND Spread_Document__c = :spreadDocumentId
                WITH USER_MODE
                ORDER BY Statement_Type__c NULLS LAST, Normalized_Line__c NULLS LAST
                LIMIT :safeSize OFFSET :safeOffset
            ];
            totalCount = [
                SELECT COUNT() FROM Spread_Line_Item__c
                WHERE Pilot_Run__c = :pilotRunId AND Material__c = true AND Spread_Document__c = :spreadDocumentId
                WITH USER_MODE
            ];
        } else if (filterMaterial) {
            lines = [
                SELECT Id, Spread_Document__c, Spread_Document__r.Name, Normalized_Line__c, Statement_Type__c,
                       Fiscal_Period__c, Material__c, Include_In_Report__c
                FROM Spread_Line_Item__c
                WHERE Pilot_Run__c = :pilotRunId AND Material__c = true
                WITH USER_MODE
                ORDER BY Statement_Type__c NULLS LAST, Normalized_Line__c NULLS LAST
                LIMIT :safeSize OFFSET :safeOffset
            ];
            totalCount = [
                SELECT COUNT() FROM Spread_Line_Item__c
                WHERE Pilot_Run__c = :pilotRunId AND Material__c = true
                WITH USER_MODE
            ];
        } else if (filterDocument) {
            lines = [
                SELECT Id, Spread_Document__c, Spread_Document__r.Name, Normalized_Line__c, Statement_Type__c,
                       Fiscal_Period__c, Material__c, Include_In_Report__c
                FROM Spread_Line_Item__c
                WHERE Pilot_Run__c = :pilotRunId AND Spread_Document__c = :spreadDocumentId
                WITH USER_MODE
                ORDER BY Statement_Type__c NULLS LAST, Normalized_Line__c NULLS LAST
                LIMIT :safeSize OFFSET :safeOffset
            ];
            totalCount = [
                SELECT COUNT() FROM Spread_Line_Item__c
                WHERE Pilot_Run__c = :pilotRunId AND Spread_Document__c = :spreadDocumentId
                WITH USER_MODE
            ];
        } else {
            lines = [
                SELECT Id, Spread_Document__c, Spread_Document__r.Name, Normalized_Line__c, Statement_Type__c,
                       Fiscal_Period__c, Material__c, Include_In_Report__c
                FROM Spread_Line_Item__c
                WHERE Pilot_Run__c = :pilotRunId
                WITH USER_MODE
                ORDER BY Statement_Type__c NULLS LAST, Normalized_Line__c NULLS LAST
                LIMIT :safeSize OFFSET :safeOffset
            ];
            totalCount = [
                SELECT COUNT() FROM Spread_Line_Item__c
                WHERE Pilot_Run__c = :pilotRunId
                WITH USER_MODE
            ];
        }

        Set<Id> lineIds = new Map<Id, Spread_Line_Item__c>(lines).keySet();
        Map<Id, List<PathResultRow>> resultsByLine = new Map<Id, List<PathResultRow>>();
        Set<String> pathKeySet = new Set<String>();

        for (Spread_Path_Result__c result : [
            SELECT Id, Path_Key__c, Manual_Value__c, Candidate_Value__c,
                   Reviewed_Value__c, Reviewed_Reason__c, Reviewed_By__c, Reviewed_At__c,
                   Variance_Amount__c, Variance_Pct__c, Certification_Status__c,
                   Exception_Flag__c, Error_Type__c, Spread_Line_Item__c, Primary_Evidence__c
            FROM Spread_Path_Result__c
            WHERE Spread_Line_Item__c IN :lineIds
            WITH USER_MODE
            ORDER BY Path_Key__c
        ]) {
            if (!resultsByLine.containsKey(result.Spread_Line_Item__c)) {
                resultsByLine.put(result.Spread_Line_Item__c, new List<PathResultRow>());
            }
            List<PathResultRow> bucket = resultsByLine.get(result.Spread_Line_Item__c);
            PathResultRow pr = new PathResultRow();
            pr.pathResultId = result.Id;
            pr.pathKey = result.Path_Key__c;
            pr.manualValue = result.Manual_Value__c;
            pr.candidateValue = result.Candidate_Value__c;
            pr.reviewedValue = result.Reviewed_Value__c;
            pr.reviewedReason = result.Reviewed_Reason__c;
            pr.reviewedById = result.Reviewed_By__c;
            pr.reviewedAt = result.Reviewed_At__c;
            pr.varianceAmount = result.Variance_Amount__c;
            pr.variancePct = result.Variance_Pct__c;
            pr.certificationStatus = result.Certification_Status__c;
            pr.exceptionFlag = result.Exception_Flag__c;
            pr.errorType = result.Error_Type__c;
            pr.primaryEvidenceId = result.Primary_Evidence__c;
            bucket.add(pr);
            if (result.Path_Key__c != null) {
                pathKeySet.add(result.Path_Key__c);
            }
        }

        List<SpreadLineRow> lineRows = new List<SpreadLineRow>();
        for (Spread_Line_Item__c line : lines) {
            SpreadLineRow row = new SpreadLineRow();
            row.lineItemId = line.Id;
            row.spreadDocumentId = line.Spread_Document__c;
            row.documentName = line.Spread_Document__r == null ? null : line.Spread_Document__r.Name;
            row.normalizedLine = line.Normalized_Line__c;
            row.statementType = line.Statement_Type__c;
            row.fiscalPeriod = line.Fiscal_Period__c;
            row.material = line.Material__c;
            row.includeInReport = line.Include_In_Report__c;
            row.pathResults = resultsByLine.containsKey(line.Id) ? resultsByLine.get(line.Id) : new List<PathResultRow>();
            lineRows.add(row);
        }

        List<String> sortedPathKeys = new List<String>(pathKeySet);
        sortedPathKeys.sort();

        SpreadReviewPage page = new SpreadReviewPage();
        page.lines = lineRows;
        page.totalCount = totalCount;
        page.pathKeys = sortedPathKeys;
        return page;
    }

    private static Map<Id, Integer> countByRun(String objectApiName, Set<Id> runIds) {
        Map<Id, Integer> counts = new Map<Id, Integer>();
        if (runIds.isEmpty()) {
            return counts;
        }

        String query = 'SELECT Pilot_Run__c runId, COUNT(Id) total FROM ' + objectApiName +
            ' WHERE Pilot_Run__c IN :runIds GROUP BY Pilot_Run__c';
        for (AggregateResult result : Database.query(query, AccessLevel.USER_MODE)) {
            counts.put((Id) result.get('runId'), Integer.valueOf(String.valueOf(result.get('total'))));
        }
        return counts;
    }

    private static PilotRunOption toPilotRunOption(
        Spread_Pilot_Run__c run,
        Map<Id, Integer> documentCounts,
        Map<Id, Integer> lineCounts
    ) {
        PilotRunOption option = new PilotRunOption();
        option.id = run.Id;
        option.label = run.Name;
        option.status = run.Status__c;
        option.portfolio = run.Portfolio__c;
        option.startedAt = run.Started_At__c;
        option.documentCount = documentCounts.containsKey(run.Id) ? documentCounts.get(run.Id) : 0;
        option.lineItemCount = lineCounts.containsKey(run.Id) ? lineCounts.get(run.Id) : 0;
        option.commercialLoanId = run.Commercial_Loan__c;
        option.commercialLoanName = run.Commercial_Loan__r == null ? null : run.Commercial_Loan__r.Name;
        return option;
    }

    private static Decimal valueOrZero(Decimal value) {
        return value == null ? 0 : value;
    }

    // ─── Policy Thresholds Tab ───────────────────────────────────────────────

    public class PolicyThresholdResult {
        @AuraEnabled public String policyId;
        @AuraEnabled public String policyName;
        @AuraEnabled public String policyVersion;
        @AuraEnabled public String policyStatus;
        @AuraEnabled public String portfolio;
        @AuraEnabled public Date effectiveStart;
        @AuraEnabled public Date effectiveEnd;
        @AuraEnabled public Boolean dualApproved;
        @AuraEnabled public List<ThresholdRow> thresholds;
    }

    public class ThresholdRow {
        @AuraEnabled public String thresholdId;
        @AuraEnabled public String metric;
        @AuraEnabled public String operator;
        @AuraEnabled public Decimal minimumValue;
        @AuraEnabled public Decimal maximumValue;
        @AuraEnabled public String severity;
        @AuraEnabled public Boolean appliesToMaterialLine;
        @AuraEnabled public Boolean requiresExceptionApproval;
        @AuraEnabled public String narrativeGuidance;
        @AuraEnabled public String displayRange;
    }

    @AuraEnabled(cacheable=false)
    public static PolicyThresholdResult getActivePolicyThresholds(String portfolio) {
        SpreadingPolicyService svc = new SpreadingPolicyService();
        Spreading_Policy__c policy = svc.resolveActivePolicy(
            portfolio, null, null, Date.today()
        );

        PolicyThresholdResult result = new PolicyThresholdResult();

        if (policy == null) {
            result.thresholds = new List<ThresholdRow>();
            return result;
        }

        result.policyId      = policy.Id;
        result.policyName    = policy.Name;
        result.policyVersion = policy.Version__c;
        result.policyStatus  = policy.Status__c;
        result.portfolio     = policy.Portfolio__c;
        result.effectiveStart = policy.Effective_Start_Date__c;
        result.effectiveEnd   = policy.Effective_End_Date__c;
        result.dualApproved  = SpreadPolicyRules.isDualApproved(policy);

        List<Spreading_Threshold__c> raw = svc.resolveThresholds(
            portfolio, null, null, Date.today()
        );

        List<ThresholdRow> rows = new List<ThresholdRow>();
        for (Spreading_Threshold__c t : raw) {
            ThresholdRow row = new ThresholdRow();
            row.thresholdId              = t.Id;
            row.metric                   = t.Metric__c;
            row.operator                 = t.Operator__c;
            row.minimumValue             = t.Minimum_Value__c;
            row.maximumValue             = t.Maximum_Value__c;
            row.severity                 = t.Severity_When_Failed__c;
            row.appliesToMaterialLine    = t.Applies_To_Material_Line__c;
            row.requiresExceptionApproval = t.Requires_Exception_Approval__c;
            row.narrativeGuidance        = t.Narrative_Guidance__c;
            row.displayRange             = buildDisplayRange(t);
            rows.add(row);
        }
        result.thresholds = rows;
        return result;
    }

    private static String buildDisplayRange(Spreading_Threshold__c t) {
        String op  = t.Operator__c;
        Decimal mn = t.Minimum_Value__c;
        Decimal mx = t.Maximum_Value__c;
        if (op == 'Between' && mn != null && mx != null) {
            return mn.stripTrailingZeros().toPlainString()
                + ' – '
                + mx.stripTrailingZeros().toPlainString();
        }
        if ((op == '>=' || op == '>') && mn != null) {
            return op + ' ' + mn.stripTrailingZeros().toPlainString();
        }
        if ((op == '<=' || op == '<') && mx != null) {
            return op + ' ' + mx.stripTrailingZeros().toPlainString();
        }
        return '—';
    }
}
