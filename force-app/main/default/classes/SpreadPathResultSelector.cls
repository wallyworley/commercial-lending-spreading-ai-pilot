// inherited sharing inherits the sharing context of the calling service (e.g. with sharing on SpreadScorecardService)
public inherited sharing virtual class SpreadPathResultSelector {

    public virtual List<Spread_Path_Result__c> getForScoring(Id pilotRunId) {
        return [
            SELECT Id, Path_Key__c, Manual_Value__c, Candidate_Value__c, Exception_Flag__c,
                   Certification_Status__c, Baseline_Minutes__c, Candidate_Minutes__c,
                   Spread_Line_Item__r.Material__c
            FROM Spread_Path_Result__c
            WHERE Pilot_Run__c = :pilotRunId
            WITH USER_MODE
        ];
    }

    public virtual List<Spread_Path_Result__c> getMaterialErrors(Id pilotRunId) {
        return [
            SELECT Id, Path_Key__c, Manual_Value__c, Candidate_Value__c, Error_Type__c,
                   Certification_Status__c, Spread_Document__r.Name, Spread_Document__r.Borrower__r.Name,
                   Spread_Line_Item__r.Normalized_Line__c, Spread_Line_Item__r.Material__c
            FROM Spread_Path_Result__c
            WHERE Pilot_Run__c = :pilotRunId
            AND Spread_Line_Item__r.Material__c = true
            AND Exception_Flag__c = false
            WITH USER_MODE
            LIMIT 2000
        ];
    }

    public virtual List<Spread_Path_Result__c> getByIds(List<Id> ids) {
        return [
            SELECT Id, Certification_Status__c, Pilot_Run__c
            FROM Spread_Path_Result__c
            WHERE Id IN :ids
            WITH USER_MODE
            FOR UPDATE
        ];
    }
}
