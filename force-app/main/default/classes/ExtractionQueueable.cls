public class ExtractionQueueable implements Queueable, Database.AllowsCallouts {
    private Id spreadDocumentId;
    private static final String DOCLING_SERVICE = 'Spread_Docling_Service_V2';

    public ExtractionQueueable(Id spreadDocumentId) {
        this.spreadDocumentId = spreadDocumentId;
    }

    public void execute(QueueableContext ctx) {
        try {
            SpreadDocumentSelector selector = new SpreadDocumentSelector();
            Spread_Document__c doc = selector.getById(spreadDocumentId);

            if (doc == null) {
                return;
            }

            // Get content version
            ContentVersion version = getContentVersion(doc.ContentDocumentId__c);
            if (version == null) {
                updateDocumentStatus(doc.Id, 'Failed', 'ContentVersion not found');
                return;
            }

            // Extract evidence only. Parsing into draft spread candidates is handled
            // by SpreadCandidateParserService after evidence is stored.
            DoclingResponse doclingResp = callDoclingService(version);
            if (doclingResp == null || doclingResp.tables == null) {
                updateDocumentStatus(
                    doc.Id,
                    'Failed',
                    String.isBlank(doclingResp == null ? null : doclingResp.errorMessage)
                        ? 'Docling extraction failed'
                        : doclingResp.errorMessage
                );
                return;
            }

            SpreadEvidenceService.EvidenceImportResult evidenceResult = SpreadEvidenceService.createTextEvidence(
                doc.Id,
                doclingResp.tables,
                doclingResp.pageCount,
                'Docling',
                String.isBlank(doclingResp.engine) ? 'docling' : doclingResp.engine
            );

            if (!String.isBlank(evidenceResult.errorMessage)) {
                updateDocumentStatus(doc.Id, 'Needs Review', evidenceResult.errorMessage);
            } else {
                System.enqueueJob(new ParsingQueueable(doc.Id));
            }
        } catch (Exception e) {
            updateDocumentStatus(spreadDocumentId, 'Failed', e.getMessage());
        }
    }

    private DoclingResponse callDoclingService(ContentVersion version) {
        try {
            HttpRequest req = new HttpRequest();
            req.setMethod('POST');
            req.setEndpoint('callout:' + DOCLING_SERVICE + '/extract');
            req.setTimeout(120000);

            String fileName = version.Title + '.' + getFileExtension(version.FileType);
            String fileContentType = getContentType(version.FileType);
            String boundary = '----WebKitFormBoundary' + String.valueOf(System.currentTimeMillis());
            String body = buildMultipartBody(boundary, fileName, fileContentType, version.VersionData);

            req.setHeader('Content-Type', 'multipart/form-data; boundary=' + boundary);
            req.setBody(body);

            Http http = new Http();
            HttpResponse res = http.send(req);

            DoclingResponse resp = new DoclingResponse();
            if (res.getStatusCode() == 200) {
                Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                resp.tables = (String) responseMap.get('tables');
                resp.pageCount = (Integer) responseMap.get('page_count');
                resp.jobId = (String) responseMap.get('job_id');
                resp.engine = (String) responseMap.get('engine');
            } else {
                resp.errorMessage = 'HTTP ' + res.getStatusCode() + ': ' + abbreviate(res.getBody(), 240);
            }

            return resp;
        } catch (Exception e) {
            DoclingResponse resp = new DoclingResponse();
            resp.errorMessage = e.getMessage();
            return resp;
        }
    }

    private void updateDocumentStatus(Id docId, String status, String reason) {
        try {
            Spread_Document__c doc = new Spread_Document__c(
                Id = docId,
                Extraction_Status__c = status
            );
            update doc;

            if (reason != null && status == 'Failed') {
                Spread_Exception__c exc = new Spread_Exception__c(
                    Spread_Document__c = docId,
                    Exception_Reason__c = 'Extraction Error: ' + reason,
                    Severity__c = 'Warning'
                );
                insert exc;
            }
        } catch (Exception e) {
            // Silent fail on exception updates
        }
    }

    private ContentVersion getContentVersion(String contentDocumentId) {
        List<ContentVersion> versions = [
            SELECT Id, VersionData, Title, FileType
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId
            AND IsLatest = true
            WITH USER_MODE
            LIMIT 1
        ];
        return versions.isEmpty() ? null : versions[0];
    }

    private String buildMultipartBody(String boundary, String fileName, String fileContentType, Blob fileData) {
        String body = '';
        body += '--' + boundary + '\r\n';
        body += 'Content-Disposition: form-data; name="file"; filename="' + fileName + '"\r\n';
        body += 'Content-Type: ' + fileContentType + '\r\n\r\n';
        body += EncodingUtil.base64Encode(fileData) + '\r\n';
        body += '--' + boundary + '--';
        return body;
    }

    private String getContentType(String fileType) {
        if (String.isBlank(fileType)) return 'application/pdf';
        String normalized = fileType.toUpperCase();
        if (normalized == 'PDF') return 'application/pdf';
        if (normalized == 'JPEG' || normalized == 'JPG') return 'image/jpeg';
        if (normalized == 'PNG') return 'image/png';
        return 'application/octet-stream';
    }

    private String getFileExtension(String fileType) {
        if (fileType == null) return 'pdf';
        if (fileType.equals('JPEG')) return 'jpg';
        return fileType.toLowerCase();
    }

    private String abbreviate(String value, Integer maxLength) {
        if (String.isBlank(value) || maxLength == null || maxLength <= 0 || value.length() <= maxLength) {
            return value;
        }
        return value.substring(0, maxLength) + '...';
    }

    private class DoclingResponse {
        public String tables;
        public Integer pageCount;
        public String jobId;
        public String engine;
        public String errorMessage;
    }
}
