public with sharing class SpreadingPolicyService {

    @TestVisible
    private SpreadPolicySelector selector;

    public SpreadingPolicyService() {
        this.selector = new SpreadPolicySelector();
    }

    @TestVisible
    private SpreadingPolicyService(SpreadPolicySelector selector) {
        this.selector = selector;
    }

    // Returns the most-specific active policy for the given context.
    // Returns null if no active policy covers the effective date.
    public Spreading_Policy__c resolveActivePolicy(
        String portfolio,
        String industry,
        String borrowerSize,
        Date effectiveDate
    ) {
        List<Spreading_Policy__c> candidates = selector.getActivePolicies(
            effectiveDate != null ? effectiveDate : Date.today()
        );
        return SpreadPolicyRules.mostSpecific(candidates, portfolio, industry, borrowerSize);
    }

    // Returns all thresholds for the resolved active policy.
    // Returns empty list if no policy is found.
    public List<Spreading_Threshold__c> resolveThresholds(
        String portfolio,
        String industry,
        String borrowerSize,
        Date effectiveDate
    ) {
        Spreading_Policy__c policy = resolveActivePolicy(portfolio, industry, borrowerSize, effectiveDate);
        if (policy == null) {
            return new List<Spreading_Threshold__c>();
        }
        return selector.getThresholdsForPolicy(policy.Id);
    }

    // Activates a policy after validating dual approval, date consistency,
    // and threshold completeness. Retires any prior active policy with
    // the same portfolio/industry/borrower-size combination.
    // Writes a Spread_Audit_Log__c entry on success.
    // Returns an error message or null on success.
    public String activatePolicy(Id policyId) {
        Spreading_Policy__c policy = selector.getById(policyId);
        if (policy == null) {
            return 'Policy not found.';
        }
        if (!SpreadPolicyRules.canActivate(policy)) {
            if (!SpreadPolicyRules.isDualApproved(policy)) {
                return 'Policy requires dual approval before activation.';
            }
            if (policy.Status__c == 'Active') {
                return 'Policy is already active.';
            }
            if (policy.Status__c == 'Retired') {
                return 'Retired policies cannot be reactivated.';
            }
            return 'Policy cannot be activated in its current state.';
        }

        List<Spreading_Threshold__c> thresholds = selector.getThresholdsForPolicy(policyId);
        for (Spreading_Threshold__c t : thresholds) {
            String thresholdError = SpreadPolicyRules.validateThreshold(t);
            if (thresholdError != null) {
                return 'Threshold validation failed for ' + t.Name + ': ' + thresholdError;
            }
        }

        List<Spreading_Policy__c> overlapping = selector.getActivePolicies(Date.today());
        List<Spreading_Policy__c> toRetire = new List<Spreading_Policy__c>();
        for (Spreading_Policy__c existing : overlapping) {
            if (existing.Id == policyId) continue;
            if (existing.Portfolio__c == policy.Portfolio__c
                && existing.Industry__c == policy.Industry__c
                && existing.Borrower_Size__c == policy.Borrower_Size__c) {
                toRetire.add(new Spreading_Policy__c(Id = existing.Id, Status__c = 'Retired'));
            }
        }

        Savepoint sp = Database.setSavepoint();
        try {
            if (!toRetire.isEmpty()) {
                update toRetire;
            }
            update new Spreading_Policy__c(Id = policyId, Status__c = 'Active');
            writeAuditLog('Policy Activated', policyId, 'Spreading_Policy__c',
                          'Pending Approval', 'Active', null);
        } catch (Exception e) {
            Database.rollback(sp);
            return 'Activation failed: ' + e.getMessage();
        }
        return null;
    }

    // Records first-approver signature. Does not activate; activation requires
    // a subsequent call to activatePolicy after both approvals are present.
    public String recordFirstApproval(Id policyId, Id approverId) {
        Spreading_Policy__c policy = selector.getById(policyId);
        if (policy == null)                         return 'Policy not found.';
        if (policy.Status__c == 'Active')           return 'Active policies cannot be re-approved.';
        if (policy.Status__c == 'Retired')          return 'Retired policies cannot be approved.';
        if (policy.Approved_By__c != null)          return 'First approval already recorded.';
        if (policy.Secondary_Approved_By__c == approverId) {
            return 'The same user cannot provide both approvals.';
        }

        try {
            update new Spreading_Policy__c(
                Id = policyId,
                Approved_By__c = approverId,
                Approved_At__c = Datetime.now(),
                Status__c = 'Pending Approval'
            );
            writeAuditLog('First Approval Recorded', policyId, 'Spreading_Policy__c',
                          null, null, 'First approver: ' + approverId);
        } catch (Exception e) {
            return 'Approval failed: ' + e.getMessage();
        }
        return null;
    }

    // Records second-approver signature. Policy moves to Pending Approval
    // awaiting explicit activatePolicy call.
    public String recordSecondApproval(Id policyId, Id approverId) {
        Spreading_Policy__c policy = selector.getById(policyId);
        if (policy == null)                      return 'Policy not found.';
        if (policy.Status__c == 'Active')        return 'Active policies cannot be re-approved.';
        if (policy.Status__c == 'Retired')       return 'Retired policies cannot be approved.';
        if (policy.Approved_By__c == null)       return 'First approval must be recorded before second.';
        if (policy.Secondary_Approved_By__c != null) return 'Second approval already recorded.';
        if (policy.Approved_By__c == approverId) return 'The same user cannot provide both approvals.';

        try {
            update new Spreading_Policy__c(
                Id = policyId,
                Secondary_Approved_By__c = approverId,
                Secondary_Approved_At__c = Datetime.now()
            );
            writeAuditLog('Second Approval Recorded', policyId, 'Spreading_Policy__c',
                          null, null, 'Second approver: ' + approverId);
        } catch (Exception e) {
            return 'Approval failed: ' + e.getMessage();
        }
        return null;
    }

    private static void writeAuditLog(
        String eventType,
        Id recordId,
        String objectName,
        String previousValue,
        String newValue,
        String notes
    ) {
        try {
            insert new Spread_Audit_Log__c(
                Event_Type__c = eventType,
                Record_Id__c = String.valueOf(recordId),
                Object_Name__c = objectName,
                Notes__c = notes
            );
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Audit log write failed: ' + e.getMessage());
        }
    }
}
