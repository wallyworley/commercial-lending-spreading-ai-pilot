public inherited sharing virtual class SpreadLineItemSelector {

    public virtual List<Spread_Line_Item__c> getByPilotRun(Id pilotRunId) {
        return [
            SELECT Id, Normalized_Line__c, Statement_Type__c, Fiscal_Period__c,
                   Material__c, Include_In_Report__c, Review_Note__c,
                   Spread_Document__c, Pilot_Run__c
            FROM Spread_Line_Item__c
            WHERE Pilot_Run__c = :pilotRunId
            WITH USER_MODE
            ORDER BY Normalized_Line__c
        ];
    }

    public virtual List<Spread_Line_Item__c> getForReport(Id pilotRunId) {
        return [
            SELECT Id, Normalized_Line__c, Statement_Type__c, Fiscal_Period__c,
                   Material__c, Include_In_Report__c, Review_Note__c,
                   Spread_Document__c, Pilot_Run__c
            FROM Spread_Line_Item__c
            WHERE Pilot_Run__c = :pilotRunId
            AND Include_In_Report__c = true
            WITH USER_MODE
            ORDER BY Normalized_Line__c
        ];
    }

    public virtual List<Spread_Line_Item__c> getByIds(List<Id> ids) {
        return [
            SELECT Id, Normalized_Line__c, Material__c, Include_In_Report__c,
                   Spread_Document__c, Pilot_Run__c
            FROM Spread_Line_Item__c
            WHERE Id IN :ids
            WITH USER_MODE
        ];
    }
}
