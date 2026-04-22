import assert from 'node:assert/strict';
import test from 'node:test';
import {
  parseEvidenceLine,
  parseFinancialNumber,
  parseSpreadCandidates
} from '../src/spreadParser.js';

test('parses financial values from common statement formats', () => {
  assert.equal(parseFinancialNumber('$8,450,000'), 8450000);
  assert.equal(parseFinancialNumber('1,090,000'), 1090000);
  assert.equal(parseFinancialNumber('($180,000)'), -180000);
});

test('parses colon and whitespace separated evidence lines', () => {
  assert.deepEqual(parseEvidenceLine('Revenue: $8,450,000'), {
    label: 'Revenue',
    valueText: '$8,450,000'
  });
  assert.deepEqual(parseEvidenceLine('Current Liabilities $1,090,000'), {
    label: 'Current Liabilities',
    valueText: '$1,090,000'
  });
});

test('creates draft spread candidates from synthetic income statement evidence', () => {
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
        rawText: [
          'Income Statement',
          'Revenue: $8,450,000',
          'Cost of Goods Sold: $5,180,000',
          'Gross Profit: $3,270,000',
          'Operating Expenses: $1,940,000',
          'EBITDA: $1,530,000',
          'Interest Expense: $210,000',
          'Debt Service: $720,000'
        ].join('\n')
      }
    ]
  });

  assert.equal(output.document_id, 'DOC-SYN-1001-AUDIT');
  assert.equal(output.statement_type, 'income_statement');
  assert.equal(output.exceptions.length, 0);
  assert.equal(output.candidates.length, 7);

  const byLine = new Map(output.candidates.map((candidate) => [candidate.normalized_line, candidate]));
  assert.equal(byLine.get('revenue').normalized_value, 8450000);
  assert.equal(byLine.get('cost_of_goods_sold').normalized_value, 5180000);
  assert.equal(byLine.get('gross_profit').normalized_value, 3270000);
  assert.equal(byLine.get('operating_expenses').normalized_value, 1940000);
  assert.equal(byLine.get('ebitda').normalized_value, 1530000);
  assert.equal(byLine.get('interest_expense').normalized_value, 210000);
  assert.equal(byLine.get('debt_service').normalized_value, 720000);
  assert.equal(byLine.get('revenue').evidence_id, 'EVID-SYN-1001-AUDIT-P1');
  assert.equal(byLine.get('revenue').status, 'draft');
});

test('routes duplicate spread candidates to exceptions', () => {
  const output = parseSpreadCandidates({
    documentId: 'DOC-SYN-1001-AUDIT',
    statementType: 'income_statement',
    fiscalPeriod: 'FY2025',
    evidenceBlocks: [
      {
        evidenceId: 'EVID-SYN-1001-AUDIT-P1',
        sourcePage: 1,
        rawText: [
          'Revenue: $8,450,000',
          'Revenue: $8,460,000'
        ].join('\n')
      }
    ]
  });

  assert.equal(output.candidates.length, 1);
  assert.equal(output.exceptions.length, 1);
  assert.match(output.exceptions[0].reason, /Duplicate candidate for revenue/);
});
