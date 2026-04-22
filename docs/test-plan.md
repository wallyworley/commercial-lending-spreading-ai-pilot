# Test Plan

## Corpus Design

Build a pilot corpus that represents the bank's actual C&I borrower population. Include clean and difficult documents.

Required scenario types:

- Clean native PDF.
- Scanned PDF.
- Borrower-prepared statement.
- Audited statement.
- Tax return.
- Multi-period financial statement.
- Amended statement.
- Poor-quality scan.
- Nonstandard account labels.
- Negative values and contra accounts.
- Missing pages.
- Duplicate statement periods.
- Conflicting fiscal periods.
- Handwritten notes.
- Unsupported file size or file type.

Use `data/templates/document-corpus.csv` to track corpus metadata without storing confidential files in this repository.

## Gold-Standard Baseline

Senior credit analysts create the baseline before AI scoring. Use `data/templates/gold-standard-spread.csv`.

Baseline records must identify:

- Borrower.
- Loan or opportunity.
- Document.
- Statement type.
- Fiscal period.
- Normalized spread line.
- Final manual value.
- Materiality.
- Analyst.
- Certification timestamp.

## Execution Steps

1. Register pilot documents in the corpus template.
2. Create certified manual spreads.
3. Run the same document set through nCino Automated Spreading.
4. Run the same document set through the Salesforce-native staging path.
5. Run or measure the improved manual nCino control path.
6. Load measured results into `data/templates/pilot-scorecard.csv` or a copied result file.
7. Run `npm run scorecard -- <scorecard.csv>`.
8. Review failures with credit, model risk, information security, and Salesforce/nCino owners.

## Acceptance Metrics

| Metric | Gate |
| --- | ---: |
| Exact line-item match rate | >= 98.0% |
| Dollar-weighted accuracy | >= 99.5% |
| Uncaught material errors | 0 |
| Analyst time reduction | >= 30.0% |
| Required certification complete | 100% |

## Error Taxonomy

| Error Type | Meaning |
| --- | --- |
| extraction | Wrong source text or number was extracted. |
| mapping | Correct source value mapped to the wrong spread line. |
| period | Value assigned to the wrong fiscal period. |
| document | Wrong, duplicate, missing, or unsupported document issue. |
| calculation | Derived value or rollup was incorrect. |
| reviewer | Human review or certification error. |

## Retest Rule

If a vendor or configuration change is made after a failed test, rerun the entire affected scenario group. Do not cherry-pick only the previously failed records.

