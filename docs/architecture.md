# Architecture

## Principle

Salesforce and nCino remain the workflow and audit system. AI systems may generate draft spread candidates, but final credit data is created only through supported Salesforce/nCino paths and human certification.

Current architecture note, 2026-04-29:

- The active build is Salesforce-native in the `agentforce` org.
- The current loan context is a fake `Commercial_Loan__c` object, not nCino.
- Document extraction is performed by the Render-hosted Docling service.
- Current line parsing is deterministic Apex, not an LLM.
- Agentforce/Prompt Builder remains a planned assistant or flexible-parsing layer, not the current parser.

## Pilot Path 1: nCino Automated Spreading

nCino is the benchmark path, but it is deferred in the current build. When resumed, it should use only nCino-supported workflows:

- Documents originate in nCino Document Manager where possible.
- Automated Spreading extracts and maps values from supported document types.
- Results are reviewed line-by-line before promotion into nCino Spreads.
- Final values remain governed by nCino Spreads and bank credit policy.

No direct write into final spread data should be introduced outside supported nCino configuration or vendor-approved APIs.

## Pilot Path 2: Salesforce-Native Extraction and Staging

The Salesforce-native path stages extracted values for review before any final credit use.

### Current Implementation

As of April 29, 2026, the Salesforce-native path is implemented and tested:

1. **Loan cockpit**: Analyst opens a `Commercial_Loan__c` record.
2. **Document intake**: Analyst uploads PDFs/JPEGs/PNGs via the pilot workbench LWC component.
3. **Spread_Document__c record** created with metadata and linked Salesforce File document ID.
4. **ExtractionQueueable** executes async extraction via Docling Named Credential.
5. **Transient retry** handles Render loading/503/chunk termination failures before final failure.
6. **Spread_Extraction_Evidence__c** records capture raw extracted text/tables, page references, and engine metadata.
7. **ParsingQueueable** invokes deterministic Apex parsing into draft spread line candidates.
8. **Spread_Line_Item__c** records store normalized line, statement type, fiscal period, and evidence reference.
9. **Spread_Path_Result__c** records store candidate amount, raw label/value, path key, and certification state.
10. **Analyst review** through LWC workbench: periods pivot into columns, evidence links are visible, material lines can be certified or rejected.
11. **SpreadManualBaselineService** lets analysts set or edit the manual comparison baseline with a required reason and audit log.
12. **SpreadCertificationService** records certification status and reviewer signature.
13. **SpreadScorecardService** calculates exact-match rate, dollar-weighted accuracy, exceptions, and time reduction.
14. **Optional nCino reconciliation** after Salesforce certification, pending future nCino adapter.

### Key Components

- `Spread_Document__c`: Document tracking (extraction status, parsing status, page count, document type)
- `Spread_Extraction_Evidence__c`: Raw extracted evidence (tables, text, page references, immutable audit trail)
- `Spread_Line_Item__c`: Canonical spread row by borrower/document/period/normalized line.
- `Spread_Path_Result__c`: Candidate amount, raw label/value, comparison path, exception state, and certification state.
- `Spread_Path_Result__c.Manual_Value__c`: Analyst-maintained comparison baseline used for scorecard and variance evaluation.
- `Commercial_Loan__c`: Sandbox loan cockpit object for avoiding nCino dependency during prototype work.
- `commercialSpreadingPilotWorkbench` LWC: Analyst UI for upload, review, certify, scorecard, and error reporting.

### Outbound Security

Outbound calls from Salesforce use Named Credentials and External Credentials for Docling service. No legacy patterns.

### Evidence and Traceability

Every extracted value is traceable to source evidence:

- `Spread_Extraction_Evidence__c` preserves raw Docling output.
- `Spread_Line_Item__c` stores line and period context.
- `Spread_Path_Result__c` stores candidate value and links to primary evidence.
- Manual baseline updates require a reason and write an audit log event before affecting scorecards.
- Certification records include reviewer signature and timestamp.
- Seven-year retention policy for evidence remains a production design item.

## Pilot Path 3: Manual nCino Control Case

The control path uses nCino Document Manager and Spreads without automated extraction. It establishes:

- Manual analyst cycle time.
- Baseline error rate.
- Current exception handling.
- Re-keying effort.
- Credit memo downstream impact.

This path is not a fallback afterthought. It is the measurement baseline that determines whether any AI path has earned production consideration.

## Draft Staging Boundary

The staging interface must preserve every value as evidence, not as final credit truth.

Required staging fields are defined in `schemas/spread-staging-record.schema.json` and reflected in `data/templates/extraction-results.csv`.

## Data Flow

```text
Borrower document
  -> Commercial Loan record page workbench
  -> Salesforce Files upload
  -> Spread_Document__c intake record
  -> Docling extraction through Named Credential
  -> Spread_Extraction_Evidence__c evidence record
  -> deterministic Apex parser
  -> Spread_Line_Item__c + Spread_Path_Result__c draft staging
  -> analyst spread review with evidence links
  -> human certification or rejection
  -> future final nCino/Salesforce credit workflow, only after certification
  -> Pilot scorecard and model-risk evidence package
```

## Implementation Reference

### Salesforce Objects

| Object | Purpose | Notes |
| --- | --- | --- |
| Spread_Document__c | Document tracking and extraction status | Fields: borrower, document type, fiscal period, page count, extraction status, parsing status |
| Spread_Extraction_Evidence__c | Raw extracted evidence (tables, text) | Immutable audit trail; preserves docling engine metadata |
| Spread_Line_Item__c | Draft spread candidates | Links to evidence via line mapping; draft status until certified |
| Spread_Path_Result__c | Path comparison results | One result per path per line item (manual, nCino, Salesforce native) |
| Commercial_Loan__c | Sandbox loan context | Fake loan object for current Agentforce prototype. Avoids nCino dependency. |
| Spreading_Pilot_Analyst permission set | Access control | Grants read/write to pilot objects; restricts to analyst role |

### Key Apex Services

| Class | Purpose |
| --- | --- |
| ExtractionQueueable | Async extraction via Docling Named Credential |
| SpreadEvidenceService | Creates Spread_Extraction_Evidence__c records with raw docling output |
| ParsingQueueable | Async parsing of evidence into draft candidates |
| SpreadEvidenceParserService | Deterministic evidence parser with period inference and line mapping |
| SpreadCandidateParserService | Imports parser JSON into spread line items and path results |
| SpreadManualBaselineService | Writes analyst-entered manual baseline values with required reason and audit log |
| SpreadScorecardService | Calculates exact-match, dollar accuracy, exceptions |
| SpreadCertificationService | Certification workflow and reviewer signature |
| SpreadLineMappingSelector | Retrieves active line mappings for spread schema |

### LWC Components

| Component | Purpose |
| --- | --- |
| commercialSpreadingPilotWorkbench | Main analyst UI (upload, review, certify, scorecard, errors) |

## Production Blockers

Do not proceed to production if any of these remain unresolved:

- Unsupported nCino object writes are required.
- Source evidence cannot be traced at line-item level.
- Material fields can bypass human certification.
- Access to financial documents is broader than the originating loan workflow requires.
- Vendor security, SOC, subprocessor, or implementation documentation is unavailable for review.
- Model-risk stakeholders reject the sample design or accuracy evidence.
- Docling service credentials and endpoint are not secured via External Credentials and Named Credential.
- Seven-year evidence retention and archive/offload path is not implemented.
