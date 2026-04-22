import { parseSpreadCandidates } from '../src/spreadParser.js';

const evidenceText = [
  'Independent Accountant Report',
  'Borrower: Aster Machine Works LLC',
  'Fiscal year ended: December 31, 2025',
  'This synthetic document is for pilot testing only.',
  '',
  'Income Statement',
  'Revenue: $8,450,000',
  'Cost of Goods Sold: $5,180,000',
  'Gross Profit: $3,270,000',
  'Operating Expenses: $1,940,000',
  'EBITDA: $1,530,000',
  'Interest Expense: $210,000',
  'Debt Service: $720,000'
].join('\n');

const output = parseSpreadCandidates({
  documentId: 'DOC-SYN-1001-AUDIT',
  borrower: 'Aster Machine Works LLC',
  loanOrOpportunity: 'LOAN-SYN-1001',
  statementType: 'income_statement',
  fiscalPeriod: 'FY2025',
  evidenceBlocks: [
    {
      evidenceId: 'EVID-SYN-1001-AUDIT-P1',
      sourcePage: 1,
      rawText: evidenceText
    }
  ]
});

console.log(JSON.stringify(output, null, 2));
