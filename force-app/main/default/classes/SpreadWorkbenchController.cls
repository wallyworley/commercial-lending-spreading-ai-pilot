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
        @AuraEnabled public Decimal varianceAmount;
        @AuraEnabled public Decimal variancePct;
        @AuraEnabled public String certificationStatus;
        @AuraEnabled public Boolean exceptionFlag;
        @AuraEnabled public String errorType;
    }

    public class PilotRunOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String label;
        @AuraEnabled public String status;
        @AuraEnabled public String portfolio;
        @AuraEnabled public Datetime startedAt;
        @AuraEnabled public Integer documentCount;
        @AuraEnabled public Integer lineItemCount;
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
            SELECT Id, Name, Status__c, Portfolio__c, Started_At__c
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
            PilotRunOption option = new PilotRunOption();
            option.id = run.Id;
            option.label = run.Name;
            option.status = run.Status__c;
            option.portfolio = run.Portfolio__c;
            option.startedAt = run.Started_At__c;
            option.documentCount = documentCounts.containsKey(run.Id) ? documentCounts.get(run.Id) : 0;
            option.lineItemCount = lineCounts.containsKey(run.Id) ? lineCounts.get(run.Id) : 0;
            options.add(option);
        }
        return options;
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
        Id pilotRunId, Integer pageSize, Integer pageOffset, Boolean materialOnly
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

        if (filterMaterial) {
            lines = [
                SELECT Id, Normalized_Line__c, Statement_Type__c, Fiscal_Period__c, Material__c, Include_In_Report__c
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
        } else {
            lines = [
                SELECT Id, Normalized_Line__c, Statement_Type__c, Fiscal_Period__c, Material__c, Include_In_Report__c
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
                   Variance_Amount__c, Variance_Pct__c, Certification_Status__c,
                   Exception_Flag__c, Error_Type__c, Spread_Line_Item__c
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
            pr.varianceAmount = result.Variance_Amount__c;
            pr.variancePct = result.Variance_Pct__c;
            pr.certificationStatus = result.Certification_Status__c;
            pr.exceptionFlag = result.Exception_Flag__c;
            pr.errorType = result.Error_Type__c;
            bucket.add(pr);
            if (result.Path_Key__c != null) {
                pathKeySet.add(result.Path_Key__c);
            }
        }

        List<SpreadLineRow> lineRows = new List<SpreadLineRow>();
        for (Spread_Line_Item__c line : lines) {
            SpreadLineRow row = new SpreadLineRow();
            row.lineItemId = line.Id;
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

    private static Decimal valueOrZero(Decimal value) {
        return value == null ? 0 : value;
    }
}
