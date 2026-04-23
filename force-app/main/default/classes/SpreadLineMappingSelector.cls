public inherited sharing class SpreadLineMappingSelector {
    public virtual List<Spread_Line_Mapping__mdt> getActiveMappings(String statementType) {
        String normalizedStatementType = String.isBlank(statementType) ? null : statementType.trim();
        return [
            SELECT DeveloperName, MasterLabel, Accepted_Label__c, Active__c, Material_Default__c,
                   Normalized_Line__c, Priority__c, Prompt_Guidance__c, Requires_Reviewer__c, Statement_Type__c
            FROM Spread_Line_Mapping__mdt
            WHERE Active__c = true
            AND (
                Statement_Type__c = :normalizedStatementType
                OR Statement_Type__c = null
                OR Statement_Type__c = ''
            )
            ORDER BY Priority__c ASC, DeveloperName ASC
        ];
    }
}
