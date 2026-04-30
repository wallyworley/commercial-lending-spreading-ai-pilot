public with sharing class SpreadPolicyRules {

    // Specificity score: more-specific policies win over broader ones.
    // Portfolio match > industry match > borrower-size match.
    // Used by SpreadingPolicyService to select the active policy for a given context.
    public static Spreading_Policy__c mostSpecific(
        List<Spreading_Policy__c> candidates,
        String portfolio,
        String industry,
        String borrowerSize
    ) {
        if (candidates == null || candidates.isEmpty()) {
            return null;
        }

        Spreading_Policy__c winner = null;
        Integer winnerScore = -1;

        for (Spreading_Policy__c p : candidates) {
            Integer score = specificityScore(p, portfolio, industry, borrowerSize);
            if (score > winnerScore) {
                winnerScore = score;
                winner = p;
            }
        }
        return winner;
    }

    // Returns true if a threshold is failed by the given measured value.
    public static Boolean isFailed(Spreading_Threshold__c threshold, Decimal measuredValue) {
        if (threshold == null || measuredValue == null) {
            return false;
        }
        String op = threshold.Operator__c;
        Decimal minVal = threshold.Minimum_Value__c;
        Decimal maxVal = threshold.Maximum_Value__c;

        if (op == '>=')      return measuredValue < minVal;
        if (op == '>')       return measuredValue <= minVal;
        if (op == '<=')      return measuredValue > maxVal;
        if (op == '<')       return measuredValue >= maxVal;
        if (op == 'Between') return minVal != null && maxVal != null
                                    && (measuredValue < minVal || measuredValue > maxVal);
        return false;
    }

    // Returns true when the policy has both required approvals.
    public static Boolean isDualApproved(Spreading_Policy__c policy) {
        return policy != null
            && policy.Approved_By__c != null
            && policy.Approved_At__c != null
            && policy.Secondary_Approved_By__c != null
            && policy.Secondary_Approved_At__c != null;
    }

    // Returns true when the policy can be activated:
    // must have dual approval, valid effective dates (if set), and Draft or Pending Approval status.
    public static Boolean canActivate(Spreading_Policy__c policy) {
        if (!isDualApproved(policy)) {
            return false;
        }
        if (policy.Status__c == 'Active' || policy.Status__c == 'Retired') {
            return false;
        }
        if (policy.Effective_Start_Date__c != null && policy.Effective_End_Date__c != null
            && policy.Effective_Start_Date__c > policy.Effective_End_Date__c) {
            return false;
        }
        return true;
    }

    // Validates that a threshold is complete and internally consistent.
    // Returns an error message or null if valid.
    public static String validateThreshold(Spreading_Threshold__c t) {
        if (String.isBlank(t.Metric__c))   return 'Metric is required.';
        if (String.isBlank(t.Operator__c)) return 'Operator is required.';

        if (t.Operator__c == 'Between') {
            if (t.Minimum_Value__c == null || t.Maximum_Value__c == null) {
                return 'Both Minimum Value and Maximum Value are required for Between operator.';
            }
            if (t.Minimum_Value__c >= t.Maximum_Value__c) {
                return 'Minimum Value must be less than Maximum Value for Between operator.';
            }
        } else if (t.Operator__c == '>=' || t.Operator__c == '>') {
            if (t.Minimum_Value__c == null) {
                return 'Minimum Value is required for ' + t.Operator__c + ' operator.';
            }
        } else if (t.Operator__c == '<=' || t.Operator__c == '<') {
            if (t.Maximum_Value__c == null) {
                return 'Maximum Value is required for ' + t.Operator__c + ' operator.';
            }
        }
        return null;
    }

    private static Integer specificityScore(
        Spreading_Policy__c p,
        String portfolio,
        String industry,
        String borrowerSize
    ) {
        Integer score = 0;
        if (String.isNotBlank(p.Portfolio__c) && p.Portfolio__c == portfolio) score += 4;
        if (String.isNotBlank(p.Industry__c) && p.Industry__c == industry)   score += 2;
        if (String.isNotBlank(p.Borrower_Size__c) && p.Borrower_Size__c == borrowerSize) score += 1;
        return score;
    }
}
