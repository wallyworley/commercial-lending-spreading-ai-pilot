# Control Framework

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

## Model-Risk Controls

| Control | Requirement |
| --- | --- |
| Gold-standard baseline | Senior analysts certify manual spreads before AI comparison. |
| Same-document comparison | Each tested path uses the same document set. |
| Blind review where feasible | Reviewers should not know which tool generated draft values during certification. |
| Material field protection | EBITDA, revenue, debt service, cash, liabilities, net worth/equity, current assets, current liabilities, and covenant inputs receive explicit review. |
| Error taxonomy | Errors are classified as extraction, mapping, period, source-quality, calculation, or reviewer errors. |
| Limitation log | Unsupported file types, document sizes, handwriting, formatting, and schema gaps are logged. |

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

