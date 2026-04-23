public with sharing class SpreadDocumentService {
    @TestVisible private static SpreadDocumentSelector documentSelector = new SpreadDocumentSelector();

    public class DocumentRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String extractionStatus;
        @AuraEnabled public String parsingStatus;
        @AuraEnabled public Integer evidenceCount;
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

    public class BulkParseResult {
        @AuraEnabled public Integer attemptedCount = 0;
        @AuraEnabled public Integer parsedCount = 0;
        @AuraEnabled public Integer skippedCount = 0;
        @AuraEnabled public Integer failedCount = 0;
        @AuraEnabled public List<String> messages = new List<String>();
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
            Set<Id> requestedContentDocumentIds = toIdSet(contentDocumentIds);
            Map<Id, ContentVersion> versionsByDocId = queryContentVersions(contentDocumentIds);
            Map<Id, Spread_Document__c> existingDocsByContentDocumentId = getExistingDocumentsByContentDocumentId(
                pilotRunId,
                requestedContentDocumentIds
            );

            List<Spread_Document__c> docsToInsert = new List<Spread_Document__c>();
            List<ContentDocumentLink> linksToInsert = new List<ContentDocumentLink>();
            List<Id> documentIds = new List<Id>();

            for (String docIdStr : contentDocumentIds) {
                Id contentDocId;
                try {
                    contentDocId = (Id) docIdStr;
                } catch (Exception invalidIdError) {
                    continue;
                }

                if (existingDocsByContentDocumentId.containsKey(contentDocId)) {
                    documentIds.add(existingDocsByContentDocumentId.get(contentDocId).Id);
                    continue;
                }

                ContentVersion version = versionsByDocId.get(contentDocId);
                String documentName = version == null || String.isBlank(version.Title)
                    ? 'Uploaded Financial Document ' + String.valueOf(contentDocId).right(6)
                    : version.Title;

                Spread_Document__c doc = new Spread_Document__c(
                    Name = documentName,
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
                documentIds.addAll(getIds(docsToInsert));

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

            if (documentIds.isEmpty()) {
                throw new AuraHandledException('No upload records were created. Please refresh and try again.');
            }

            return documentIds;
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
        List<Spread_Document__c> documents = documentSelector.getByPilotRun(pilotRunId);
        Map<Id, Integer> evidenceCounts = countEvidenceByDocument(new Map<Id, Spread_Document__c>(documents).keySet());

        for (Spread_Document__c doc : documents) {
            DocumentRow row = new DocumentRow();
            row.id = doc.Id;
            row.name = doc.Name;
            row.extractionStatus = doc.Extraction_Status__c;
            row.parsingStatus = String.isBlank(doc.Parsing_Status__c) ? 'Not Started' : doc.Parsing_Status__c;
            row.evidenceCount = evidenceCounts.containsKey(doc.Id) ? evidenceCounts.get(doc.Id) : 0;
            row.documentType = doc.Document_Type__c;
            row.statementType = doc.Statement_Type__c;
            row.fiscalPeriod = doc.Fiscal_Period__c;
            row.scenarioType = doc.Scenario_Type__c;
            row.extractedAt = doc.Extracted_At__c != null ? doc.Extracted_At__c.format() : null;
            row.pageCount = doc.Page_Count__c;
            row.contentDocumentId = doc.ContentDocumentId__c;
            row.documentStore = doc.Document_Store__c;
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

    @AuraEnabled
    public static SpreadingParseOutput parseDocument(Id spreadDocumentId, String pathKey) {
        if (spreadDocumentId == null) {
            throw new AuraHandledException('Document ID is required.');
        }

        Spread_Document__c doc = documentSelector.getById(spreadDocumentId);
        if (doc == null) {
            throw new AuraHandledException('Document not found.');
        }

        try {
            return SpreadEvidenceParserService.parseDocument(spreadDocumentId, pathKey);
        } catch (Exception error) {
            throw new AuraHandledException('Parse failed: ' + error.getMessage());
        }
    }

    @AuraEnabled
    public static BulkParseResult parseReadyDocuments(Id pilotRunId, String pathKey) {
        if (pilotRunId == null) {
            throw new AuraHandledException('Pilot run ID is required.');
        }

        BulkParseResult summary = new BulkParseResult();
        List<Spread_Document__c> documents = documentSelector.getByPilotRun(pilotRunId);
        Map<Id, Integer> evidenceCounts = countEvidenceByDocument(new Map<Id, Spread_Document__c>(documents).keySet());
        String resolvedPathKey = String.isBlank(pathKey) ? null : pathKey;

        Integer processed = 0;
        for (Spread_Document__c document : documents) {
            if (processed >= 25) {
                summary.skippedCount++;
                summary.messages.add('Stopped after 25 documents to keep parsing within governor limits.');
                break;
            }

            if (document.Extraction_Status__c != 'Complete') {
                summary.skippedCount++;
                continue;
            }
            if (!evidenceCounts.containsKey(document.Id) || evidenceCounts.get(document.Id) == 0) {
                summary.skippedCount++;
                continue;
            }
            if (document.Parsing_Status__c == 'Complete' || document.Parsing_Status__c == 'In Progress') {
                summary.skippedCount++;
                continue;
            }

            processed++;
            summary.attemptedCount++;

            try {
                SpreadingParseOutput result = SpreadEvidenceParserService.parseDocument(document.Id, resolvedPathKey);
                if (!String.isBlank(result.errorMessage)) {
                    summary.failedCount++;
                    summary.messages.add(document.Name + ': ' + result.errorMessage);
                } else {
                    summary.parsedCount++;
                }
            } catch (Exception error) {
                summary.failedCount++;
                summary.messages.add(document.Name + ': Parse failed: ' + error.getMessage());
            }
        }

        return summary;
    }

    private static Map<Id, ContentVersion> queryContentVersions(List<String> contentDocumentIds) {
        Set<Id> idSet = toIdSet(contentDocumentIds);

        Map<Id, ContentVersion> versionsByDocId = new Map<Id, ContentVersion>();
        for (ContentVersion version : documentSelector.getVersionsByDocumentIds(idSet)) {
            versionsByDocId.put(version.ContentDocumentId, version);
        }
        return versionsByDocId;
    }

    private static Set<Id> toIdSet(List<String> ids) {
        Set<Id> idSet = new Set<Id>();
        for (String rawId : ids) {
            try {
                idSet.add((Id) rawId);
            } catch (Exception invalidIdError) {
                // Skip invalid IDs
            }
        }
        return idSet;
    }

    private static Map<Id, Spread_Document__c> getExistingDocumentsByContentDocumentId(
        Id pilotRunId,
        Set<Id> contentDocumentIds
    ) {
        Map<Id, Spread_Document__c> documentsByContentDocumentId = new Map<Id, Spread_Document__c>();
        if (pilotRunId == null || contentDocumentIds.isEmpty()) {
            return documentsByContentDocumentId;
        }

        for (Spread_Document__c document : [
            SELECT Id, ContentDocumentId__c
            FROM Spread_Document__c
            WHERE Pilot_Run__c = :pilotRunId
            AND ContentDocumentId__c IN :contentDocumentIds
            WITH USER_MODE
        ]) {
            documentsByContentDocumentId.put((Id) document.ContentDocumentId__c, document);
        }
        return documentsByContentDocumentId;
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

    private static Map<Id, Integer> countEvidenceByDocument(Set<Id> documentIds) {
        Map<Id, Integer> counts = new Map<Id, Integer>();
        if (documentIds.isEmpty()) {
            return counts;
        }

        for (AggregateResult result : [
            SELECT Spread_Document__c documentId, COUNT(Id) total
            FROM Spread_Extraction_Evidence__c
            WHERE Spread_Document__c IN :documentIds
            WITH USER_MODE
            GROUP BY Spread_Document__c
        ]) {
            counts.put((Id) result.get('documentId'), Integer.valueOf(String.valueOf(result.get('total'))));
        }
        return counts;
    }
}
