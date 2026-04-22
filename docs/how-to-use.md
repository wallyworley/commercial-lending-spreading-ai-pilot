# How to Use This Project

Use this project as the working folder for deciding whether AI financial spreading is safe enough to buy or implement. It is not an app that connects to Salesforce or nCino yet. It is a pilot-control package: charter, architecture, test templates, source register, and a scorecard.

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
- AI output is draft-only.
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

Run the same document set through each path:

| Path | What to Do |
| --- | --- |
| `ncino_automated_spreading` | Run documents through nCino Automated Spreading using supported nCino Document Manager and Spreads workflow. |
| `salesforce_native_staging` | Run documents through the Salesforce-supported extraction/staging design. If this is not built yet, score it as a design alternative after a small proof of concept. |
| `manual_ncino_control` | Measure current or improved manual nCino Document Manager and Spreads workflow. This is the baseline. |

The manual control path does not need to reduce time. It establishes the baseline the AI paths must beat.

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
