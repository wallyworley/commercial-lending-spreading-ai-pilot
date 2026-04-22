# Salesforce Agentforce Architecture Plan

Research date: April 20, 2026

This plan merges the original architecture, the external review notes, and the updated recommendation for path modeling. It assumes Agentforce Employee Agent / Agent Script is licensed, initial documents live in Salesforce Files, nCino integration is desired but API documentation is not yet available, the first Salesforce build is a sandbox demo, and reports must be available as both a Salesforce page and generated PDF.

Resolved implementation decisions:

- Initial thresholds should start with the most credit-critical metrics, then expand to the full policy set.
- Threshold activation requires dual approval.
- Scorecards lock on explicit pilot-run close, with draft/stale recalculation available before close.
- Reports should support both Salesforce-native generation and an external rendering option.
- Audit logs, reports, files, and agent records must support seven-year retention, with an offload/archive path.
- A React POC is desired eventually, after the LWC baseline is stable.

## Recommendation

Do not move the whole project into an Agent Script agent.

Use a Salesforce-native hybrid architecture:

- **Lightning Web Components for Phase 1 sandbox demo and production baseline.** LWC is GA, App Builder-compatible, supports Salesforce Files well, and is the lowest-risk choice for a bank-facing demo.
- **React on Salesforce Multi-Framework as Phase 2.** React is promising for complex grids, richer PDF review, and reusable frontend libraries, but Salesforce Multi-Framework is still beta and not production-deployable during beta.
- **Apex services for deterministic logic.** Scoring, certification, threshold resolution, exception creation, report data, audit writes, and nCino adapter contracts belong in Apex.
- **Agentforce / Agent Script as an assistant layer.** The agent explains, summarizes, drafts review questions, and invokes controlled Apex or Flow actions. It does not certify, approve, risk-rate, or write final spread values.
- **Prompt Builder / Agentforce for parsing extracted evidence, not OCR.** OCR and text extraction belong in document extraction providers. Prompt templates and Agentforce actions receive already-extracted text/tables and return draft spread candidates as validated JSON.
- **Flow for review routing and approvals.** Use Flow where credit admins need visible workflow ownership.
- **Provider adapters for documents and extraction evidence.** Start with Salesforce Files; add nCino provider adapters only after supported nCino object/API guidance is available.

## Validated Path Modeling Decision

The cleanest architecture combines both reviewed ideas:

- `Spread_Path__mdt` defines valid path types.
- `Spread_Path_Result__c` stores the actual result for each path and each normalized spread line.

This is valid and recommended.

Why:

- Custom metadata records are metadata, not business data, and Salesforce positions custom metadata as an app configuration mechanism that can be deployed and packaged.
- Path definitions are stable configuration: Manual Control, nCino Automated Spreading, Salesforce Native Staging, future OCR provider, future nCino version, and so on.
- Path results are business data: one measured value, confidence, exception status, and review status for a specific pilot run and spread line.
- A child `Spread_Path_Result__c` model avoids three full `Spread_Line_Item__c` records per line while avoiding a wide object like `nCino_Auto_Value__c`, `Salesforce_Native_Value__c`, `Manual_Value__c` that would require schema changes for every new path.

Use this shape:

```text
Spread_Line_Item__c
  -> one normalized borrower/document/period/spread line

Spread_Path_Result__c
  -> one result for one path against that line
  -> lookup/reference to Spread_Path__mdt by DeveloperName or text key
```

## Target Architecture

```text
Analyst uploads PDF/JPEG via LWC file upload component
  -> ContentDocument + ContentDocumentLink (Salesforce Files)
  -> Spread_Document__c record created, Extraction_Status__c = Pending
  -> Queueable Apex (SpreadDocumentService.enqueueExtraction)
       -> Named Credential callout to extraction provider
       -> Native PDF extraction for text-layer PDFs, Docling/OCR for scanned files,
          or Salesforce Document AI / supported nCino extraction provider where available
       -> Extraction provider returns raw evidence: page text, tables, page references, optional coordinates
  -> Spread_Extraction_Evidence__c records created
  -> Apex invokes Prompt Builder / Agentforce parsing action with:
       extracted evidence + bank spread schema + active line mapping configuration
  -> Prompt returns validated JSON draft spread candidates
  -> Spread_Line_Item__c staging records created (draft, not certified)
  -> Spread_Path_Result__c per comparison path
  -> Spreading_Policy__c / Spreading_Threshold__c gate evaluation
  -> Pilot_Scorecard_Result__c
  -> LWC analyst workbench: review, certify, flag exceptions
  -> Flow review/certification routing
  -> Agentforce assistant for guided analysis and exception explanation
  -> optional nCino spread adapter, once supported documentation is available
  -> ⚑ optional Data 360 borrower context layer (Phase 2+), grounded via Data Graph API
```

## Data Model

Use custom objects unless nCino provides supported guidance for reading or writing existing nCino objects. Do not write to final nCino spread objects without vendor-supported documentation and bank approval.

### `Spread_Pilot_Run__c`

One pilot execution.

Key fields:

- `Name`
- `Status__c`: Draft, Running, Review, Complete, Blocked
- `Decision__c`: Proceed, Retest, Do Not Proceed
- `Portfolio__c`: C&I, CRE, SBA, ABL
- `Started_At__c`
- `Completed_At__c`
- `Notes__c`

### `Spread_Document__c`

One source document in the pilot corpus.

Key fields:

- `Pilot_Run__c`
- `Borrower__c`: Account lookup. Use Account consistently; nCino commonly centers borrower context on Account.
- `Loan_Or_Opportunity__c`: Opportunity lookup or text reference for sandbox demo.
- `Document_Type__c`
- `Statement_Type__c`
- `Fiscal_Period__c`
- `Scenario_Type__c`
- `ContentDocumentId__c`: Text(18). Do not model this as a lookup; Salesforce does not support custom lookup fields to `ContentDocument`. Link the file with `ContentDocumentLink`.
- `Source_System__c`: Salesforce Files, nCino, External ECM, Synthetic Demo
- `Contains_Confidential_Data__c`
- `Extraction_Status__c`: Pending, In Progress, Complete, Failed, Needs Review
- `Extracted_At__c`
- `Parsing_Status__c`: Not Started, Pending, In Progress, Complete, Failed, Needs Review
- `Parsed_At__c`
- `Page_Count__c`

### `Spread_Extraction_Evidence__c`

One extracted evidence block from a document. This separates OCR/text extraction from financial spreading interpretation.

Why separate:

- OCR/text extraction is not the same control as line-item mapping.
- Analysts and model-risk reviewers need to see what text or table block supported each draft value.
- Provider changes should not force a change in spread candidate storage.
- Prompt templates should receive bounded evidence blocks rather than raw Salesforce File binaries.

Key fields:

- `Spread_Document__c`
- `Pilot_Run__c`
- `Provider__c`: Native PDF, Docling, Salesforce Document AI, FSC Intelligent Document Reader, nCino, Manual
- `Extraction_Engine__c`: native_pdf, docling, document_ai, idr, ncino, manual
- `Source_Page__c`
- `Source_Coordinates__c`: optional JSON/text for page coordinate evidence
- `Evidence_Type__c`: Text, Table, Key Value, Image OCR, Metadata
- `Raw_Text__c`: Long Text Area, extracted page/table text
- `Raw_Table_Markdown__c`: Long Text Area, table representation where available
- `Extraction_Confidence__c`
- `Extraction_Status__c`: Success, Partial, Failed, Needs Review
- `Source_Hash__c`: hash of the evidence block for audit/replay comparison

### `Spread_Line_Item__c`

One normalized spread line for a borrower/document/period. This is the canonical comparison row.

Key fields:

- `Pilot_Run__c`
- `Spread_Document__c`
- `Normalized_Line__c`
- `Statement_Type__c`
- `Fiscal_Period__c`
- `Source_Page__c`
- `Source_Coordinates__c`
- `Primary_Evidence__c`: lookup to `Spread_Extraction_Evidence__c`
- `Material__c`
- `Include_In_Report__c`
- `Review_Note__c`: Long Text Area
- `Final_Spread_Reference__c`: Text reference until nCino integration is formalized

Do not store path-specific candidate values here. Those belong in `Spread_Path_Result__c`.

### `Spread_Path__mdt`

Deployable configuration for valid comparison paths.

Fields:

- `DeveloperName`: e.g. `manual_ncino_control`, `ncino_automated_spreading`, `salesforce_native_staging`
- `MasterLabel`
- `Display_Order__c`
- `Is_Baseline__c`
- `Requires_Time_Reduction__c`
- `Provider_Type__c`: Manual, Salesforce, nCino, External
- `Active__c`
- `Description__c`

Default records:

- `manual_ncino_control`
- `ncino_automated_spreading`
- `salesforce_native_staging`

### `Spread_Line_Mapping__mdt`

Deployable configuration that tells the parser which financial statement labels can map to which normalized spread lines.

Why custom metadata:

- Line mappings are bank configuration, not transaction data.
- Prompt templates and Apex validators need the same allowed line names.
- New synonyms can be promoted through change control without code changes.

Fields:

- `DeveloperName`: e.g. `current_liabilities_accounts_payable`
- `Normalized_Line__c`: e.g. `current_liabilities`
- `Statement_Type__c`: Income Statement, Balance Sheet, Cash Flow, Tax Return, Covenant Schedule
- `Accepted_Label__c`: e.g. "Accounts Payable and Accrued Expenses"
- `Priority__c`
- `Requires_Reviewer__c`
- `Material_Default__c`
- `Active__c`
- `Prompt_Guidance__c`: short instruction used as grounding context for ambiguous labels

### `Spread_Path_Result__c`

One measured result for one path against one normalized spread line.

Key fields:

- `Spread_Line_Item__c`
- `Pilot_Run__c`
- `Spread_Document__c`
- `Path_Key__c`: Text matching `Spread_Path__mdt.DeveloperName`, or metadata relationship if supported in the target design.
- `Manual_Value__c`: Number(18,2), baseline value for scoring comparison
- `Candidate_Value__c`: Number(18,2)
- `Raw_Label__c`: source label from extracted evidence, e.g. "Current Liabilities"
- `Raw_Value__c`: source value string, e.g. "$1,090,000"
- `Primary_Evidence__c`: lookup to `Spread_Extraction_Evidence__c`
- `Variance_Amount__c`: Formula, null-safe `Manual_Value__c - Candidate_Value__c`
- `Variance_Pct__c`: Formula, null-safe percentage variance
- `Confidence__c`
- `Exception_Flag__c`
- `Exception_Reason__c`
- `Exception_Status__c`: None, Open, Pending Review, Approved, Denied, Escalated
- `Certification_Status__c`: Uncertified, Certified, Rejected, Exception Pending, Exception Approved
- `Certified_By__c`: User lookup, set only by Apex
- `Certified_At__c`: DateTime, set only by Apex
- `Error_Type__c`: extraction, mapping, period, document, calculation, reviewer
- `Candidate_Minutes__c`
- `Baseline_Minutes__c`

Certification fields must be locked from direct edit via FLS. Analysts certify through Apex service methods invoked by the workbench.

### `Spread_Exception__c`

Dedicated exception lifecycle record.

Why separate:

- Exception routing should not be conflated with spread values.
- It gives reviewers a record with tasks, ownership, status, activity history, and sharing.
- Flow can route exceptions without mutating line values directly.

Key fields:

- `Spread_Path_Result__c`
- `Spread_Line_Item__c`
- `Pilot_Run__c`
- `Status__c`: Open, Pending Review, Approved, Denied, Escalated
- `Severity__c`: Warning, Policy Exception, Hard Stop
- `Raised_By__c`
- `Raised_At__c`
- `Assigned_To__c` or queue ownership
- `Resolution__c`: Long Text Area
- `Resolved_By__c`
- `Resolved_At__c`
- `Escalated_To__c`
- `Credit_Impact__c`: Long Text Area; agent-drafted only from Apex-grounded facts

### `Pilot_Scorecard_Result__c`

Aggregated pass/fail metrics for a pilot run by path.

Key fields:

- `Pilot_Run__c`
- `Path_Key__c`
- `Passed__c`
- `Exact_Match_Rate__c`
- `Dollar_Weighted_Accuracy__c`
- `Time_Reduction__c`
- `Baseline_Time__c`
- `Actual_Time__c`
- `Certification_Rate__c`
- `Uncaught_Material_Errors__c`
- `Line_Item_Count__c`
- `Certified_Count__c`
- `Exception_Count__c`
- `Policy_Version__c`: lookup to `Spreading_Policy__c`
- `Recommendation__c`
- `Calculated_By__c`
- `Calculated_At__c`
- `Status__c`: Current, Stale, Superseded, Failed

Scorecard records should be created or locked by explicit user action, not by an expensive trigger after every row edit.

### `Spreading_Policy__c`

Versioned, bank-specific threshold policy set.

Use custom objects, not custom metadata, for bank threshold values because these values need business ownership, approval, field history/audit, effective dating, and user-editable lifecycle.

Key fields:

- `Name`
- `Version__c`
- `Status__c`: Draft, Pending Approval, Active, Retired
- `Portfolio__c`: C&I, CRE, SBA, ABL
- `Industry__c`
- `Borrower_Size__c`
- `Effective_Start_Date__c`
- `Effective_End_Date__c`
- `Approved_By__c`
- `Approved_At__c`
- `Secondary_Approved_By__c`
- `Secondary_Approved_At__c`
- `Change_Rationale__c`: Long Text Area
- `Description__c`

### `Spreading_Threshold__c`

One threshold rule within a policy.

Key fields:

- `Spreading_Policy__c`
- `Metric__c`: DSCR, FCCR, Current Ratio, Debt / EBITDA, Debt-to-Worth, Working Capital, AR Days, Inventory Days, Exact Match Rate, Dollar Accuracy, Certification Rate, Uncaught Material Errors
- `Operator__c`: >=, >, <=, <, Between
- `Minimum_Value__c`
- `Maximum_Value__c`
- `Severity_When_Failed__c`: Warning, Policy Exception, Hard Stop
- `Applies_To_Material_Line__c`
- `Requires_Exception_Approval__c`
- `Narrative_Guidance__c`: Long Text Area

Validation:

- If `Operator__c = Between`, both min and max are required.
- For single-bound operators, exactly one relevant threshold value should be required.
- Apex scoring must enforce the same rules so API-loaded data cannot bypass validation.

### `Spreading_Definition__mdt`

Stable, packageable definitions:

- Ratio labels
- Formula keys
- Normalized spread line definitions
- Default material line categories
- Supported source document types
- Default scenario classifications

Use custom metadata for definitions, not bank-specific threshold values.

### `Spread_Audit_Log__c`

Append-only audit record. Standard field history tracking is not sufficient for credit/model-risk evidence because of retention, field-count, and business-context limitations.

Capture:

- Certification events
- Exception lifecycle events
- Policy activation and threshold changes
- Scorecard calculation events
- Pilot run status transitions
- Agent-generated narrative events, including selected fact IDs used

Key fields:

- `Event_Type__c`: Certification, Exception Raised, Exception Resolved, Policy Activated, Scorecard Calculated, Run Status Change, Agent Narrative Generated
- `Record_Id__c`: Text(18)
- `Object_Name__c`
- `User__c`
- `Timestamp__c`
- `Previous_Value__c`
- `New_Value__c`
- `Notes__c`: Long Text Area

No user profile should have delete access. Writes should happen only through Apex service methods.

Retention:

- Keep seven years of audit evidence available for regulatory, model-risk, and internal audit review.
- Keep current-period audit records in Salesforce for operational access.
- Design an archive/offload pattern for older records using a bank-approved archive, data lake, warehouse, or external object pattern.
- Store archive references back on the pilot run when records are offloaded.
- Do not delete source audit records until archive validation, retention approval, and legal-hold checks are complete.

## Workbench

Build the Phase 1 analyst workbench as LWC. Name the primary component `commercialSpreadingPilotWorkbench`.

Reasons:

- LWC is GA and supported in Lightning Experience, Salesforce Mobile App, Lightning App Builder, Lightning Console Apps, custom tabs, utility bars, Flows, and packaging.
- It supports Salesforce Files and record context cleanly.
- It supports App Builder placement from the start.
- It reduces beta-runtime risk for a bank-facing demo.

Tabs:

1. **Overview**
   - Pilot run status
   - Pass/fail by path
   - Recommendation
   - Open blockers
   - Scorecard stale/current state

2. **Document Corpus**
   - LWC file upload component (`lightning-file-upload`) targeting the pilot run record. Accepts PDF, JPEG, PNG. Triggers `SpreadDocumentService.onUpload` on `uploadfinished` event, which creates the `Spread_Document__c` record and enqueues extraction.
   - Document list: borrower, loan, document type, fiscal period, scenario, document store, nCino spreading mode
   - Extraction status badge (Pending / In Progress / Complete / Failed / Needs Review) with extracted timestamp
   - Salesforce File preview link via `NavigationMixin` to the ContentDocument record page
   - Retry extraction button for Failed documents (invokes Queueable re-enqueue via Apex)
   - Read-only when pilot run status is Running or Blocked

3. **Spread Review**
   - Grid grouped by `Spread_Line_Item__c`
   - Child path results shown as comparison columns/cards per line
   - Manual value, candidate value, variance amount, variance percent, confidence, exception status, certification status
   - Document preview pane beside the grid, using `ContentDocumentId__c` and Salesforce File preview patterns
   - Filters for path, borrower, document, material flag, error type, exception status, certification status
   - Server-side pagination from day one
   - Certification confirmation dialog showing the values being certified
   - Bulk certification with explicit acknowledgment and row count
   - Read-only mode when pilot status is Running or Blocked

4. **Material Errors**
   - Uncaught material errors
   - Errors that would change DSCR, leverage, liquidity, covenant, or risk-rating conclusions
   - Link each error to source document and path result

5. **Policy Thresholds**
   - Active policy set
   - Threshold table by portfolio, industry, borrower size, and metric
   - Draft/activate workflow
   - Dual approval status
   - Preview how thresholds affect current pilot results

6. **Report**
   - Deterministic pass/fail report
   - Explicit fact selection step using `Include_In_Report__c` or report checklist records
   - Agent-generated narrative only from selected certified facts
   - HTML page and generated PDF attachment

## Agentforce / Agent Script Role

Create an Agentforce Employee Agent subagent for commercial spreading review.

Allowed:

- Parse extracted document evidence into draft spread candidates when invoked by controlled Apex/Flow actions.
- Explain why a spread line is material.
- Summarize failed gates.
- Identify which errors affect repayment capacity.
- Draft review questions for selected line items.
- Draft credit memo exception narrative based on selected certified facts.
- Invoke Apex read actions for pilot summary, material errors, and selected facts.
- Invoke Flow actions that route exceptions, with user confirmation.

Not allowed:

- Perform OCR directly from raw Salesforce File binaries.
- Treat OCR or extracted text as final credit truth.
- Certify a spread line or path result.
- Change final spread values.
- Decide credit approval.
- Decide risk rating.
- Override policy thresholds.
- Write into final nCino spread objects.

⚑ Tool count discipline: The eight actions defined below maintain intentional headroom below the 20–25 tool threshold at which LLM context accuracy measurably degrades. Future action additions should be reviewed against this limit before registration.

## Agent Actions

Expose Apex `@InvocableMethod` or Apex REST actions to Agentforce.

⚑ Each action must be registered via the Action Definition process before it is visible to the agent. Steps: create Action Definition, define input/output variables, write a plain-English `description` on both the action and each variable, register in Agent Builder, test via Agent Preview, enable. The `description` on `@InvocableMethod` and each `@InvocableVariable` is what the LLM reads to decide when and how to call the action — missing or vague descriptions cause the agent to skip or misuse actions. Input list parameters must be typed as `List<T>` (Agentforce passes a single-element list per invocation).

⚑ Each `@InvocableMethod` action class must declare `with sharing`. By default, `@InvocableMethod` runs in system context and ignores FLS and sharing rules. `RouteExceptionForReview` in particular writes records and must enforce sharing so analysts can only route exceptions they have access to.

Recommended actions:

- `ParseExtractedFinancialEvidence`
  - Input: `Spread_Document__c` ID or up to 20 `Spread_Extraction_Evidence__c` IDs, target statement type, fiscal period, active mapping version
  - Output: validated draft candidate JSON with normalized line, raw label, raw value, normalized value, source evidence ID, page, confidence, and exception reason
  - Constraints: no direct final-spread writes; Apex validates JSON before creating `Spread_Line_Item__c` and `Spread_Path_Result__c`

- `GetPilotRunSummary`
  - Input: pilot run ID
  - Output: status, scorecards, blockers, recommendation, scorecard freshness

- `GetMaterialErrors`
  - Input: pilot run ID, optional path key
  - Output: uncaught material errors with document references and threshold context

- `GetSelectedReportFacts`
  - Input: pilot run ID
  - Output: only certified facts explicitly selected for report inclusion

- `ExplainCreditImpact`
  - Input: up to 20 `Spread_Path_Result__c` IDs
  - Output: structured facts tagged `source: apex`, plus a prompt instruction to explain only from those facts

- `DraftReviewQuestions`
  - Input: up to 20 path result IDs, or material exception-flagged filter
  - Output: questions for analyst review

- `RouteExceptionForReview`
  - Input: path result ID and reviewer queue
  - Output: Flow/task result
  - Requires explicit user confirmation

- `RefreshPilotContext`
  - Input: pilot run ID
  - Output: freshly queried summary values

## Agent Configuration Requirements

- Embed the agent in the workbench for Phase 1 so analysts stay in context.
- Restrict access to authenticated Salesforce users with the spreading analyst permission set.
- ⚑ The Spreading Analyst permission set XML must include an `<agentAccesses>` element referencing this agent's API name. Without it, users holding the permission set will not see the agent even if it is active and deployed. Assign the `CopilotSalesforceUser` permission set to analysts in addition to the domain permission set — agent visibility requires both.
- Configure Einstein Trust Layer/data masking policies for borrower names, financial values, DSCR, loan balances, tax identifiers, and other sensitive fields.
- ⚑ Distinguish two masking layers: Einstein Trust Layer enforces Zero Data Retention and PII masking at the LLM call boundary. Dynamic Data Masking (DDM) in the Salesforce org permission model masks sensitive fields at display time for role-based access. Both must be configured independently — Trust Layer does not replace org-level field masking for analysts viewing the workbench.
- Confirm no pilot data is retained for model training.
- Define `AgentConversation` access: analysts see only their sessions, model-risk reviewers get review access, admins get full audit access.
- Agent instructions must require a fresh Apex call for state-affecting questions such as remaining uncertified count, current scorecard result, or latest exception status.

## Apex Services

⚑ Every service class must declare a sharing keyword. Omitting it is a security anti-pattern per vault rules. Recommended declarations are noted per service below.

⚑ SOQL queries should not be embedded inline across multiple service classes. Extract queries into a Selector layer (`SpreadLineItemSelector`, `SpreadPathResultSelector`, `SpreadPolicySelector`, etc.) with `inherited sharing` and `WITH USER_MODE`. Selectors are `virtual` so tests can inject mock subclasses. This keeps service methods at a consistent orchestration abstraction level (no raw SOQL mixed into business logic) and is the vault-recommended pattern for financial systems with complex multi-object queries.

⚑ All `@AuraEnabled` Apex methods backing the workbench LWC must use `WITH USER_MODE` in their SOQL (or `Database.query` with `AccessLevel.USER_MODE`). By default, `@AuraEnabled` methods run in system context — FLS is not automatically enforced, and sensitive fields such as DSCR values and borrower financials will be returned to the browser regardless of analyst permissions. `WITH USER_MODE` enforces both FLS and sharing in a single clause.

⚑ `SpreadCertificationService`, `SpreadScorecardService`, and `SpreadArchiveService` each touch multiple objects in a single transaction. Use a Unit of Work pattern (`UnitOfWork.registerNew/registerDirty/commitWork`) with a savepoint in `commitWork()` rather than ad-hoc `Database.setSavepoint()` calls scattered across methods. This makes rollback consistent and testable.

Required service classes:

- `SpreadScorecardService` — ⚑ `with sharing`
  - Calculates path results and writes `Pilot_Scorecard_Result__c`.
  - Resolves active policy and stores policy version.
  - Marks scorecards stale when certifications or exceptions change.
  - Supports draft recalculation while the run is in Review.
  - Locks final scorecard results when the pilot run is closed.
  - ⚑ Extract the pass/fail gate evaluation logic (exact match rate, dollar accuracy, certification rate, uncaught material error checks) into a `SpreadScorecardRules` domain class. The service orchestrates writes; the domain class makes testable boolean decisions. Vault Domain Class pattern applies here.

- `SpreadCertificationService` — ⚑ `without sharing` for certification field writes and audit writes; document the justification inline per vault security rules (analyst shares do not determine whether certifications are recorded)
  - Certifies, rejects, or reopens path results.
  - Sets certification fields in system mode.
  - Writes audit events.
  - Creates or updates exception records when needed.
  - ⚑ Use Unit of Work to register path result update, audit record insert, and exception record upsert as a single `commitWork()` call with rollback.

- `SpreadingPolicyService` — ⚑ `with sharing`
  - Resolves active policy by portfolio, industry, borrower size, and effective date.
  - Chooses the most specific policy where multiple policies match.
  - Validates threshold configuration.
  - Requires dual approval before policy activation.
  - ⚑ Extract specificity resolution (the logic that ranks overlapping policies) into a `SpreadPolicyRules` domain class. The ranking algorithm is business logic that should be independently testable without DML.

- `SpreadDocumentService` — ⚑ `with sharing`
  - Creates `Spread_Document__c` and `ContentDocumentLink` records on file upload.
  - Sets `Extraction_Status__c = Pending` and enqueues extraction via `SpreadProviderService`.
  - Updates extraction status and page count when results are received.
  - Tracks `Document_Store__c` (salesforce_files vs. ncino_document_manager) and `Source_System__c`.

- `SpreadEvidenceService` — ⚑ `with sharing`
  - Receives raw evidence from extraction providers.
  - Creates `Spread_Extraction_Evidence__c` records for text, tables, key-value blocks, OCR output, and provider metadata.
  - Stores source page, coordinates, extraction confidence, and source hash.
  - Marks the source document `Extraction_Status__c = Complete`, `Partial`, `Failed`, or `Needs Review`.
  - Does not create spread candidate values.

- `SpreadCandidateParserService` — ⚑ `with sharing`
  - Invokes Prompt Builder / Agentforce parsing against bounded evidence blocks.
  - Grounds the prompt with active spread line mapping configuration and bank-specific threshold context where needed.
  - Requires structured JSON output and validates it against the spread staging schema.
  - Creates draft `Spread_Line_Item__c` and `Spread_Path_Result__c` records only after JSON validation passes.
  - Routes ambiguous, missing, duplicate, unmapped, low-confidence, or nonnumeric values to `Spread_Exception__c`.
  - Does not write final nCino spread objects.

- `SpreadProviderService` — ⚑ `with sharing` on the interface; individual provider implementations may vary
  - Interface/facade for document extraction providers.
  - ⚑ Use Strategy pattern: `ISpreadProvider` interface with `DoclingProvider` as the Phase 1 concrete implementation. `nCinoProvider` is a future stub. Factory or constructor injection selects the active provider by `Document_Store__c` value on the `Spread_Document__c`. This makes provider substitution testable without callouts.
  - `ISpreadProvider` contract: `requestExtraction(documentId)`, `getExtractionStatus(jobId)`, `importExtractionEvidence(jobId)`.
  - `DoclingProvider`: issues an async HTTP callout via Named Credential to the Docling microservice endpoint. Must execute inside Queueable Apex — never inside a DML transaction. Returns a job ID stored on `Spread_Document__c` for status polling.
  - Docling microservice (Heroku or bank-hosted Python service, MIT license): receives the ContentVersion body and returns extracted text/table evidence. It does not perform final financial spreading interpretation.
  - ⚑ Salesforce Files callout from Queueable Apex: retrieve the `ContentVersion.VersionData` blob via `[SELECT VersionData FROM ContentVersion WHERE Id = :versionId]`, then pass the blob bytes to the Docling service as multipart form-data. Do not attempt to pass a ContentDocument URL — external services cannot authenticate to Salesforce Files endpoints.
  - ⚑ Prompt-based financial parsing should run in Salesforce through Prompt Builder / Agentforce actions after extraction evidence is stored. Pass extracted evidence, source references, and the target schema as structured inputs. Output must be validated JSON before writing draft records — reject and route to exception if the JSON does not conform to the spread staging schema.
  - ⚑ IDR (Salesforce Intelligent Document Reader) evaluation result: not viable for this use case. IDR wraps AWS Textract and has a 5-page cap per extraction job, requires a separate add-on license plus an AWS account, and uses template-bound field mapping that cannot handle arbitrary CPA-format financial statement layouts. Documented for traceability — do not reopen without a fundamental change in IDR capabilities.

- `SpreadReportService` — ⚑ `with sharing`
  - Builds deterministic report data and generates/attaches PDF output.
  - Supports Salesforce-native rendering first and an external rendering adapter where needed.

- `SpreadArchiveService` — ⚑ `without sharing`; archive operations must succeed regardless of analyst sharing context; document justification inline
  - Offloads seven-year retention artifacts to a bank-approved archive when appropriate.
  - Writes archive references back to `Spread_Pilot_Run__c` or related archive-tracking records.
  - Honors legal hold and retention status before purge/delete operations.
  - ⚑ Archive callouts to external storage must not occur inside a DML transaction. Use Queueable Apex for the archive-then-update-reference pattern, same rule as nCino callouts.

## Document Intake, Extraction, and Parsing

### Intake: LWC File Upload

Analysts upload emailed attachments (PDF, JPEG, PNG) directly in the Document Corpus tab of the workbench. No email forwarding or external inbox required.

Flow:

1. Analyst opens the pilot run in the workbench, navigates to the Document Corpus tab.
2. `lightning-file-upload` component is scoped to the `Spread_Pilot_Run__c` record. Multiple files can be uploaded in one operation.
3. On `uploadfinished`, an Apex `@AuraEnabled` method (`SpreadDocumentService.onUpload`) receives the new `ContentDocumentId` list, creates one `Spread_Document__c` per file with `Extraction_Status__c = Pending`, creates `ContentDocumentLink` records, and enqueues one `ExtractionQueueable` job per document.
4. The Document Corpus tab refreshes via a wire refresh, showing each document in Pending state.

Supported formats: PDF (preferred — digital and scanned), JPEG, PNG. TIFF is not supported by Salesforce Files upload and should be converted to PDF before upload. XLSX is not supported by the Phase 1 extraction path.

### Extraction: Evidence Providers

**Why Docling, not FSC Intelligent Document Reader:**
IDR wraps Amazon Textract, has a 5-page cap per extraction job, requires a separate add-on license and AWS account, and uses template-bound field mapping. Arbitrary CPA-format financial statements (P&L, balance sheet, 1120S, 1065, Schedule K-1) exceed 5 pages and vary in layout by preparer. IDR is not viable for this use case.

**Docling** (IBM Research, MIT license) is the Phase 1 extraction engine for scanned or complex documents. Native text-layer PDFs should use a lightweight PDF text extractor first. Salesforce Document AI, FSC Intelligent Document Reader, or nCino extraction can be evaluated as provider adapters where the bank owns the required licenses and the document pattern fits the supported capability.

Extraction providers must return evidence, not final spread data.

**Microservice deployment options (bank chooses):**
- Heroku Python dyno (Eco or Basic, $5–$7/mo for pilot volume)
- Bank-hosted Docker container (on-prem or private cloud) — Docling Docker image available
- AWS Lambda (Python, MIT license, no Textract dependency)

**Extraction pipeline inside the microservice:**

```text
Receive multipart POST (ContentVersion binary + document metadata)
  -> If PDF has usable text layer: extract native text
  -> Else Docling/OCR: extract text + tables -> Markdown with table structure preserved
  -> Return raw evidence blocks:
       { evidence_type, raw_text, raw_table_markdown, page, coordinates, extraction_confidence }
  -> POST evidence to Salesforce REST callback endpoint (Named Credential auth)
```

**Salesforce-side callback endpoint:**
A public-facing Apex REST resource (`@RestResource(urlMapping='/spread/extraction-results/*')`) receives extraction evidence from the provider, looks up the `Spread_Document__c` by job ID, creates `Spread_Extraction_Evidence__c` records, and updates `Extraction_Status__c = Complete` (or `Failed` with exception reason if validation fails). It does not directly create final spread data.

### Parsing: Prompt Builder / Agentforce

Financial statement parsing begins only after extraction evidence is stored.

```text
SpreadCandidateParserService
  -> Select bounded evidence blocks for one document/period/statement type
  -> Ground prompt with:
       extracted evidence
       active spread line mapping configuration
       allowed normalized line names
       bank-specific ambiguity and exception rules
  -> Prompt Builder / Agentforce returns JSON only:
       { normalized_line, raw_label, raw_value, normalized_value,
         evidence_id, source_page, confidence, exception_reason }
  -> Apex validates schema and numeric normalization
  -> Apex creates draft Spread_Line_Item__c and Spread_Path_Result__c records
  -> Ambiguous or missing values create Spread_Exception__c
```

The prompt template must not receive raw PDF binaries and must not perform OCR. Its job is financial interpretation of extracted evidence: label matching, value normalization, statement-period selection, and exception identification.

**Named Credentials:**
- One Named Credential for the outbound callout to the extraction provider endpoint (Apex → provider).
- The callback endpoint authenticates the microservice using a Connected App + JWT or a long-lived access token stored as an External Credential on the microservice side — not a hardcoded username/password.

**Scanned document handling:**
Native PDFs use the text-layer extractor first. For scanned images (JPEG, PNG, or scanned PDF), Docling/OCR or another approved extraction provider creates evidence blocks. Low-DPI scans (below 150 DPI) may produce degraded results — the parsing layer should flag these for human review by returning a low confidence score rather than silently writing incorrect values.

**Exception routing on extraction failure:**
- Evidence schema validation failure → `Extraction_Status__c = Needs Review`, `Spread_Exception__c` created with `Severity__c = Warning`, assigned to analyst queue
- Prompt parsing timeout, invalid JSON, unmapped line, ambiguous period, or low-confidence candidate → `Parsing_Status__c = Needs Review`, `Spread_Exception__c` created and assigned to analyst queue
- Microservice unreachable → Queueable job fails, platform email to integration alert address (configurable in Custom Setting or Named Credential metadata)

## Error Handling and Concurrency

- Certification touches path result, audit log, and possibly exception records. Use a savepoint and rollback if any DML fails.
- Scorecard recalculation should not commit partial results. Use savepoint/rollback and mark prior scorecard stale if recalculation fails.
- Do not perform nCino callouts inside a DML transaction. Use Queueable Apex for asynchronous provider calls.
- Use `SELECT ... FOR UPDATE` on scorecard or pilot run records during recalculation, or accept eventual consistency and explicitly mark scorecards Stale after row changes.
- For the first pilot, document whether only one analyst reviews a pilot run at a time. Do not leave the concurrency assumption implicit.
- ⚑ Scorecard recalculation over large pilot runs (200+ documents, 1000+ path results) may approach CPU governor limits (10,000ms sync / 60,000ms async). If synchronous recalculation times out at realistic data volumes during testing, escalate to async. Prefer Batch Apex over Queueable for very large recalculations: Batch resets CPU time per chunk (up to 2,000 records per execute call) making it more suitable than Queueable when the total record set exceeds what a single async transaction can process within 60,000ms. Design the service method signature to support synchronous (small runs), Queueable (moderate), and Batch (large) invocation so the LWC can handle all three response paths from the outset. Note that async Apex jobs have no SLA and are subject to org-level flow control — under peak load, recalculation jobs may be delayed by minutes.

## nCino Integration

Until nCino supported documentation is available:

- Treat nCino as read-only references or external path labels.
- Do not write final nCino spread values.
- Do not assume object names, namespaces, or APIs.

Design now for later integration:

- The `ISpreadProvider` interface (`requestExtraction`, `getExtractionStatus`, `importExtractionEvidence`) is already implemented by `DoclingProvider` for Phase 1. `nCinoProvider` will implement the same interface against nCino's documented APIs when available.
- Named Credentials and External Credentials for all nCino callouts — same pattern as the Docling microservice credential.
- Async extraction state tracked on `Spread_Document__c.Extraction_Status__c` — same field used by Docling; nCino provider sets the same values.
- LWC polling pattern for status refresh already required by Docling — no additional work needed for nCino.
- Environment-specific endpoint and auth handled outside code via Named Credentials.
- ⚑ When nCino documentation is available, evaluate MuleSoft API-Led Connectivity as the mediation layer for `SpreadProviderService`. MuleSoft's Process API tier is the recommended pattern for API mediation, protocol translation, and transactional reliability between Salesforce and third-party financial platforms. The provider interface defined here (`requestExtraction`, `getExtractionStatus`, `importExtractionEvidence`) is compatible with a future MuleSoft-mediated callout via Named Credentials.

## Security and Sharing

Minimum permission sets:

- **Spreading Analyst**
  - Read documents, line items, path results, scorecards, and active policies.
  - Certify/reject only through Apex actions.

- **Credit Admin**
  - Manage policies and thresholds.
  - Activate policy sets if approval is complete.

- **Model Risk Reviewer**
  - Read-only access to pilot runs, documents, results, policies, thresholds, audit logs, reports, and agent sessions as approved.

- **Spreading System Integration**
  - Minimal integration permissions for data load/provider jobs.

Security defaults:

- OWD Private for pilot objects unless the org-specific sharing model says otherwise.
- No user delete access on audit logs.
- FLS locks certification fields from direct edit.
- ⚑ Evaluate Dynamic Data Masking (DDM) rules on `Spread_Path_Result__c` and `Pilot_Scorecard_Result__c` for role-based obfuscation of DSCR, loan balances, and borrower financial values visible in the workbench grid and reports. DDM masks at display time without altering source data and is configured separately from FLS.
- Use sharing rules/teams/queues for analyst and exception-review access.

## Reporting and PDF

Phase 1:

- Lightning report tab renders deterministic report data.
- Store generated HTML-like report data as Salesforce records or files where useful.
- Generate a Salesforce-native PDF if the report layout is simple enough.
- Attach PDF output to the pilot run when generated.

PDF implementation options:

- **Salesforce-native:** preferred for the first demo and for simple deterministic reports.
- **External rendering service:** design an adapter because complex reports, large tables, charts, and strict branding may exceed native PDF comfort.
- If the bank already owns a document-generation product, evaluate it before introducing a new renderer.
- Avoid agent-generated PDF content unless every narrative section cites selected certified facts.

The report strategy should therefore support both paths:

```text
SpreadReportService
  -> SalesforceNativePdfRenderer
  -> ExternalPdfRenderer, optional Phase 2
```

## LWC vs React

### Phase 1: LWC

Use LWC for sandbox demo and production baseline.

Why:

- GA and fully supported.
- App Builder-compatible.
- Native Salesforce Files and record context.
- Strong security/governance posture.
- Lightning base components and SLDS alignment.
- Lower demo risk for bank stakeholders.

### Phase 2: React Multi-Framework

Revisit React when the LWC baseline is stable and Salesforce Multi-Framework is GA or the bank explicitly accepts beta risk for a separate technology POC.

React is attractive for:

- Virtualized grids
- Advanced PDF review panes
- Diff views
- Charting
- Richer report authoring
- Agentforce Conversation Client embedding

Current constraints:

- Salesforce Multi-Framework React is beta.
- Beta apps are available in scratch orgs and sandboxes, not production.
- Lightning App Builder drag-and-drop support is not available during beta.
- React apps do not support Lightning base components or `lightning/*` modules.
- Some platform APIs are unavailable in the beta runtime.

## Migration Steps

1. **Create SFDX project**
   - Custom objects, custom metadata, permission sets, Apex services, LWC workbench, Flow definitions.

2. **Implement data model**
   - Build `Spread_Line_Item__c` + `Spread_Path_Result__c` + `Spread_Path__mdt` model.
   - Add policy, threshold, exception, scorecard, and audit objects.

3. **Port scorecard logic to Apex**
   - Preserve gates: 98% exact match, 99.5% dollar accuracy, zero uncaught material errors, 30% time reduction, 100% certification.
   - Read baseline behavior from `Spread_Path__mdt.Requires_Time_Reduction__c`.

4. **Build document intake and extraction pipeline**
   - Add `lightning-file-upload` to the Document Corpus tab. Wire `uploadfinished` to `SpreadDocumentService.onUpload`.
   - Implement `ExtractionQueueable`: retrieves `ContentVersion.VersionData`, POSTs to the extraction provider via Named Credential, stores job ID on `Spread_Document__c`.
   - Deploy extraction provider (Heroku Python or Docker): native PDF text extraction first; Docling/OCR only when the document lacks a usable text layer.
   - Implement Apex REST callback resource to receive extraction evidence and create `Spread_Extraction_Evidence__c` records.
   - Implement `SpreadCandidateParserService`: invoke Prompt Builder / Agentforce parsing on stored evidence, validate JSON, create draft `Spread_Line_Item__c` and `Spread_Path_Result__c` records.
   - Load synthetic pilot data for workbench testing: convert CSVs to Salesforce records, upload synthetic PDFs as Salesforce Files, link via `ContentDocumentLink`.

5. **Build LWC workbench**
   - Overview, document corpus, spread review, material errors, thresholds, report.
   - Include document preview pane and server-side pagination from day one.
   - ⚑ The workbench is a bank-facing component. Target 150+ on the LWC SLDS 2 165-point scoring rubric before demo delivery: all colors via CSS custom property tokens (no hardcoded hex or RGB), spacing via `--slds-g-spacing-*` tokens, dark mode verified, semantic HTML for interactive controls (no `div` buttons), `aria-label` on all icon-only buttons, keyboard-navigable grid and certification dialog. Hardcoded hex colors are an automatic scoring failure and break dark mode. Verify in both light and dark themes before handoff.

6. **Add threshold admin**
   - Create `Spreading_Definition__mdt` defaults.
   - Add `Spreading_Policy__c` and `Spreading_Threshold__c` demo policy.
   - Add dual-approval policy activation flow.
   - Start with the first-wave thresholds listed below.

7. **Add Agentforce assistant**
   - Add the `ParseExtractedFinancialEvidence` action for controlled draft candidate generation.
   - Start analyst-facing chat actions as read-only.
   - Add material-error explanation.
   - Add review-question drafting.
   - Add user-confirmed exception routing.

8. **Add PDF output**
   - Generate a deterministic Salesforce-native PDF and attach it to the pilot run.
   - Add renderer abstraction for later external PDF generation.

9. **Add nCino adapter**
   - Only after supported documentation is available.
   - Use Named Credentials and async provider pattern.

10. **Run UAT**
    - Credit analysts validate workflow.
    - Model risk validates scoring evidence and auditability.
    - Security validates Files access, conversation logs, and integration posture.

11. **Add retention/offload path**
    - Define archive target.
    - Offload older audit/report artifacts.
    - Preserve archive references.
    - Validate seven-year retention and legal-hold behavior.

12. **Run React POC**
    - Build only after LWC workbench is stable.
    - Focus on advanced grid/PDF review and Agentforce Conversation Client UX.
    - Treat as optional enhancement, not a blocker for Phase 1.

## First-Wave Thresholds

The bank will eventually need all major thresholds, but Phase 1 should start with the highest credit and pilot-governance impact.

Implement these first:

| Priority | Metric | Why First |
| --- | --- | --- |
| 1 | DSCR | Primary repayment-capacity indicator for many C&I credits. A bad spread that changes DSCR can change the credit conclusion. |
| 2 | Uncaught Material Errors | Hard stop for AI pilot governance. Any uncaught material error blocks production. |
| 3 | Dollar Accuracy | Captures dollar-weighted impact so large errors cannot hide behind many small correct lines. |
| 4 | Exact Match Rate | Basic extraction and mapping reliability measure. |
| 5 | Certification Rate | Enforces human-certified operating model. |
| 6 | Debt / EBITDA | Common leverage and repayment burden indicator. |
| 7 | Current Ratio | Basic liquidity signal. |
| 8 | Debt-to-Worth | Balance-sheet leverage and loss-absorption indicator. |

Second wave:

- FCCR
- Working capital
- AR days
- Inventory days
- Covenant-specific thresholds
- Industry-specific liquidity/leverage standards

Default Phase 1 pilot gates:

- DSCR threshold: bank-configured by policy; no universal default.
- Uncaught material errors: 0.
- Dollar-weighted accuracy: >= 99.5%.
- Exact match rate: >= 98%.
- Certification rate: 100% for material lines.
- Time reduction: >= 30% for non-baseline paths.

## Dual Approval Policy Activation

Threshold policy activation should require dual approval:

1. Credit policy or senior credit admin approval.
2. Model risk, compliance, or delegated second-line approval.

Recommended flow:

- Credit admin creates or edits `Spreading_Policy__c` and child thresholds in Draft.
- Submit for approval sets status to Pending Approval.
- First approver populates `Approved_By__c` and `Approved_At__c`.
- Second approver populates `Secondary_Approved_By__c` and `Secondary_Approved_At__c`.
- Activation flow validates both approvals, effective dates, threshold completeness, and no overlapping active policy with equal specificity.
- Activation retires or end-dates the prior active policy where appropriate.
- Activation writes `Spread_Audit_Log__c`.

## Scorecard Locking Recommendation

Use explicit pilot-run close as the scorecard lock point.

Why:

- Document sign-off may happen in pieces.
- Analysts need to recalculate draft scorecards during review.
- Locking too early creates rework when exceptions are resolved.
- Locking through an explicit close action is auditable and understandable for credit/model-risk users.

Lifecycle:

1. Run status Draft or Running: no certification or final scorecard lock.
2. Run status Review: certifications and draft scorecard recalculations are allowed.
3. Any certification or exception change marks scorecards Stale. ⚑ This stale-marking must execute inside `SpreadCertificationService` and the exception routing service — not via a record-triggered Flow or Apex trigger on `Spread_Path_Result__c`. Trigger-based stale-marking would fire on every bulk path result write, adding unnecessary DML overhead and limit exposure on a high-volume object.
4. User runs recalculation explicitly to create Current draft scorecards.
5. User closes pilot run.
6. Close action validates required certifications, unresolved exceptions, active policy, and report facts.
7. Close action creates final scorecards, locks them, writes audit records, and changes status to Complete.

If material exceptions remain open, close is blocked unless the active policy permits an approved exception path.

## Retention and Offload

Seven-year retention applies to:

- Pilot runs.
- Document corpus records.
- Spread line items and path results.
- Scorecard results.
- Policy versions and thresholds used.
- Exception records.
- Audit logs.
- Generated reports and PDFs.
- Agent conversation records or exported conversation evidence, subject to bank policy.

Recommended model:

- Keep active and recent pilot data in Salesforce.
- Archive older closed-run evidence to bank-approved storage after the operational access window.
- Store archive location, archive checksum, archived timestamp, and archived-by user on an archive tracking object or the pilot run.
- Use external IDs to correlate Salesforce records to archived evidence.
- Legal hold prevents purge/offload deletion.
- Purge only after retention period, archive validation, legal-hold check, and approval.

## Test Strategy

Apex:

- Target 90%+ class-level coverage for services.
- Use shared `SpreadTestDataFactory`.
- Test passing path, failed path, baseline/manual path, exception-routed mismatch, missing certification, threshold failure, scorecard stale behavior, audit writes, and policy resolution specificity.
- ⚑ Use constructor injection (Factory pattern) for all service dependencies: `SpreadCertificationService(SpreadPathResultSelector selector, UnitOfWork uow)`. Tests pass mock subclasses via `@TestVisible` constructors; production code uses the no-arg constructor which calls `Factory.getInstance()`. This is the vault-recommended pattern for making services testable without DML side effects.
- ⚑ Test `SpreadScorecardRules` and `SpreadPolicyRules` domain classes in pure unit tests with no DML — pass in SObjects directly and assert boolean outcomes. These tests should be fast and not require `@TestSetup`.

LWC:

- Test loading states, filters, pagination, read-only statuses, certification confirmation, bulk certification acknowledgment, and report fact selection.
- ⚑ Async wire adapter tests must call `.emit()` and `.error()` on the adapter mock and then `await flushPromises()` before asserting DOM state. Asserting before `flushPromises()` checks a stale DOM that has not yet re-rendered after the wire response.
- ⚑ Call `while (document.body.firstChild) { document.body.removeChild(document.body.firstChild); }` in `afterEach`. Missing DOM cleanup causes test bleed between certification dialog and bulk-certification tests, producing non-deterministic pass/fail.
- ⚑ Certification confirmation dialog and bulk certification flow require keyboard navigation tests: Enter/Space to confirm, Escape to cancel. The workbench must be WCAG 2.1 AA compliant; modal focus trap (focus moves into dialog on open, returns to trigger on close) must also be tested.

Agentforce:

- Test that each action returns only grounded facts.
- Test stale-context questions trigger `RefreshPilotContext`.
- Test the agent refuses certification, approval, risk-rating, and final-value write requests.
- ⚑ Adversarial testing required before deployment: test prompt injection attempts, requests to bypass guardrails, attempts to extract raw borrower data or invoke disallowed actions. Guardrail enforcement must be validated against a defined test set, not assumed.
- ⚑ ADLC testing principle: Agentforce behavior is non-deterministic. Test for behavioral alignment against defined acceptance envelopes, not exact output correctness. Define the acceptable response range for each action before UAT. The ADLC five-layer testing approach applies: (1) unit testing of individual actions, (2) E2E goal achievement scenarios, (3) adversarial/robustness, (4) Human-in-the-Loop scoring — credit analysts evaluate helpfulness and grounding quality on a representative sample before go-live, (5) performance/scale — simulate concurrent analyst sessions at expected peak load. Layers 4 and 5 are commonly omitted and become the source of post-launch failures.
- ⚑ Use the AFDX Testing Center for automated regression testing in CI/CD. Supports up to 1,000 test cases and 10 concurrent runs. Build the adversarial and behavioral test set during development, not after UAT.
- ⚑ Use the Session Tracing Data Model to debug unexpected behavior during UAT. The key entities are `AIAgentSession` (container for the interaction sequence), `AIAgentInteraction` (one user request through agent response turn), `AIAgentInteractionStep` (discrete actions within a turn), and `AIAgentInteractionMessage` (individual communications). Do not rely on conversation logs alone — structured session traces are required for model-risk evidence.

Integration:

- Test Salesforce Files upload/linking.
- Test synthetic PDF preview.
- Test future nCino provider with HTTP callout mocks and Queueable Apex.

## Open Decisions

1. Which second-line role provides the second approval: model risk, compliance, credit risk review, or another group?
2. What is the operational access window before records are offloaded from Salesforce?
3. What archive target should be used for seven-year retention?
4. Which Salesforce-native PDF mechanism is acceptable in the target org?
5. Does the bank already own a document generation or external rendering product?
6. Which industry/borrower-size tiers should be configured after the first-wave thresholds?
7. ⚑ If Data 360 / Data Cloud is introduced as a borrower data layer, evaluate replacing direct Apex SOQL grounding in `RefreshPilotContext` and `ExplainCreditImpact` with the Data Graph API for unified borrower context. This decision impacts the grounding architecture for the agent and should be resolved before expanding the agent's data access scope.

## Official Salesforce Sources

- Agentforce overview and Agent Script: https://developer.salesforce.com/docs/ai/agentforce/guide/get-started.html
- Agent Script language characteristics: https://developer.salesforce.com/docs/ai/agentforce/guide/ascript-lang.html
- Agent Script actions: https://developer.salesforce.com/docs/ai/agentforce/guide/ascript-ref-actions.html
- Agentforce custom actions: https://developer.salesforce.com/docs/ai/agentforce/guide/get-started-actions.html
- Apex InvocableMethod Agentforce actions: https://developer.salesforce.com/docs/ai/agentforce/guide/agent-invocablemethod.html
- Agentforce agents invoked from Apex and Flow: https://developer.salesforce.com/blogs/2025/04/invoke-agentforce-agents-with-apex-and-flow.html
- Prompt Builder grounding with Salesforce resources: https://help.salesforce.com/s/articleView?id=ai.prompt_builder_ground_template.htm&type=5
- Prompt Builder programmatic invocation: https://developer.salesforce.com/docs/ai/agentforce/guide/get-started-prompt-builder.html
- Salesforce Data Cloud Document AI: https://developer.salesforce.com/blogs/2025/08/process-unstructured-data-with-document-ai
- FSC Intelligent Document Reader: https://help.salesforce.com/s/articleView?id=ind.fsc_intelligent_document_reader.htm&type=5
- Lightning Web Components overview: https://developer.salesforce.com/docs/platform/lwc/guide/get-started-introduction
- Supported LWC targets: https://developer.salesforce.com/docs/platform/lwc/guide/get-started-supported-experiences.html
- Salesforce Multi-Framework React announcement: https://developer.salesforce.com/blogs/2026/04/build-with-react-run-on-salesforce-introducing-salesforce-multi-framework
- Build a React app with Salesforce Multi-Framework: https://developer.salesforce.com/docs/platform/code-builder/guide/reactdev-overview.html
- React app project structure and UIBundle metadata: https://developer.salesforce.com/docs/platform/code-builder/guide/reactdev-integrate.html
- React app styling considerations: https://developer.salesforce.com/docs/platform/code-builder/guide/reactdev-styling.html
- Agentforce Conversation Client in React: https://developer.salesforce.com/docs/platform/einstein-for-devs/guide/reactdev-acc.html
- Custom metadata types as deployable app configuration: https://developer.salesforce.com/blogs/2015/04/custom-metadata-types-ga
- Testing custom metadata types in Apex: https://developer.salesforce.com/blogs/engineering/2015/05/testing-custom-metadata-types.html
