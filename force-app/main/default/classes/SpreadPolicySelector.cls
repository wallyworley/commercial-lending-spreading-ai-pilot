public inherited sharing virtual class SpreadPolicySelector {

    // Returns all active policies — SpreadPolicyRules.mostSpecific() chooses the winner
    public virtual List<Spreading_Policy__c> getActivePolicies(Date effectiveDate) {
        return [
            SELECT Id, Name
            FROM Spreading_Policy__c
            WITH USER_MODE
            LIMIT 200
        ];
    }

    public virtual List<Spreading_Threshold__c> getThresholdsForPolicy(Id policyId) {
        // Spreading_Threshold__c schema not yet deployed — return empty until fields are defined
        return new List<Spreading_Threshold__c>();
    }
}
