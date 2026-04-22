import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

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

const expectedTerms = [
  'Income Statement',
  'Revenue',
  '8,450,000',
  'Cost of Goods Sold',
  '5,180,000',
  'Gross Profit',
  '3,270,000',
  'EBITDA',
  '1,530,000',
  'Debt Service',
  '720,000'
];

if (!apiKey) {
  console.error('Missing DOCLING_API_KEY or SPREAD_DOCLING_API_KEY.');
  console.error('Example: DOCLING_API_KEY=... npm run test:extract:income');
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
    'Api-Key': apiKey
  },
  body: form
});
const elapsedMs = Date.now() - started;
const bodyText = await response.text();

if (!response.ok) {
  console.error(`Extraction request failed: HTTP ${response.status}`);
  console.error(bodyText.slice(0, 2000));
  process.exit(1);
}

let payload;
try {
  payload = JSON.parse(bodyText);
} catch (error) {
  console.error('Extraction response was not JSON.');
  console.error(bodyText.slice(0, 2000));
  process.exit(1);
}

const markdown = payload.tables || '';
const missingTerms = expectedTerms.filter((term) => !markdown.includes(term));
const passed = missingTerms.length === 0;

console.log(JSON.stringify({
  passed,
  endpoint,
  pdf: path.relative(root, pdfPath),
  elapsedMs,
  jobId: payload.job_id,
  pageCount: payload.page_count,
  markdownLength: markdown.length,
  missingTerms
}, null, 2));

if (!passed) {
  console.error('\nExtracted Markdown preview:');
  console.error(markdown.slice(0, 4000));
  process.exit(1);
}
