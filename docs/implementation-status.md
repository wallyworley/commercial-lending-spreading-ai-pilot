# Implementation Status — Salesforce-Native Extraction Path

**Updated:** 2026-04-29  
**Status:** Agentforce sandbox flow is working end to end for Salesforce Files upload, Docling extraction, deterministic Apex parsing, analyst review, and certification.

## Current Working Baseline

The current baseline is Salesforce-native and Agentforce-first. nCino integration is intentionally deferred until supported nCino object/API guidance is available.

Working flow:

1. Analyst opens a `Commercial_Loan__c` record.
2. The `commercialSpreadingPilotWorkbench` LWC creates or reuses the loan-scoped `Spread_Pilot_Run__c`.
3. Analyst uploads PDF/JPEG/PNG financial statements using Salesforce Files.
4. `ExtractionQueueable` calls the Render-hosted Docling service through `Spread_Docling_Service_V2`.
5. `SpreadEvidenceService` stores raw extracted text/tables in `Spread_Extraction_Evidence__c`.
6. `ParsingQueueable` runs deterministic Apex parsing.
7. `SpreadEvidenceParserService` maps known labels to normalized spread lines, infers statement periods, and creates draft line/path records.
8. The review tab displays an analyst-style spread grid with periods pivoted into columns.
9. Analysts certify or reject the candidate values while source evidence remains linked.

Important boundary:

- Docling performs document text/table extraction.
- Apex performs current spread parsing and mapping.
- No LLM is currently classifying financial lines.
- Candidate values are draft-only until analyst certification.

## Completed Components

### Document Processing Pipeline

| Component | Status | Notes |
| --- | --- | --- |
| `Spread_Document__c` object | ✓ Complete | Tracks document intake, extraction, and parsing status with fields for borrower, document type, fiscal period, page count, and processing state. |
| `ExtractionQueueable` | ✓ Complete | Executes async extraction via Docling Named Credential; routes failures to "Needs Review"; calls parsing queue on success. |
| `SpreadEvidenceService` | ✓ Complete | Creates `Spread_Extraction_Evidence__c` records; preserves raw docling output (tables, text, page count, engine metadata) as evidence. |
| `DoclingKeepWarmSchedulable` | ✓ Complete | Scheduled action to keep Docling extraction service warm and reduce cold-start latency. |
| Transient extraction retry | ✓ Complete | Retries Render loading/503/chunk termination failures before marking extraction failed. |

### Evidence Staging

| Component | Status | Notes |
| --- | --- | --- |
| `Spread_Extraction_Evidence__c` object | ✓ Complete | Records raw extracted tables, page counts, and engine metadata. One evidence record per document. Evidence is immutable and serves as the audit trail. |
| Evidence creation on extraction success | ✓ Complete | ExtractionQueueable→SpreadEvidenceService→Spread_Extraction_Evidence__c. |

### Parsing and Draft Spread Candidates

| Component | Status | Notes |
| --- | --- | --- |
| `ParsingQueueable` | ✓ Refactored | Invokes `SpreadEvidenceParserService` / `SpreadCandidateParserService` to parse evidence into draft spread candidates. |
| `SpreadEvidenceParserService` | ✓ Complete | Deterministic parser for known extracted labels. Supports multi-period balance-sheet rows and period inference. |
| `SpreadCandidateParserService` | ✓ Complete | Imports parser JSON into `Spread_Line_Item__c` and `Spread_Path_Result__c`, including candidate-level statement type and fiscal period. |
| `SpreadLineMappingSelector` | ✓ Enhanced | Selects active line mappings for normalized spread schema. |

### Pilot Scorecard and Certification

| Component | Status | Notes |
| --- | --- | --- |
| `SpreadScorecardService` | ✓ Enhanced | Calculates exact-match, dollar-weighted accuracy, and exception rates across paths. |
| `SpreadCertificationService` | ✓ Complete | Certification workflow: certify/reject path results with reviewer signature and timestamp. |
| `SpreadManualBaselineService` | ✓ Complete | Allows analysts to set or edit `Manual_Value__c` on a path result with a required reason and audit log entry. |
| `Spreading_Pilot_Analyst` permission set | ✓ Complete | Controls access to Spread Document, Evidence, Line Item, and Scorecard records. |

### Analyst Workbench (LWC)

| Component | Status | Notes |
| --- | --- | --- |
| `commercialSpreadingPilotWorkbench` LWC | ✓ Major Update | Upload, parse, review, certify, and measure pilot results. Supports document status polling, analyst-style spread review, material error reporting, scorecard display, and path comparison. |
| Document upload and polling | ✓ Complete | File upload→Spread_Document creation→async extraction→status polling. |
| Spread review grid | ✓ Complete | Analyst view groups rows by spread line and pivots fiscal periods into columns. Certification and rejection actions remain available. |
| Manual baseline entry | ✓ Complete | Analysts can set or edit manual comparison values from the review grid. A reason is required and the change is logged for auditability. |
| Scorecard display | ✓ Complete | Path comparison table with exact-match, dollar accuracy, time reduction, certification rate, and uncaught material error metrics. |
| Material error reporting | ✓ Complete | Query and display line items with variance above thresholds. |

### Infrastructure and Control

| Component | Status | Notes |
| --- | --- | --- |
| Docling Named Credential | ✓ Complete | Configured for async callout to extraction service. Secured via External Credentials. |
| Error handling and routing | ✓ Complete | Extraction failures→"Failed" status; soft errors→"Needs Review". Re-queue and retry available. Transient Docling failures retry automatically. |
| Test coverage | ✓ Enhanced | ExtractionQueueableTest, ParsingQueueableTest, SpreadScorecardServiceTest, SpreadWorkbenchControllerTest, and SpreadEvidenceParserServiceTest all updated with full scenarios. |

## Current Flow

1. **Analyst uploads document** via LWC workbench → Spread_Document__c created (Extraction_Status = Pending)
2. **ExtractionQueueable fires** → calls Docling service via Named Credential → on success: creates Spread_Extraction_Evidence__c
3. **ParsingQueueable fires** → deterministic Apex parser creates draft `Spread_Line_Item__c` and `Spread_Path_Result__c` records
4. **LWC workbench displays** upload status, parsed period columns, evidence links, and material errors
5. **Analyst reviews and certifies** candidate values → SpreadCertificationService certifies Spread_Path_Result__c records
6. **Scorecard calculation** → SpreadScorecardService evaluates exact-match, dollar accuracy, exceptions per path
7. **Reporting** → scorecard and error reports available in workbench and exportable

## Known Limitations and Next Steps

| Area | Current State | Next Steps |
| --- | --- | --- |
| **Prompt-based parsing** | Current parser is deterministic Apex with custom metadata mappings. | Add Prompt Builder or Agentforce only after the deterministic baseline is stable and test data exposes where flexibility is needed. |
| **Multi-path comparison** | Salesforce native path is implemented. nCino and manual paths are data-only. | Add nCino provider adapter and manual path data import workflow. |
| **Document types** | PDF/JPEG/PNG via Docling. Native text PDFs are working through Docling. | Add more samples for scanned-image OCR, tax returns, statements in thousands, notes, and debt schedules. |
| **nCino integration** | Not yet implemented; waiting for supported nCino object API guidance. | Integrate with nCino spreads after API documentation is available. |
| **Agentforce assistant** | Not yet integrated. | Add Agentforce / Agent Script for guided analysis and exception explanation. |
| **Data Cloud integration** | Not yet implemented. | Optional Phase 2: add Data 360 borrower context grounded via Data Graph API. |
| **Analyst adjustments** | Manual baseline capture is now implemented for comparison scoring. Candidate values can still only be certified or rejected, not overridden into a separate reviewed value. | Add an adjust action that stores analyst-reviewed value separately from extracted candidate value and requires a reason distinct from baseline entry. |

## Testing and Validation

- **Unit tests**: All queueables and services have full test coverage.
- **Synthetic data**: npm run generate:synthetic creates fake borrower documents and pilot results for workflow validation.
- **End-to-end flow**: Document upload → extraction → parsing → review → certification → scorecard calculation tested in WorkbenchControllerTest.
- **Validation data**: Use data/templates/ for corpus, gold-standard, extraction results, and scorecard structure.

## Latest Verified Sandbox Scenario

On 2026-04-29, `statement_3` was uploaded to the Agentforce org and initially hit Render cold-start failures. After transient retry hardening, extraction and parsing completed successfully.

Verified output:

- `Extraction_Status__c`: Complete
- `Parsing_Status__c`: Complete
- `Page_Count__c`: 1
- Periods inferred: `12/31/2025`, `12/31/2024`
- Lines parsed: Cash, Current Assets, Current Liabilities
- Amounts stored in `Spread_Path_Result__c.Candidate_Value__c`
- Evidence retained in `Spread_Extraction_Evidence__c.Raw_Text__c`

## Deployment Notes

1. Deploy Apex classes, LWC components, and metadata in order: object definitions → services → queueables → LWC.
2. Configure Docling Named Credential with endpoint and API credentials before extraction.
3. Deploy Spreading_Pilot_Analyst permission set to analyst users.
4. Enable flow-based certification routing in Flow Orchestration if needed.
5. For production, implement Seven-Year Evidence Retention (SER) with archive/offload path for Spread_Extraction_Evidence__c.

## Decision Points for Stakeholders

- ✓ **Salesforce-native path is buildable and tested** as a sandbox POC.
- ✓ **Evidence staging preserves source traceability** via Spread_Extraction_Evidence__c.
- ✓ **Analyst certification is mandatory** before any AI value affects credit data.
- ✓ **Analyst review UX now resembles a spread** with period columns and evidence links.
- ⚠ **nCino integration requires supported API documentation** not yet available.
- ⚠ **Production readiness requires** full pilot gate evaluation (98% exact match, 99.5% dollar accuracy, zero uncaught material errors, 30% time reduction).
