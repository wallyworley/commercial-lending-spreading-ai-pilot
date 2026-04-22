import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const defaultPdfPath = path.join(
  root,
  'data',
  'synthetic',
  'documents',
  'cobalt-components-fy2025-poor-scan.pdf'
);

const endpoint = normalizeExtractUrl(process.env.EXTRACT_URL || 'https://spread-docling-service.onrender.com/extract');
const apiKey = process.env.DOCLING_API_KEY || process.env.SPREAD_DOCLING_API_KEY;
const pdfPath = process.env.POOR_SCAN_PDF || defaultPdfPath;
const extractionEngine = process.env.POOR_SCAN_EXTRACTION_ENGINE || 'docling';
const timeoutMs = Number(process.env.POOR_SCAN_TIMEOUT_MS || 300000);

const expectedTerms = [
  'Cobalt Components Co.',
  'LOW QUALITY SCAN SIMULATION',
  'Revenue',
  '4,980,000',
  'EBITDA',
  '620,000',
  'Current Liabilities',
  '1,090,000',
  'Total Liabilities',
  '3,700,000',
  'Equity',
  '1,050,000'
];

if (!apiKey) {
  console.error('Missing DOCLING_API_KEY or SPREAD_DOCLING_API_KEY.');
  console.error('Example: DOCLING_API_KEY=... npm run test:extract:poor-scan');
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
const controller = new AbortController();
const timeout = setTimeout(() => controller.abort(), timeoutMs);
let response;
try {
  response = await fetch(endpoint, {
    method: 'POST',
    headers: {
      'Api-Key': apiKey,
      'Extraction-Engine': extractionEngine
    },
    body: form,
    signal: controller.signal
  });
} catch (error) {
  const elapsedMs = Date.now() - started;
  console.error(`Poor-scan extraction request failed before response headers after ${elapsedMs}ms.`);
  console.error(`Requested engine: ${extractionEngine}`);
  console.error(`Timeout setting: ${timeoutMs}ms`);
  console.error(`Error: ${error.cause?.code || error.name || error.message}`);
  if (extractionEngine === 'docling') {
    console.error('\nThe forced Docling/OCR lane is taking longer than this HTTP smoke test allows.');
    console.error('That confirms the native PDF lane works, while Docling needs a larger runtime or an async/background job pattern.');
  }
  process.exit(1);
} finally {
  clearTimeout(timeout);
}
const elapsedMs = Date.now() - started;
const bodyText = await response.text();

if (!response.ok) {
  console.error(`Poor-scan extraction request failed: HTTP ${response.status}`);
  console.error(bodyText.slice(0, 2000));
  if (response.status === 502 && extractionEngine === 'docling') {
    console.error('\nThe API route is reachable, but the forced Docling path is still failing on Render.');
    console.error('Check Render logs for worker timeout or memory/OOM during converter initialization.');
  }
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
const expectedEngineMismatch = extractionEngine !== 'auto' && payload.engine !== extractionEngine;
const passed = missingTerms.length === 0 && !expectedEngineMismatch;

console.log(JSON.stringify({
  passed,
  endpoint,
  pdf: path.relative(root, pdfPath),
  requestedEngine: extractionEngine,
  responseEngine: payload.engine,
  conversionStatus: payload.conversion_status,
  elapsedMs,
  timeoutMs,
  serviceElapsedSeconds: payload.elapsed_seconds,
  jobId: payload.job_id,
  pageCount: payload.page_count,
  markdownLength: markdown.length,
  missingTerms,
  expectedEngineMismatch
}, null, 2));

if (!passed) {
  console.error('\nExtracted Markdown preview:');
  console.error(markdown.slice(0, 4000));
  process.exit(1);
}
