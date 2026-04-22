// Pure domain logic — no SOQL, no DML. Testable with direct SObject or scalar input.
public without sharing class SpreadScorecardRules {
    public static final Decimal EXACT_MATCH_GATE = 0.98;
    public static final Decimal DOLLAR_ACCURACY_GATE = 0.995;
    public static final Decimal TIME_REDUCTION_GATE = 0.30;

    public class GateInput {
        public Decimal exactMatchRate;
        public Decimal dollarWeightedAccuracy;
        public Integer uncaughtMaterialErrors;
        public Boolean requiresTimeReduction;
        public Decimal timeReduction;
        public Decimal certificationRate;
    }

    public class GateResult {
        public Boolean passed;
        public List<String> failedGates;
        public String recommendation;
    }

    public static GateResult evaluate(GateInput input) {
        GateResult result = new GateResult();
        result.failedGates = new List<String>();

        if (input.exactMatchRate == null || input.exactMatchRate < EXACT_MATCH_GATE) {
            result.failedGates.add('exact_match_rate below ' + (EXACT_MATCH_GATE * 100).setScale(1) + '%');
        }
        if (input.dollarWeightedAccuracy == null || input.dollarWeightedAccuracy < DOLLAR_ACCURACY_GATE) {
            result.failedGates.add('dollar_weighted_accuracy below ' + (DOLLAR_ACCURACY_GATE * 100).setScale(1) + '%');
        }
        if (input.uncaughtMaterialErrors == null || input.uncaughtMaterialErrors > 0) {
            result.failedGates.add('uncaught_material_errors: ' + (input.uncaughtMaterialErrors == null ? 'unknown' : String.valueOf(input.uncaughtMaterialErrors)));
        }
        if (input.requiresTimeReduction == true && (input.timeReduction == null || input.timeReduction < TIME_REDUCTION_GATE)) {
            result.failedGates.add('time_reduction below ' + (TIME_REDUCTION_GATE * 100).setScale(0) + '%');
        }
        if (input.certificationRate == null || input.certificationRate < 1) {
            result.failedGates.add('certification_rate below 100%');
        }

        result.passed = result.failedGates.isEmpty();
        result.recommendation = result.passed
            ? 'Path meets pilot gates for this scorecard run.'
            : 'Do not proceed. Failed gates: ' + String.join(result.failedGates, '; ');
        return result;
    }
}
