import assert from 'node:assert/strict';
import test from 'node:test';
import { formatResults, parseCsv, scoreRows, toNumber } from '../src/scorecard.js';

test('parses quoted CSV fields', () => {
  const rows = parseCsv('case_id,notes\nCASE-001,"quoted, note"\n');
  assert.deepEqual(rows, [{ case_id: 'CASE-001', notes: 'quoted, note' }]);
});

test('normalizes common financial number formats', () => {
  assert.equal(toNumber('$1,250.50'), 1250.5);
  assert.equal(toNumber('(1,250)'), -1250);
  assert.equal(toNumber(''), 0);
});

test('scores passing path when all gates are met', () => {
  const results = scoreRows([
    {
      path: 'ncino_automated_spreading',
      case_id: 'CASE-001',
      document_id: 'DOC-001',
      normalized_line: 'revenue',
      material: 'true',
      manual_value: '1000000',
      candidate_value: '1000000',
      manual_minutes: '100',
      candidate_minutes: '60',
      exception_flag: 'false',
      certified: 'true'
    },
    {
      path: 'ncino_automated_spreading',
      case_id: 'CASE-001',
      document_id: 'DOC-001',
      normalized_line: 'cash',
      material: 'true',
      manual_value: '500000',
      candidate_value: '500000',
      manual_minutes: '20',
      candidate_minutes: '10',
      exception_flag: 'false',
      certified: 'true'
    }
  ]);

  assert.equal(results.length, 1);
  assert.equal(results[0].passed, true);
  assert.equal(results[0].uncaughtMaterialErrors, 0);
});

test('fails path with uncaught material error or missing certification', () => {
  const results = scoreRows([
    {
      path: 'salesforce_native_staging',
      case_id: 'CASE-002',
      document_id: 'DOC-002',
      normalized_line: 'ebitda',
      material: 'true',
      manual_value: '300000',
      candidate_value: '250000',
      manual_minutes: '100',
      candidate_minutes: '60',
      exception_flag: 'false',
      certified: 'false',
      error_type: 'mapping'
    }
  ]);

  assert.equal(results[0].passed, false);
  assert.equal(results[0].gateResults.uncaughtMaterialErrors, false);
  assert.equal(results[0].gateResults.certificationRate, false);
  assert.equal(results[0].errors[0].line, 'ebitda');
});

test('treats manual nCino control as baseline rather than time-reduction candidate', () => {
  const results = scoreRows([
    {
      path: 'manual_ncino_control',
      case_id: 'CASE-003',
      document_id: 'DOC-003',
      normalized_line: 'revenue',
      material: 'true',
      manual_value: '1000000',
      candidate_value: '1000000',
      manual_minutes: '100',
      candidate_minutes: '100',
      exception_flag: 'false',
      certified: 'true'
    }
  ]);

  assert.equal(results[0].timeReduction, 0);
  assert.equal(results[0].gateResults.timeReduction, true);
  assert.equal(results[0].passed, true);
});

test('formats failing pilot errors for review', () => {
  const results = scoreRows([
    {
      path: 'ncino_automated_spreading',
      case_id: 'CASE-004',
      document_id: 'DOC-004',
      normalized_line: 'current_liabilities',
      material: 'true',
      manual_value: '1090000',
      candidate_value: '109000',
      manual_minutes: '12',
      candidate_minutes: '7',
      exception_flag: 'false',
      certified: 'true',
      error_type: 'extraction'
    }
  ]);

  const output = formatResults(results);
  assert.match(output, /Passed: no/);
  assert.match(output, /current_liabilities/);
});
