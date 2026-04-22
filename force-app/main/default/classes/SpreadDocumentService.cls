public with sharing class SpreadDocumentService {
    @TestVisible private static SpreadDocumentSelector documentSelector = new SpreadDocumentSelector();

    public class DocumentRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String extractionStatus;
        @AuraEnabled public String documentStore;
        @AuraEnabled public String documentType;
        @AuraEnabled public String statementType;
        @AuraEnabled public String fiscalPeriod;
        @AuraEnabled public String scenarioType;
        @AuraEnabled public String extractedAt;
        @AuraEnabled public Decimal pageCount;
        @AuraEnabled public String contentDocumentId;
        @AuraEnabled public String ncinSpreadingMode;
    }

    @AuraEnabled
    public static List<Id> onUpload(Id pilotRunId, List<String> contentDocumentIds) {
        if (pilotRunId == null) {
            throw new AuraHandledException('Pilot run ID is required.');
        }
        if (contentDocumentIds == null || contentDocumentIds.isEmpty()) {
            throw new AuraHandledException('At least one document is required.');
        }

        Savepoint checkpoint = Database.setSavepoint();
        try {
            Map<Id, ContentVersion> versionsByDocId = queryContentVersions(contentDocumentIds);

            List<Spread_Document__c> docsToInsert = new List<Spread_Document__c>();
            List<ContentDocumentLink> linksToInsert = new List<ContentDocumentLink>();
            List<Id> createdDocIds = new List<Id>();

            for (String docIdStr : contentDocumentIds) {
                Id contentDocId = (Id) docIdStr;
                ContentVersion version = versionsByDocId.get(contentDocId);

                if (version == null) {
                    continue;
                }

                Spread_Document__c doc = new Spread_Document__c(
                    Pilot_Run__c = pilotRunId,
                    ContentDocumentId__c = contentDocId,
                    Document_Type__c = 'uploaded_document',
                    Document_Store__c = 'salesforce_files',
                    Source_System__c = 'Analyst Upload',
                    Extraction_Status__c = 'Pending',
                    Contains_Confidential_Data__c = false
                );
                docsToInsert.add(doc);
            }

            if (!docsToInsert.isEmpty()) {
                insert docsToInsert;
                createdDocIds.addAll(getIds(docsToInsert));

                for (Spread_Document__c doc : docsToInsert) {
                    linksToInsert.add(new ContentDocumentLink(
                        LinkedEntityId = doc.Id,
                        ContentDocumentId = (Id) doc.ContentDocumentId__c,
                        ShareType = 'V'
                    ));
                }

                if (!linksToInsert.isEmpty()) {
                    insert linksToInsert;
                }

                enqueueExtractions(docsToInsert);
            }

            return createdDocIds;
        } catch (Exception error) {
            Database.rollback(checkpoint);
            throw new AuraHandledException('Upload failed: ' + error.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static List<DocumentRow> getDocuments(Id pilotRunId) {
        if (pilotRunId == null) {
            return new List<DocumentRow>();
        }

        List<DocumentRow> rows = new List<DocumentRow>();
        for (Spread_Document__c doc : documentSelector.getByPilotRun(pilotRunId)) {
            DocumentRow row = new DocumentRow();
            row.id = doc.Id;
            row.name = doc.Name;
            row.extractionStatus = doc.Extraction_Status__c;
            row.documentType = doc.Document_Type__c;
            row.statementType = doc.Statement_Type__c;
            row.fiscalPeriod = doc.Fiscal_Period__c;
            row.scenarioType = doc.Scenario_Type__c;
            row.extractedAt = doc.Extracted_At__c != null ? doc.Extracted_At__c.format() : null;
            row.pageCount = doc.Page_Count__c;
            row.contentDocumentId = doc.ContentDocumentId__c;
            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled
    public static void retryExtraction(Id spreadDocumentId) {
        if (spreadDocumentId == null) {
            throw new AuraHandledException('Document ID is required.');
        }

        Spread_Document__c doc = documentSelector.getById(spreadDocumentId);
        if (doc == null) {
            throw new AuraHandledException('Document not found.');
        }

        Savepoint checkpoint = Database.setSavepoint();
        try {
            doc.Extraction_Status__c = 'Pending';
            update doc;
            System.enqueueJob(new ExtractionQueueable(spreadDocumentId));
        } catch (Exception error) {
            Database.rollback(checkpoint);
            throw new AuraHandledException('Retry failed: ' + error.getMessage());
        }
    }

    private static Map<Id, ContentVersion> queryContentVersions(List<String> contentDocumentIds) {
        Set<Id> idSet = new Set<Id>();
        for (String docId : contentDocumentIds) {
            try {
                idSet.add((Id) docId);
            } catch (Exception e) {
                // Skip invalid IDs
            }
        }

        Map<Id, ContentVersion> versionsByDocId = new Map<Id, ContentVersion>();
        for (ContentVersion version : documentSelector.getVersionsByDocumentIds(idSet)) {
            versionsByDocId.put(version.ContentDocumentId, version);
        }
        return versionsByDocId;
    }

    private static void enqueueExtractions(List<Spread_Document__c> docs) {
        for (Spread_Document__c doc : docs) {
            System.enqueueJob(new ExtractionQueueable(doc.Id));
        }
    }

    private static List<Id> getIds(List<SObject> records) {
        List<Id> ids = new List<Id>();
        for (SObject record : records) {
            ids.add(record.Id);
        }
        return ids;
    }
}
