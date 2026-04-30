# Test Plan

## Current Sandbox Baseline

As of 2026-04-29, the Agentforce sandbox supports an end-to-end Salesforce-native test path:

1. Upload a document from a `Commercial_Loan__c` record page.
2. Confirm Docling extraction creates `Spread_Extraction_Evidence__c`.
3. Confirm deterministic Apex parsing creates `Spread_Line_Item__c` and `Spread_Path_Result__c`.
4. Confirm the Spread Review tab shows spread lines with periods pivoted into columns.
5. Certify or reject extracted candidate values.

Current parser scope:

- Known mapped balance-sheet and income-statement labels.
- Multi-period balance-sheet rows where period headers are present.
- Period inference from full date headers such as `December 31, 2025`.
- Fallback period inference from year headers such as `2025 2024`.

Current parser is deterministic Apex. It is not an AI/LLM parser yet.

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

Immediate next sample focus:

- Larger multi-page balance sheets.
- Income statements with two and three periods.
- Statements where values are shown in thousands.
- Parentheses/negative values.
- Debt schedules and interest expense lines.
- Common synonyms for current assets, current liabilities, equity, revenue, EBITDA, and debt service.

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
2. For current sandbox testing, upload each document to a `Commercial_Loan__c` record.
3. Confirm extraction status, parsing status, evidence count, page count, and parsed line count.
4. Review period columns in the Spread Review tab.
5. Certify correct candidate values and reject incorrect values.
6. Log mapping gaps and period/classification failures.
7. Add or adjust `Spread_Line_Mapping__mdt` records for deterministic parser gaps.
8. Create certified manual spreads once the candidate UI is stable.
9. Run nCino Automated Spreading later, after nCino scope is reopened.
10. Load measured results into `data/templates/pilot-scorecard.csv` or a copied result file.
11. Run `npm run scorecard -- <scorecard.csv>`.
12. Review failures with credit, model risk, information security, and Salesforce/nCino owners.

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

## Manual Test Cases Added 2026-04-29

| Scenario | Expected Result |
| --- | --- |
| Render cold start returns 503 loading page | Extraction retries before final failure. |
| Render chunk termination during extraction | Extraction retries before final failure. |
| One-page two-period balance sheet | Parser creates one line per normalized line per period. |
| Header `December 31, 2025 December 31, 2024` | Periods display as `12/31/2025` and `12/31/2024`. |
| Header `2025 2024` without full dates | Periods display as `FY2025` and `FY2024`. |
| No manual baseline exists | Analyst view shows extracted candidate amount without `Needs baseline` noise. |
| Analyst review grid | Periods appear as columns, not repeated rows. |

## Retest Rule

If a vendor or configuration change is made after a failed test, rerun the entire affected scenario group. Do not cherry-pick only the previously failed records.
