# How to Use This Project

Use this project as the working folder for deciding whether automated financial spreading is safe enough to buy or implement. It now includes a working Salesforce-native Agentforce sandbox flow, plus the pilot-control package: charter, architecture, test templates, source register, and scorecard.

Current implementation note, 2026-04-29:

- The working UI is the `commercialSpreadingPilotWorkbench` LWC on `Commercial_Loan__c` record pages.
- Documents are uploaded to Salesforce Files.
- Docling extracts source text/tables.
- Deterministic Apex currently parses known financial statement labels and periods.
- Values are draft candidates until an analyst certifies them.
- nCino integration is intentionally deferred for now.

## 1. Start With the Decision

Read these first:

- `docs/pilot-charter.md`
- `docs/commercial-lending-spreading-primer.md`
- `docs/architecture.md`
- `docs/control-framework.md`

The core decision is:

> Should the bank allow AI-generated financial spreading values into the commercial credit workflow?

The default answer is no unless the pilot proves accuracy, traceability, certification, and control effectiveness.

## 2. Confirm the Pilot Scope

Use `docs/pilot-charter.md` in a working session with:

- Credit leadership.
- Senior credit analysts.
- Salesforce owner.
- nCino owner.
- Information security.
- Model risk.
- Compliance/legal.

Confirm these before testing:

- Initial portfolio is C&I, not CRE.
- Automated extraction/parsing output is draft-only.
- Human certification is mandatory for material values.
- nCino Automated Spreading is being tested against alternatives, not assumed to win.
- Production is blocked unless every gate passes.

## 3. Build the Document Corpus

If you do not have real pilot data yet, generate fake data first:

```bash
npm run generate:synthetic
```

This creates synthetic PDFs and CSVs under `data/synthetic/`. The files are fictional and marked as synthetic demo data. They are useful for practicing the workflow before you receive real nCino or Salesforce pilot results.

Copy this template:

```bash
cp data/templates/document-corpus.csv data/pilot-results/document-corpus.csv
```

Then replace the sample row with real pilot document metadata. Do not store confidential borrower documents in this repo. Put only references to bank-controlled document locations.

The corpus should include easy and hard examples:

- Clean native PDFs.
- Scanned documents.
- Tax returns.
- Audits.
- Borrower-prepared statements.
- Multi-period statements.
- Poor-quality scans.
- Missing pages.
- Duplicate or conflicting periods.
- Nonstandard line labels.

## 4. Create the Gold-Standard Manual Spread

Copy this template:

```bash
cp data/templates/gold-standard-spread.csv data/pilot-results/gold-standard-spread.csv
```

Senior credit analysts should create this manually before AI results are scored. This becomes the truth set.

Each row should represent one spread line item, such as:

- Revenue.
- EBITDA.
- Cash.
- Current assets.
- Current liabilities.
- Total liabilities.
- Net worth/equity.
- Debt service.
- Covenant inputs.

## 5. Run the Three Pilot Paths

Run the same document set through each path as the pilot matures:

| Path | What to Do |
| --- | --- |
| `ncino_automated_spreading` | Deferred for now. Run documents through nCino Automated Spreading later using supported nCino Document Manager and Spreads workflow. |
| `salesforce_native_staging` | **Now available in Salesforce**: Upload documents via the pilot workbench LWC, monitor extraction status, review parsed line items, and certify candidates. See `docs/implementation-status.md` for component details. |
| `manual_ncino_control` | Later baseline. Measure current or improved manual nCino Document Manager and Spreads workflow. |

The manual control path does not need to reduce time. It establishes the baseline the AI paths must beat.

### Using the Salesforce Workbench

The LWC workbench (`commercialSpreadingPilotWorkbench`) provides:
- Document upload and extraction status monitoring
- Parsed line-item review grid with sort and filter
- Material error detection and reporting
- Certification workflow for each line item
- Scorecard calculation and path comparison
- Document retry if extraction fails

In the current Agentforce sandbox, use the Commercial Loans tab or App Launcher:

```text
Commercial Loans -> open a Commercial Loan record -> C&I Spreading Evidence Pilot
```

The record page workbench will create or reuse the loan-scoped pilot run.

### Current Analyst Flow

1. Open a `Commercial_Loan__c` record.
2. Upload a financial statement on the Document Corpus tab.
3. Watch the document reach `Extraction = Complete`.
4. If parsing does not run automatically, click `Parse Ready Documents`.
5. Open the Spread Review tab.
6. Review the analyst-style grid, where fiscal periods are columns.
7. Use `Evidence` links to inspect the extracted source text.
8. Certify values that are acceptable.
9. Reject values that need correction or mapping changes.

Current behavior:

- `Candidate_Value__c` stores the extracted/parser value.
- `Manual_Value__c` is reserved for baseline/manual comparison and future analyst adjustments.
- The screen does not overwrite extracted values directly.
- Future adjustment work should store analyst-entered values separately and require a reason.

## 6. Capture Extraction Results

Copy this template:

```bash
cp data/templates/extraction-results.csv data/pilot-results/extraction-results.csv
```

Use it to record draft extracted values, reviewer actions, exception reasons, source page references, and certification status.

This file answers:

- Where did each value come from?
- Was it mapped correctly?
- Was it reviewed?
- Was it certified?
- Did it become final spread data?

In the Salesforce implementation, the same evidence is captured natively:

- `Spread_Extraction_Evidence__c`: raw extracted source text/table evidence.
- `Spread_Line_Item__c`: normalized line and period.
- `Spread_Path_Result__c`: candidate value, raw label/value, certification status, and reviewer result.

## 7. Fill Out the Scorecard

Copy this template:

```bash
cp data/templates/pilot-scorecard.csv data/pilot-results/pilot-scorecard.csv
```

Then replace the sample rows with measured results from the pilot.

Important fields:

| Field | Meaning |
| --- | --- |
| `path` | One of `ncino_automated_spreading`, `salesforce_native_staging`, or `manual_ncino_control`. |
| `manual_value` | Gold-standard certified value. |
| `candidate_value` | Value produced by the tested path. |
| `material` | `true` for values that matter to underwriting, covenants, risk rating, or credit memo output. |
| `exception_flag` | `true` if the tool correctly routed the issue for human review. |
| `certified` | `true` only if a qualified reviewer certified the value. |
| `manual_minutes` | Baseline analyst time. |
| `candidate_minutes` | Time required using the tested path. |

## 8. Run the Scorecard

From the project folder:

```bash
npm test
npm run scorecard -- data/pilot-results/pilot-scorecard.csv
```

If you only want to try the sample data:

```bash
npm run scorecard -- data/templates/pilot-scorecard.csv
```

If you want to try the richer synthetic data:

```bash
npm run generate:synthetic
npm run scorecard -- data/synthetic/pilot-scorecard.csv --no-exit-code
npm run report -- data/synthetic/pilot-scorecard.csv
```

The synthetic data intentionally includes several extraction and period errors, so it is normal for candidate paths to fail. The `--no-exit-code` option lets you print the results without treating the failing pilot as a shell error.

The report command creates `reports/pilot-scorecard-report.html`, which can be opened in a browser for a cleaner executive or credit/risk review.

The scorecard reports:

- Exact line-item match rate.
- Dollar-weighted accuracy.
- Time reduction.
- Certification rate.
- Uncaught material errors.
- Pass/fail by path.

## 9. Interpret the Results

The AI paths pass only if they meet every gate:

- Exact match rate is at least 98%.
- Dollar-weighted accuracy is at least 99.5%.
- Uncaught material errors are zero.
- Analyst time reduction is at least 30%.
- Required certification is 100%.

If nCino Automated Spreading fails one of these gates, the correct next step is not to tune the narrative. The next step is to classify the failure, ask nCino for product/implementation evidence, and retest the affected scenario group.

## 10. Use the Outputs for the Vendor Decision

Use the following materials for the final recommendation package:

- `docs/pilot-charter.md` for the decision structure.
- `docs/control-framework.md` for risk-owner review.
- `docs/source-register.md` for official-source discipline.
- `data/pilot-results/document-corpus.csv` for sample coverage.
- `data/pilot-results/gold-standard-spread.csv` for truth-set evidence.
- `data/pilot-results/extraction-results.csv` for traceability and review evidence.
- Scorecard command output for pass/fail metrics.

## Recommended First Working Session

For the first 60-minute meeting, do this:

1. Review the pilot gates in `docs/pilot-charter.md`.
2. Confirm the document types in scope.
3. Assign owners for the corpus, gold-standard spread, nCino test, Salesforce-native test, and scorecard.
4. Select 25-50 representative borrower document packages for the first corpus.
5. Decide what counts as a material line item for the bank.

After that meeting, the project becomes a checklist-driven evidence folder.

## Tomorrow Pickup Checklist

1. Refresh the Commercial Loan record page and confirm the new analyst spread view loads.
2. Upload more synthetic balance sheets and income statements from the sample document folder.
3. Confirm period columns and extracted amounts look right.
4. Identify the first labels that fail mapping and add `Spread_Line_Mapping__mdt` records.
5. Decide whether the next UX step is analyst adjustment entry or better evidence preview.
