# Pilot Charter

## Objective

Determine whether AI-assisted C&I financial spreading can safely reduce analyst effort while preserving credit quality, auditability, and regulatory defensibility.

Current prototype note, 2026-04-29:

The active build is an Agentforce sandbox prototype, not a production nCino integration. It uses a fake `Commercial_Loan__c` object as the working loan context, Salesforce Files for upload, Docling for extraction, deterministic Apex for parsing, and an LWC workbench for analyst review.

## Scope

Initial scope is C&I borrower financial documents only:

- Tax returns.
- Audited financial statements.
- Company-prepared financial statements.
- Balance sheets.
- Income statements.
- Supporting schedules.
- 10-K and 10-Q filings where applicable.

CRE packages, rent rolls, personal financial statements, collateral valuation, and covenant automation are out of scope for the first pilot unless approved as a separate phase.

## Paths Under Evaluation

1. Salesforce-native document extraction and staging, currently implemented in the Agentforce sandbox.
2. nCino Automated Spreading, deferred until nCino scope and supported APIs are reopened.
3. Manual spreading control path, deferred until the Salesforce-native workflow is stable enough for time comparison.

## Operating Model

AI output is draft-only. A generated value can prefill a staging record, but it cannot be treated as final spread data until a credit user certifies it.

Current parser output is better described as automated extraction/parsing output, not AI output. It is still draft-only and subject to the same certification rule.

Every staged line item must retain:

- Borrower and loan/opportunity context.
- Source document reference.
- Statement type and fiscal period.
- Source page and source coordinates where available.
- Extracted raw value.
- Normalized spread line.
- Confidence or exception reason.
- Reviewer and certification timestamp.
- Final spread reference, if promoted after review.

## Required Roles

| Role | Responsibility |
| --- | --- |
| Credit Executive Sponsor | Owns pilot decision and production go/no-go. |
| Senior Credit Analysts | Create gold-standard manual spreads and certify pilot output. |
| Salesforce Architect | Owns Salesforce integration, staging, security, and audit architecture. |
| nCino Administrator | Owns nCino Document Manager, Spreads, templates, and vendor configuration. |
| Information Security | Reviews access, encryption, vendor controls, and data movement. |
| Model Risk | Reviews pilot design, sampling, metrics, and limitations. |
| Compliance/Legal | Reviews records, retention, vendor terms, and regulatory expectations. |

## Go/No-Go Gates

The pilot passes only if all gates are met:

- Exact line-item match rate is at least 98%.
- Dollar-weighted accuracy is at least 99.5%.
- There are zero uncaught material errors.
- Analyst spreading time is reduced by at least 30%.
- Every extracted value is traceable to document evidence.
- Low-confidence, missing, ambiguous, duplicate, or unmapped values route to review.
- All material AI-generated line items are human-certified before final use.

For the current deterministic parser, add these near-term gates before expanding scope:

- Multi-period rows produce the correct amount for each period.
- Extracted values remain traceable to `Spread_Extraction_Evidence__c`.
- The analyst can understand the screen without reading object names or path keys.
- Failed extraction can be retried without creating duplicate final results.

## Decision Outcomes

| Outcome | Meaning |
| --- | --- |
| Proceed | All gates pass and risk owners approve a controlled production rollout. |
| Remediate and Retest | One or more gates fail but the failure has a bounded, fixable cause. |
| Do Not Proceed | Accuracy, controls, source traceability, vendor evidence, or operating risk is unacceptable. |
