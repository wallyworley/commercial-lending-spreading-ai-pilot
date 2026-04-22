public with sharing class SpreadScorecardService {
    public static final Decimal EXACT_MATCH_GATE = SpreadScorecardRules.EXACT_MATCH_GATE;
    public static final Decimal DOLLAR_ACCURACY_GATE = SpreadScorecardRules.DOLLAR_ACCURACY_GATE;
    public static final Decimal TIME_REDUCTION_GATE = SpreadScorecardRules.TIME_REDUCTION_GATE;

    @TestVisible private static SpreadPathResultSelector pathResultSelector = new SpreadPathResultSelector();

    public class ScorecardSummary {
        @AuraEnabled public Id scorecardId;
        @AuraEnabled public String pathKey;
        @AuraEnabled public Boolean passed;
        @AuraEnabled public Decimal exactMatchRate;
        @AuraEnabled public Decimal dollarWeightedAccuracy;
        @AuraEnabled public Decimal timeReduction;
        @AuraEnabled public Decimal certificationRate;
        @AuraEnabled public Integer uncaughtMaterialErrors;
        @AuraEnabled public Integer lineItemCount;
    }

    @AuraEnabled
    public static List<ScorecardSummary> calculateForRun(Id pilotRunId) {
        if (pilotRunId == null) {
            throw new AuraHandledException('Pilot run id is required.');
        }

        Savepoint checkpoint = Database.setSavepoint();
        try {
            Map<String, Spread_Path__mdt> pathDefinitions = Spread_Path__mdt.getAll();
            Map<String, Bucket> buckets = new Map<String, Bucket>();

            for (Spread_Path_Result__c result : pathResultSelector.getForScoring(pilotRunId)) {
                String pathKey = String.isBlank(result.Path_Key__c) ? 'unknown' : result.Path_Key__c;
                if (!buckets.containsKey(pathKey)) {
                    buckets.put(pathKey, new Bucket(pathKey, pathDefinitions.get(pathKey)));
                }
                buckets.get(pathKey).add(result);
            }

            delete [
                SELECT Id
                FROM Pilot_Scorecard_Result__c
                WHERE Pilot_Run__c = :pilotRunId
                AND Status__c != 'Locked'
                WITH USER_MODE
            ];

            List<Pilot_Scorecard_Result__c> scorecards = new List<Pilot_Scorecard_Result__c>();
            for (Bucket bucket : buckets.values()) {
                scorecards.add(bucket.toScorecard(pilotRunId));
            }
            if (!scorecards.isEmpty()) {
                insert scorecards;
            }

            List<ScorecardSummary> summaries = new List<ScorecardSummary>();
            for (Pilot_Scorecard_Result__c scorecard : scorecards) {
                summaries.add(toSummary(scorecard));
            }
            return summaries;
        } catch (Exception error) {
            Database.rollback(checkpoint);
            throw new AuraHandledException('Scorecard calculation failed: ' + error.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<ScorecardSummary> getRunSummary(Id pilotRunId) {
        List<ScorecardSummary> summaries = new List<ScorecardSummary>();
        for (Pilot_Scorecard_Result__c scorecard : [
            SELECT Id, Path_Key__c, Passed__c, Exact_Match_Rate__c, Dollar_Weighted_Accuracy__c,
                   Time_Reduction__c, Certification_Rate__c, Uncaught_Material_Errors__c,
                   Line_Item_Count__c
            FROM Pilot_Scorecard_Result__c
            WHERE Pilot_Run__c = :pilotRunId
            WITH USER_MODE
            ORDER BY Path_Key__c
        ]) {
            summaries.add(toSummary(scorecard));
        }
        return summaries;
    }

    private static ScorecardSummary toSummary(Pilot_Scorecard_Result__c scorecard) {
        ScorecardSummary summary = new ScorecardSummary();
        summary.scorecardId = scorecard.Id;
        summary.pathKey = scorecard.Path_Key__c;
        summary.passed = scorecard.Passed__c;
        summary.exactMatchRate = scorecard.Exact_Match_Rate__c;
        summary.dollarWeightedAccuracy = scorecard.Dollar_Weighted_Accuracy__c;
        summary.timeReduction = scorecard.Time_Reduction__c;
        summary.certificationRate = scorecard.Certification_Rate__c;
        summary.uncaughtMaterialErrors = scorecard.Uncaught_Material_Errors__c == null
            ? 0
            : Integer.valueOf(scorecard.Uncaught_Material_Errors__c);
        summary.lineItemCount = scorecard.Line_Item_Count__c == null
            ? 0
            : Integer.valueOf(scorecard.Line_Item_Count__c);
        return summary;
    }

    private class Bucket {
        private String pathKey;
        private Boolean requiresTimeReduction;
        private Integer rowCount = 0;
        private Integer exactMatches = 0;
        private Decimal absoluteManualValue = 0;
        private Decimal absoluteError = 0;
        private Decimal baselineMinutes = 0;
        private Decimal candidateMinutes = 0;
        private Integer materialRows = 0;
        private Integer certifiedRows = 0;
        private Integer uncaughtMaterialErrors = 0;
        private Integer exceptionRows = 0;

        Bucket(String pathKey, Spread_Path__mdt pathDefinition) {
            this.pathKey = pathKey;
            this.requiresTimeReduction = pathDefinition == null
                ? pathKey != 'manual_ncino_control'
                : pathDefinition.Requires_Time_Reduction__c;
        }

        void add(Spread_Path_Result__c result) {
            Decimal manualValue = valueOrZero(result.Manual_Value__c);
            Decimal candidateValue = valueOrZero(result.Candidate_Value__c);
            Boolean exact = manualValue == candidateValue;
            Boolean material = result.Spread_Line_Item__r != null && result.Spread_Line_Item__r.Material__c == true;
            Boolean exceptionFlag = result.Exception_Flag__c == true;
            Boolean certified = result.Certification_Status__c == 'Certified' || result.Certification_Status__c == 'Exception Approved';

            rowCount++;
            if (exact) exactMatches++;
            absoluteManualValue += manualValue.abs();
            absoluteError += (manualValue - candidateValue).abs();
            baselineMinutes += valueOrZero(result.Baseline_Minutes__c);
            candidateMinutes += valueOrZero(result.Candidate_Minutes__c);
            if (exceptionFlag) exceptionRows++;

            if (material) {
                materialRows++;
                if (certified) certifiedRows++;
                if (!exact && !exceptionFlag) {
                    uncaughtMaterialErrors++;
                }
            }
        }

        Pilot_Scorecard_Result__c toScorecard(Id pilotRunId) {
            Decimal exactMatchRate = rowCount == 0 ? 0 : Decimal.valueOf(exactMatches) / rowCount;
            Decimal dollarWeightedAccuracy = absoluteManualValue == 0
                ? exactMatchRate
                : Decimal.valueOf(1) - (absoluteError / absoluteManualValue);
            if (dollarWeightedAccuracy < 0) {
                dollarWeightedAccuracy = 0;
            }
            Decimal timeReduction = baselineMinutes == 0
                ? 0
                : Decimal.valueOf(1) - (candidateMinutes / baselineMinutes);
            if (timeReduction < 0) {
                timeReduction = 0;
            }
            Decimal certificationRate = materialRows == 0
                ? 1
                : Decimal.valueOf(certifiedRows) / materialRows;

            SpreadScorecardRules.GateInput gateInput = new SpreadScorecardRules.GateInput();
            gateInput.exactMatchRate = exactMatchRate;
            gateInput.dollarWeightedAccuracy = dollarWeightedAccuracy;
            gateInput.uncaughtMaterialErrors = uncaughtMaterialErrors;
            gateInput.requiresTimeReduction = requiresTimeReduction;
            gateInput.timeReduction = timeReduction;
            gateInput.certificationRate = certificationRate;
            SpreadScorecardRules.GateResult gate = SpreadScorecardRules.evaluate(gateInput);

            return new Pilot_Scorecard_Result__c(
                Pilot_Run__c = pilotRunId,
                Path_Key__c = pathKey,
                Passed__c = gate.passed,
                Exact_Match_Rate__c = exactMatchRate,
                Dollar_Weighted_Accuracy__c = dollarWeightedAccuracy,
                Time_Reduction__c = timeReduction,
                Certification_Rate__c = certificationRate,
                Uncaught_Material_Errors__c = uncaughtMaterialErrors,
                Line_Item_Count__c = rowCount,
                Certified_Count__c = certifiedRows,
                Exception_Count__c = exceptionRows,
                Baseline_Time__c = baselineMinutes,
                Actual_Time__c = candidateMinutes,
                Status__c = 'Current',
                Recommendation__c = gate.recommendation
            );
        }
    }

    private static Decimal valueOrZero(Decimal value) {
        return value == null ? 0 : value;
    }
}

