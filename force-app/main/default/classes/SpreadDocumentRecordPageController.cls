public with sharing class SpreadDocumentRecordPageController {
    public class DocumentView {
        @AuraEnabled public DocumentSummary summary;
        @AuraEnabled public List<EvidenceRow> evidences = new List<EvidenceRow>();
        @AuraEnabled public List<LineItemRow> lineItems = new List<LineItemRow>();
        @AuraEnabled public List<PathResultRow> pathResults = new List<PathResultRow>();
        @AuraEnabled public List<ExceptionRow> exceptions = new List<ExceptionRow>();
    }

    public class DocumentSummary {
        @AuraEnabled public Id documentId;
        @AuraEnabled public String documentName;
        @AuraEnabled public String borrowerName;
        @AuraEnabled public Id pilotRunId;
        @AuraEnabled public String pilotRunName;
        @AuraEnabled public String extractionStatus;
        @AuraEnabled public String parsingStatus;
        @AuraEnabled public Decimal pageCount;
        @AuraEnabled public Datetime extractedAt;
        @AuraEnabled public Datetime parsedAt;
        @AuraEnabled public Integer evidenceCount;
        @AuraEnabled public Integer lineItemCount;
        @AuraEnabled public Integer pathResultCount;
        @AuraEnabled public Integer exceptionCount;
    }

    public class EvidenceRow {
        @AuraEnabled public Id evidenceId;
        @AuraEnabled public String evidenceName;
        @AuraEnabled public String provider;
        @AuraEnabled public String extractionEngine;
        @AuraEnabled public String extractionStatus;
        @AuraEnabled public String evidenceType;
        @AuraEnabled public Decimal sourcePage;
        @AuraEnabled public String sourceCoordinates;
        @AuraEnabled public Decimal extractionConfidence;
    }

    public class LineItemRow {
        @AuraEnabled public Id lineItemId;
        @AuraEnabled public String lineItemName;
        @AuraEnabled public String normalizedLine;
        @AuraEnabled public String statementType;
        @AuraEnabled public String fiscalPeriod;
        @AuraEnabled public Boolean material;
        @AuraEnabled public Boolean includeInReport;
        @AuraEnabled public Decimal sourcePage;
        @AuraEnabled public Id primaryEvidenceId;
    }

    public class PathResultRow {
        @AuraEnabled public Id pathResultId;
        @AuraEnabled public String pathResultName;
        @AuraEnabled public String pathKey;
        @AuraEnabled public String normalizedLine;
        @AuraEnabled public Decimal manualValue;
        @AuraEnabled public Decimal candidateValue;
        @AuraEnabled public Decimal varianceAmount;
        @AuraEnabled public Decimal variancePct;
        @AuraEnabled public String certificationStatus;
        @AuraEnabled public Boolean exceptionFlag;
        @AuraEnabled public String errorType;
        @AuraEnabled public Id primaryEvidenceId;
    }

    public class ExceptionRow {
        @AuraEnabled public Id exceptionId;
        @AuraEnabled public String exceptionName;
        @AuraEnabled public String severity;
        @AuraEnabled public String reason;
        @AuraEnabled public Datetime createdDate;
    }

    @AuraEnabled(cacheable=true)
    public static DocumentView getDocumentView(Id spreadDocumentId) {
        if (spreadDocumentId == null) {
            throw new AuraHandledException('Spread document ID is required.');
        }

        List<Spread_Document__c> documents = [
            SELECT Id, Name, Borrower__r.Name, Pilot_Run__c, Pilot_Run__r.Name,
                   Extraction_Status__c, Parsing_Status__c, Page_Count__c, Extracted_At__c, Parsed_At__c
            FROM Spread_Document__c
            WHERE Id = :spreadDocumentId
            WITH USER_MODE
            LIMIT 1
        ];
        if (documents.isEmpty()) {
            throw new AuraHandledException('Spread document not found.');
        }

        Spread_Document__c document = documents[0];
        DocumentView view = new DocumentView();
        view.summary = buildSummary(document);

        List<Spread_Extraction_Evidence__c> evidences = [
            SELECT Id, Name, Provider__c, Extraction_Engine__c, Extraction_Status__c, Evidence_Type__c,
                   Source_Page__c, Source_Coordinates__c, Extraction_Confidence__c
            FROM Spread_Extraction_Evidence__c
            WHERE Spread_Document__c = :spreadDocumentId
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 100
        ];
        view.summary.evidenceCount = evidences.size();
        for (Spread_Extraction_Evidence__c evidence : evidences) {
            EvidenceRow row = new EvidenceRow();
            row.evidenceId = evidence.Id;
            row.evidenceName = evidence.Name;
            row.provider = evidence.Provider__c;
            row.extractionEngine = evidence.Extraction_Engine__c;
            row.extractionStatus = evidence.Extraction_Status__c;
            row.evidenceType = evidence.Evidence_Type__c;
            row.sourcePage = evidence.Source_Page__c;
            row.sourceCoordinates = evidence.Source_Coordinates__c;
            row.extractionConfidence = evidence.Extraction_Confidence__c;
            view.evidences.add(row);
        }

        List<Spread_Line_Item__c> lineItems = [
            SELECT Id, Name, Normalized_Line__c, Statement_Type__c, Fiscal_Period__c,
                   Material__c, Include_In_Report__c, Source_Page__c, Primary_Evidence__c
            FROM Spread_Line_Item__c
            WHERE Spread_Document__c = :spreadDocumentId
            WITH USER_MODE
            ORDER BY Statement_Type__c NULLS LAST, Normalized_Line__c NULLS LAST
            LIMIT 200
        ];
        view.summary.lineItemCount = lineItems.size();
        for (Spread_Line_Item__c lineItem : lineItems) {
            LineItemRow row = new LineItemRow();
            row.lineItemId = lineItem.Id;
            row.lineItemName = lineItem.Name;
            row.normalizedLine = lineItem.Normalized_Line__c;
            row.statementType = lineItem.Statement_Type__c;
            row.fiscalPeriod = lineItem.Fiscal_Period__c;
            row.material = lineItem.Material__c;
            row.includeInReport = lineItem.Include_In_Report__c;
            row.sourcePage = lineItem.Source_Page__c;
            row.primaryEvidenceId = lineItem.Primary_Evidence__c;
            view.lineItems.add(row);
        }

        List<Spread_Path_Result__c> pathResults = [
            SELECT Id, Name, Path_Key__c, Spread_Line_Item__r.Normalized_Line__c,
                   Manual_Value__c, Candidate_Value__c, Variance_Amount__c, Variance_Pct__c,
                   Certification_Status__c, Exception_Flag__c, Error_Type__c, Primary_Evidence__c
            FROM Spread_Path_Result__c
            WHERE Spread_Document__c = :spreadDocumentId
            WITH USER_MODE
            ORDER BY Path_Key__c NULLS LAST, Spread_Line_Item__r.Normalized_Line__c NULLS LAST
            LIMIT 500
        ];
        view.summary.pathResultCount = pathResults.size();
        for (Spread_Path_Result__c pathResult : pathResults) {
            PathResultRow row = new PathResultRow();
            row.pathResultId = pathResult.Id;
            row.pathResultName = pathResult.Name;
            row.pathKey = pathResult.Path_Key__c;
            row.normalizedLine = pathResult.Spread_Line_Item__r == null ? null : pathResult.Spread_Line_Item__r.Normalized_Line__c;
            row.manualValue = pathResult.Manual_Value__c;
            row.candidateValue = pathResult.Candidate_Value__c;
            row.varianceAmount = pathResult.Variance_Amount__c;
            row.variancePct = pathResult.Variance_Pct__c;
            row.certificationStatus = pathResult.Certification_Status__c;
            row.exceptionFlag = pathResult.Exception_Flag__c;
            row.errorType = pathResult.Error_Type__c;
            row.primaryEvidenceId = pathResult.Primary_Evidence__c;
            view.pathResults.add(row);
        }

        List<Spread_Exception__c> exceptions = [
            SELECT Id, Name, Severity__c, Exception_Reason__c, CreatedDate
            FROM Spread_Exception__c
            WHERE Spread_Document__c = :spreadDocumentId
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 100
        ];
        view.summary.exceptionCount = exceptions.size();
        for (Spread_Exception__c exceptionRecord : exceptions) {
            ExceptionRow row = new ExceptionRow();
            row.exceptionId = exceptionRecord.Id;
            row.exceptionName = exceptionRecord.Name;
            row.severity = exceptionRecord.Severity__c;
            row.reason = exceptionRecord.Exception_Reason__c;
            row.createdDate = exceptionRecord.CreatedDate;
            view.exceptions.add(row);
        }

        return view;
    }

    private static DocumentSummary buildSummary(Spread_Document__c document) {
        DocumentSummary summary = new DocumentSummary();
        summary.documentId = document.Id;
        summary.documentName = document.Name;
        summary.borrowerName = document.Borrower__r == null ? null : document.Borrower__r.Name;
        summary.pilotRunId = document.Pilot_Run__c;
        summary.pilotRunName = document.Pilot_Run__r == null ? null : document.Pilot_Run__r.Name;
        summary.extractionStatus = document.Extraction_Status__c;
        summary.parsingStatus = document.Parsing_Status__c;
        summary.pageCount = document.Page_Count__c;
        summary.extractedAt = document.Extracted_At__c;
        summary.parsedAt = document.Parsed_At__c;
        summary.evidenceCount = 0;
        summary.lineItemCount = 0;
        summary.pathResultCount = 0;
        summary.exceptionCount = 0;
        return summary;
    }
}
