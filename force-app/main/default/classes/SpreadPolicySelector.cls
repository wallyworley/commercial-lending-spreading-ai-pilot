public inherited sharing virtual class SpreadPolicySelector {

    public virtual List<Spreading_Policy__c> getActivePolicies(Date effectiveDate) {
        return [
            SELECT Id, Name, Version__c, Status__c, Portfolio__c, Industry__c,
                   Borrower_Size__c, Effective_Start_Date__c, Effective_End_Date__c,
                   Approved_By__c, Approved_At__c,
                   Secondary_Approved_By__c, Secondary_Approved_At__c,
                   Description__c
            FROM Spreading_Policy__c
            WHERE Status__c = 'Active'
              AND (Effective_Start_Date__c = null OR Effective_Start_Date__c <= :effectiveDate)
              AND (Effective_End_Date__c = null OR Effective_End_Date__c >= :effectiveDate)
            WITH USER_MODE
            LIMIT 200
        ];
    }

    public virtual List<Spreading_Threshold__c> getThresholdsForPolicy(Id policyId) {
        return [
            SELECT Id, Name, Spreading_Policy__c,
                   Metric__c, Operator__c,
                   Minimum_Value__c, Maximum_Value__c,
                   Severity_When_Failed__c,
                   Applies_To_Material_Line__c,
                   Requires_Exception_Approval__c,
                   Narrative_Guidance__c
            FROM Spreading_Threshold__c
            WHERE Spreading_Policy__c = :policyId
            WITH USER_MODE
            ORDER BY Metric__c
        ];
    }

    public virtual Spreading_Policy__c getById(Id policyId) {
        List<Spreading_Policy__c> results = [
            SELECT Id, Name, Version__c, Status__c, Portfolio__c, Industry__c,
                   Borrower_Size__c, Effective_Start_Date__c, Effective_End_Date__c,
                   Approved_By__c, Approved_At__c,
                   Secondary_Approved_By__c, Secondary_Approved_At__c,
                   Change_Rationale__c, Description__c
            FROM Spreading_Policy__c
            WHERE Id = :policyId
            WITH USER_MODE
            LIMIT 1
        ];
        return results.isEmpty() ? null : results[0];
    }
}
