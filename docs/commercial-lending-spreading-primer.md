# Commercial Lending Spreading Primer

Research date: April 20, 2026

This primer explains financial statement spreading from the perspective of a commercial credit analyst or underwriter. It is intended to improve the AI spreading pilot by making the test data, scorecard, and report more faithful to commercial banking credit work.

## 1. What Spreading Is

Spreading is the process of taking borrower financial information from source documents and normalizing it into a consistent credit-analysis format across borrowers, periods, entities, and document types.

In practice, spreading is not just data entry. A good spread lets the bank:

- Compare borrower performance across periods.
- Calculate ratios consistently.
- Evaluate repayment capacity.
- Identify trends, anomalies, and covenant pressure.
- Support risk rating, credit memo, and portfolio monitoring decisions.
- Preserve evidence back to source documents.

For this pilot, the key lesson is simple: AI can help extract and map values, but the underwriting judgment lives in how those values affect cash flow, repayment capacity, collateral support, and risk rating.

## 2. The Credit Question Behind Every Spread

Commercial credit analysis starts with repayment capacity. Regulatory guidance repeatedly points examiners and bankers toward the borrower’s ability and willingness to repay under reasonable terms, the purpose and terms of the borrowing, the expected source of repayment, the borrower’s financial condition, collateral, market conditions, and guarantor support.

A spread should therefore answer these core questions:

- What is the primary source of repayment?
- Is operating cash flow sufficient to service debt?
- Are trends improving, stable, or deteriorating?
- Is liquidity adequate for working-capital needs and shocks?
- Is leverage reasonable for the borrower’s industry and structure?
- Are collateral and guarantors secondary support or the real repayment source?
- Are projections realistic relative to historical performance?
- Are there weaknesses that should affect risk rating, covenants, or approval conditions?

## 3. Documents Commonly Spread

Commercial spreading commonly uses several document types. Each type has different reliability and interpretation risk.

| Document | Credit Use | Key Risk |
| --- | --- | --- |
| Audited financial statements | Higher-reliability GAAP view of performance, position, and cash flows. | Audit opinion, notes, consolidation, and subsequent events matter. |
| Reviewed or compiled statements | Useful for trend and ratio analysis. | Less assurance than audited statements. |
| Company-prepared statements | Often timely for interim monitoring. | Management-prepared values may lack independent assurance. |
| Tax returns, such as Form 1120 | Useful for taxable income, gross receipts, deductions, and reconciliation. | Tax accounting and financial reporting can differ materially. |
| 10-K | Public-company annual view with audited financial statements, MD&A, risks, and notes. | May be consolidated and not borrower-entity specific. |
| 10-Q | Public-company interim view with unaudited financial statements. | Interim/quarterly values can be misread as annual values. |
| Debt schedules | Needed for DSCR, fixed-charge coverage, maturities, and global debt load. | Missing off-balance-sheet, related-party, or guarantor obligations. |
| AR and inventory reports | Needed for asset-based or working-capital facilities. | Eligibility, aging, dilution, concentration, and obsolescence risk. |

## 4. Statements and Schedules to Spread

Most C&I spreads need these sections:

- Income statement: revenue, COGS, gross profit, operating expenses, EBITDA, interest, taxes, net income.
- Balance sheet: cash, receivables, inventory, current assets, fixed assets, current liabilities, debt, total liabilities, equity.
- Cash flow: operating cash flow, working capital changes, capital expenditures, financing activity, distributions.
- Debt schedule: current maturities, interest expense, required principal, debt service, maturities, collateral.
- Guarantor/global cash flow: guarantor income, debt, liquidity, contingent liabilities, and support capacity.
- AR/inventory support when collateral-based lending is involved.

## 5. Core Ratios and Why They Matter

Different banks define ratios differently. The pilot should use the bank’s credit policy definitions, but the following are common underwriting concepts.

| Area | Ratio | Typical Formula | Why It Matters |
| --- | --- | --- | --- |
| Liquidity | Current ratio | Current assets / current liabilities | Near-term ability to cover obligations. |
| Liquidity | Working capital | Current assets - current liabilities | Operating cushion and borrowing need. |
| Leverage | Debt-to-worth | Total liabilities / equity | Balance-sheet leverage and loss absorption. |
| Leverage | Debt / EBITDA | Funded debt / EBITDA | Debt burden relative to recurring earnings. |
| Coverage | DSCR | Cash flow available for debt service / required debt service | Capacity to service interest and principal. |
| Coverage | Fixed-charge coverage | Adjusted cash flow / fixed charges | Capacity after taxes, capex, distributions, or lease burden. |
| Profitability | Gross margin | Gross profit / revenue | Pricing power and cost structure. |
| Profitability | EBITDA margin | EBITDA / revenue | Operating cash earnings before financing/tax structure. |
| Activity | AR days | Accounts receivable / average daily sales | Collection speed and working-capital pressure. |
| Activity | Inventory days | Inventory / average daily COGS | Inventory conversion and obsolescence risk. |

## 6. EBITDA Is Not Cash Flow

An AI spreading tool will often extract EBITDA or calculate it from mapped lines. That is useful, but it is not enough.

Credit analysis usually needs to move from earnings to cash available for debt service. Common adjustments include:

- Interest, taxes, depreciation, and amortization.
- Non-recurring gains or losses.
- Owner compensation normalization.
- Related-party transactions.
- Working-capital changes.
- Maintenance capital expenditures.
- Distributions or dividends.
- Current maturities of long-term debt.
- Operating lease or rent burden where relevant.
- One-time addbacks that require evidence and policy approval.

The pilot should not treat an AI-calculated EBITDA number as a final credit metric unless the reviewer confirms the source lines, allowed addbacks, period, and bank policy definition.

## 7. Primary and Secondary Repayment Sources

For traditional C&I lending, the strongest primary repayment source is usually recurring business cash flow sufficient to cover debt service under reasonable terms.

Secondary sources may include:

- Collateral liquidation.
- Guarantor support.
- Refinancing.
- Asset sale.
- Controlled cash.
- Additional committed equity or sponsor support.

Regulatory guidance is clear that weak or unsupported repayment sources should not be dressed up as safe repayment capacity. Uncommitted future equity or unrestricted cash that will be burned to fund operations is not the same as sustainable repayment capacity.

## 8. Collateral and ABL Spreading

For asset-based or working-capital facilities, spreading must go beyond financial statements. The credit file needs collateral reporting and controls.

Important ABL/ARIF concepts include:

- Borrowing base.
- Eligible receivables.
- Eligible inventory.
- Advance rates.
- Concentration limits.
- Dilution from disputes, returns, offsets, and credits.
- AR aging.
- Inventory obsolescence.
- Excess availability.
- Field exams and collateral audits.
- Cash dominion or springing cash dominion.

For an AI spreading pilot, this means a standard income-statement/balance-sheet extraction test is not enough for ABL use cases. AR aging and inventory schedules need their own test scenarios and controls.

## 9. Common Spreading Errors That Matter in Credit

These are the errors most likely to create bad credit analysis even if the OCR appears to work.

| Error | Example | Credit Impact |
| --- | --- | --- |
| Period error | Quarterly revenue treated as annual revenue. | DSCR, leverage, and trend analysis are wrong. |
| Sign error | Parentheses or contra accounts read as positive. | Earnings or equity can be overstated. |
| Scale error | Values in thousands treated as dollars, or vice versa. | Every material ratio is wrong. |
| Gross/net error | Gross receipts mapped as net revenue. | Margin and trend analysis are wrong. |
| Classification error | Current debt mapped as long-term debt. | Liquidity and current ratio are wrong. |
| Entity error | Consolidated parent values used for borrower-only spread. | Repayment source may not match legal borrower. |
| Tax/GAAP error | Taxable income treated as EBITDA. | Cash flow available for debt service is wrong. |
| Duplicate line | Same debt or revenue line included twice. | Debt load or repayment capacity is distorted. |
| Missing schedule | Debt schedule omitted from DSCR calculation. | Required debt service is understated. |
| Unsupported addback | Non-recurring expense added back without evidence. | Cash flow is overstated. |

## 10. What AI Should and Should Not Do

AI can reasonably assist with:

- Extracting values from financial documents.
- Mapping values to a bank-defined spread template.
- Flagging low-confidence or ambiguous fields.
- Linking values back to document evidence.
- Suggesting normalized line-item mappings for review.
- Reducing duplicate keying.

AI should not independently:

- Certify final spread values.
- Determine risk rating.
- Decide covenant compliance.
- Approve addbacks.
- Decide primary source of repayment.
- Approve or decline a loan.
- Replace credit policy or human underwriting judgment.

## 11. How This Changes the Pilot

The pilot should measure both extraction accuracy and credit consequence.

In addition to exact line-item match and dollar-weighted accuracy, the pilot should track:

- Whether DSCR changes enough to alter credit conclusions.
- Whether leverage or liquidity ratios cross policy thresholds.
- Whether material errors affect covenant compliance.
- Whether source documents and page references are complete.
- Whether exceptions are routed before bad values reach final spread data.
- Whether analyst review time improves without weakening judgment.

The strongest test cases are not the neat PDFs. They are the cases where a real analyst would slow down: tax returns, interim statements, scanned statements, multi-period filings, guarantor/global cash flow, and AR/inventory schedules.

## Verified Sources

- FDIC Risk Management Manual of Examination Policies, especially Section 3.2 Loans: https://www.fdic.gov/resources/supervision-and-examinations/examination-policies-manual/
- Federal Reserve Commercial Bank Examination Manual: https://www.federalreserve.gov/publications/supervision_cbem.htm
- OCC Comptroller's Handbook, Commercial Loans: https://www.occ.treas.gov/publications-and-resources/publications/comptrollers-handbook/files/commercial-loans/index-commercial-loans.html
- OCC Comptroller's Handbook, Loan Portfolio Management: https://occ.gov/publications-and-resources/publications/comptrollers-handbook/files/loan-portfolio-management/index-loan-portfolio-management.html
- OCC Comptroller's Handbook, Rating Credit Risk: https://www.occ.treas.gov/publications-and-resources/publications/comptrollers-handbook/files/rating-credit-risk/index-rating-credit-risk.html
- OCC Commercial Credit topic page: https://www.occ.treas.gov/topics/supervision-and-examination/credit/commercial-credit/index-commercial-credit.html
- OCC Asset-Based Lending: https://www.occ.treas.gov/publications-and-resources/publications/comptrollers-handbook/files/asset-based-lending/index-asset-based-lending.html
- OCC Accounts Receivable and Inventory Financing: https://www.occ.gov/topics/supervision-and-examination/credit/commercial-credit/accounts-receivable.html
- FDIC Commercial and Industrial Lending: https://www.fdic.gov/credit/commercial-industrial-lending
- IRS Instructions for Form 1120: https://www.irs.gov/instructions/i1120
- SEC Investor.gov, How to Read a 10-K/10-Q: https://www.investor.gov/introduction-investing/general-resources/news-alerts/alerts-bulletins/how-read
- SEC Investor.gov, Form 10-K: https://www.investor.gov/additional-resources/general-resources/glossary/form-10-k
- SEC Investor.gov, Form 10-Q: https://www.investor.gov/introduction-investing/investing-basics/glossary/form-10-q
- nCino Credit Analysis Suite: https://www.ncino.com/en-US/solutions/credit-analysis
- nCino Automated Spreading: https://www.ncino.com/solutions/automated-spreading

