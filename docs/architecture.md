# Architecture

## Principle

Salesforce and nCino remain the workflow and audit system. AI systems may generate draft spread candidates, but final credit data is created only through supported Salesforce/nCino paths and human certification.

## Pilot Path 1: nCino Automated Spreading

nCino is the benchmark path. It should use only nCino-supported workflows:

- Documents originate in nCino Document Manager where possible.
- Automated Spreading extracts and maps values from supported document types.
- Results are reviewed line-by-line before promotion into nCino Spreads.
- Final values remain governed by nCino Spreads and bank credit policy.

No direct write into final spread data should be introduced outside supported nCino configuration or vendor-approved APIs.

## Pilot Path 2: Salesforce-Native Extraction and Staging

The Salesforce-native path should stage extracted values for review before any final credit use:

1. Document intake occurs through Financial Services Cloud document controls, Document Checklist Items, or the bank's existing file process.
2. Supported Salesforce document extraction capabilities process PDFs or images where appropriate.
3. Extracted values map into draft-only staging records.
4. Reviewers certify material fields.
5. Certified values are manually reconciled or integrated into the bank-approved nCino/Salesforce final process.

Outbound calls from Salesforce must use Named Credentials and External Credentials. Legacy named credential patterns should not be introduced for new pilot work.

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
  -> Salesforce/nCino document intake
  -> Extraction path under test
  -> Draft spread staging
  -> Exception routing and human certification
  -> Final nCino/Salesforce credit workflow, only after certification
  -> Pilot scorecard and model-risk evidence package
```

## Production Blockers

Do not proceed to production if any of these remain unresolved:

- Unsupported nCino object writes are required.
- Source evidence cannot be traced at line-item level.
- Material fields can bypass human certification.
- Access to financial documents is broader than the originating loan workflow requires.
- Vendor security, SOC, subprocessor, or implementation documentation is unavailable for review.
- Model-risk stakeholders reject the sample design or accuracy evidence.

