import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseSpreadCandidates } from '../src/spreadParser.js';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const defaultPdfPath = path.join(
  root,
  'data',
  'synthetic',
  'documents',
  'aster-machine-works-fy2025-audited-financials.pdf'
);

const endpoint = normalizeExtractUrl(process.env.EXTRACT_URL || 'https://spread-docling-service.onrender.com/extract');
const apiKey = process.env.DOCLING_API_KEY || process.env.SPREAD_DOCLING_API_KEY;
const pdfPath = process.env.INCOME_STATEMENT_PDF || defaultPdfPath;
const extractionEngine = process.env.INCOME_PARSE_EXTRACTION_ENGINE || 'auto';

const expectedValues = {
  revenue: 8450000,
  cost_of_goods_sold: 5180000,
  gross_profit: 3270000,
  operating_expenses: 1940000,
  ebitda: 1530000,
  interest_expense: 210000,
  debt_service: 720000
};

if (!apiKey) {
  console.error('Missing DOCLING_API_KEY or SPREAD_DOCLING_API_KEY.');
  console.error('Example: DOCLING_API_KEY=... npm run test:extract:parse:income');
  process.exit(2);
}

function normalizeExtractUrl(value) {
  const trimmed = value.trim().replace(/\/+$/, '');
  return trimmed.endsWith('/extract') ? trimmed : `${trimmed}/extract`;
}

const pdf = await readFile(pdfPath);
const form = new FormData();
form.append('file', new Blob([pdf], { type: 'application/pdf' }), path.basename(pdfPath));

const started = Date.now();
const response = await fetch(endpoint, {
  method: 'POST',
  headers: {
    'Api-Key': apiKey,
    'Extraction-Engine': extractionEngine
  },
  body: form
});
const elapsedMs = Date.now() - started;
const bodyText = await response.text();

if (!response.ok) {
  console.error(`Income statement extract-and-parse request failed: HTTP ${response.status}`);
  console.error(bodyText.slice(0, 2000));
  process.exit(1);
}

let extractionPayload;
try {
  extractionPayload = JSON.parse(bodyText);
} catch (error) {
  console.error('Extraction response was not JSON.');
  console.error(bodyText.slice(0, 2000));
  process.exit(1);
}

const markdown = extractionPayload.tables || '';
const parserOutput = parseSpreadCandidates({
  documentId: 'DOC-SYN-1001-AUDIT',
  borrower: 'Aster Machine Works LLC',
  loanOrOpportunity: 'LOAN-SYN-1001',
  statementType: 'income_statement',
  fiscalPeriod: 'FY2025',
  evidenceBlocks: [
    {
      evidenceId: extractionPayload.job_id || 'EVID-SYN-1001-AUDIT-RENDER',
      sourcePage: 1,
      rawText: markdown
    }
  ]
});

const byLine = new Map(parserOutput.candidates.map((candidate) => [candidate.normalized_line, candidate]));
const mismatches = Object.entries(expectedValues)
  .filter(([line, expectedValue]) => byLine.get(line)?.normalized_value !== expectedValue)
  .map(([line, expectedValue]) => ({
    line,
    expectedValue,
    actualValue: byLine.get(line)?.normalized_value ?? null
  }));
const passed = mismatches.length === 0 && parserOutput.exceptions.length === 0;

console.log(JSON.stringify({
  passed,
  endpoint,
  pdf: path.relative(root, pdfPath),
  requestedEngine: extractionEngine,
  responseEngine: extractionPayload.engine,
  conversionStatus: extractionPayload.conversion_status,
  elapsedMs,
  serviceElapsedSeconds: extractionPayload.elapsed_seconds,
  jobId: extractionPayload.job_id,
  pageCount: extractionPayload.page_count,
  markdownLength: markdown.length,
  candidateCount: parserOutput.candidates.length,
  exceptionCount: parserOutput.exceptions.length,
  mismatches,
  candidates: parserOutput.candidates
}, null, 2));

if (!passed) {
  console.error('\nExtracted Markdown preview:');
  console.error(markdown.slice(0, 4000));
  process.exit(1);
}
