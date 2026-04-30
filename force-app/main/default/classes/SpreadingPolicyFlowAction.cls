public with sharing class SpreadingPolicyFlowAction {

    public enum ActionType {
        SUBMIT_FOR_APPROVAL,
        RECORD_FIRST_APPROVAL,
        RECORD_SECOND_APPROVAL,
        ACTIVATE_POLICY
    }

    public class FlowRequest {
        @InvocableVariable(label='Policy Id' required=true)
        public Id policyId;

        @InvocableVariable(label='Action' description='SUBMIT_FOR_APPROVAL | RECORD_FIRST_APPROVAL | RECORD_SECOND_APPROVAL | ACTIVATE' required=true)
        public String action;

        @InvocableVariable(label='Approver Id' description='Required for RECORD_FIRST_APPROVAL and RECORD_SECOND_APPROVAL')
        public Id approverId;
    }

    public class FlowResult {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Error Message')
        public String errorMessage;

        @InvocableVariable(label='New Policy Status')
        public String newStatus;
    }

    @InvocableMethod(
        label='Execute Policy Approval Action'
        description='Submits for approval, records first or second approval, or activates a Spreading_Policy__c record.'
        category='Spreading Policy'
    )
    public static List<FlowResult> execute(List<FlowRequest> requests) {
        List<FlowResult> results = new List<FlowResult>();
        SpreadingPolicyService svc = new SpreadingPolicyService();

        for (FlowRequest req : requests) {
            FlowResult res = new FlowResult();
            try {
                String actionUpper = req.action == null ? '' : req.action.toUpperCase().trim();
                if (actionUpper == 'SUBMIT_FOR_APPROVAL') {
                    res.errorMessage = submitForApproval(req.policyId);
                } else if (actionUpper == 'RECORD_FIRST_APPROVAL') {
                    res.errorMessage = svc.recordFirstApproval(req.policyId, req.approverId);
                } else if (actionUpper == 'RECORD_SECOND_APPROVAL') {
                    res.errorMessage = svc.recordSecondApproval(req.policyId, req.approverId);
                } else if (actionUpper == 'ACTIVATE') {
                    res.errorMessage = svc.activatePolicy(req.policyId);
                } else {
                    res.errorMessage = 'Unknown action: ' + req.action;
                }

                if (String.isBlank(res.errorMessage)) {
                    res.success = true;
                    res.newStatus = queryStatus(req.policyId);
                } else {
                    res.success = false;
                }
            } catch (Exception e) {
                res.success = false;
                res.errorMessage = e.getMessage();
            }
            results.add(res);
        }
        return results;
    }

    private static String submitForApproval(Id policyId) {
        if (policyId == null) {
            return 'Policy Id is required.';
        }
        List<Spreading_Policy__c> policies = [
            SELECT Id, Status__c FROM Spreading_Policy__c WHERE Id = :policyId WITH USER_MODE LIMIT 1
        ];
        if (policies.isEmpty()) {
            return 'Policy not found.';
        }
        Spreading_Policy__c policy = policies[0];
        if (policy.Status__c != 'Draft') {
            return 'Only Draft policies can be submitted for approval. Current status: ' + policy.Status__c;
        }
        policy.Status__c = 'Pending Approval';
        update as user policy;
        return null;
    }

    private static String queryStatus(Id policyId) {
        List<Spreading_Policy__c> policies = [
            SELECT Status__c FROM Spreading_Policy__c WHERE Id = :policyId WITH USER_MODE LIMIT 1
        ];
        return policies.isEmpty() ? null : policies[0].Status__c;
    }
}
