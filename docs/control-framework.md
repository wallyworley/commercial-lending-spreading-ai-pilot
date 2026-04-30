# Control Framework

## Current Control Boundary

As of 2026-04-29, the working Agentforce prototype uses this boundary:

- Docling extracts text and tables from Salesforce Files.
- Deterministic Apex maps extracted evidence to draft spread candidates.
- Candidate values are stored in `Spread_Path_Result__c.Candidate_Value__c`.
- Extracted values are not final credit data.
- Analysts certify or reject values in the workbench.
- Any future analyst adjustment must preserve the original extracted candidate and store the analyst value separately.
- nCino final spread writeback is not implemented.

## Control Objectives

The pilot must prove that AI-assisted spreading is:

- Accurate enough for C&I underwriting support.
- Traceable to source documents.
- Draft-only until human certified.
- Governed by least privilege and auditable workflow.
- Supported by Salesforce and nCino documented capabilities.
- Acceptable to model risk, information security, legal, compliance, and credit leadership.

## Security Controls

| Control | Requirement |
| --- | --- |
| Least privilege | Users and integrations receive only the access required for assigned pilot work. |
| Permission-based document access | Financial documents remain visible only to users with loan or review responsibility. |
| Credential governance | Salesforce outbound integrations use Named Credentials and External Credentials. |
| Encryption review | Files, sensitive fields, and staging records are reviewed for Shield or platform encryption needs. |
| Audit logging | Upload, extraction, review, certification, and promotion events are logged. |
| Vendor access | nCino or Salesforce support access follows bank-approved vendor access procedures. |
| Third-party extraction service | Docling/Render use is sandbox-only until vendor/security review approves production use or a bank-approved extraction provider replaces it. |

## Model-Risk Controls

| Control | Requirement |
| --- | --- |
| Gold-standard baseline | Senior analysts certify manual spreads before AI comparison. |
| Same-document comparison | Each tested path uses the same document set. |
| Blind review where feasible | Reviewers should not know which tool generated draft values during certification. |
| Material field protection | EBITDA, revenue, debt service, cash, liabilities, net worth/equity, current assets, current liabilities, and covenant inputs receive explicit review. |
| Error taxonomy | Errors are classified as extraction, mapping, period, source-quality, calculation, or reviewer errors. |
| Limitation log | Unsupported file types, document sizes, handwriting, formatting, and schema gaps are logged. |
| Parser transparency | Current parser is deterministic Apex with custom metadata mappings. It should be validated separately from any future LLM-based parser. |

## Vendor Evidence Required Before Contract Approval

Request these from nCino under NDA before purchase or production approval:

- Current implementation guide for Automated Spreading.
- Data flow and hosting architecture for the automated spreading feature.
- SOC 1 Type II and SOC 2 Type II reports or bridge letters.
- ISO 27001 certificate and scope.
- AI/model governance documentation for extraction and mapping.
- Subprocessor list and data residency details.
- Supported document types, limits, exception behavior, and known limitations.
- Audit logging, retention, and customer data deletion behavior.
- Salesforce package/object/API impact documentation.

## Certification Rule

AI-generated draft values must not become final credit values until a qualified credit reviewer certifies the line item or explicitly resolves its exception.

Certification requires:

- Reviewer identity.
- Review timestamp.
- Source document reference.
- Confirmation that the final value matches the source evidence.
- Exception notes when a value is changed, rejected, or manually entered.

## Analyst Adjustment Rule

Analysts will eventually need to change numbers. When that capability is added, do not overwrite the extracted candidate value.

Required adjustment pattern:

- Preserve `Candidate_Value__c` as the extracted/parser value.
- Store analyst-entered value separately, currently planned for `Manual_Value__c` or a dedicated reviewed-value field.
- Require an adjustment reason.
- Keep source evidence linked.
- Mark the record as certified with adjustment or rejected and corrected.
- Include the reviewer, timestamp, original value, adjusted value, and reason in audit evidence.
