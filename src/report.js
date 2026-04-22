import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { formatPercent, parseCsv, scoreRows, toBoolean, toNumber } from './scorecard.js';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

function escapeHtml(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function formatCurrency(value) {
  return Number(value ?? 0).toLocaleString('en-US', {
    style: 'currency',
    currency: 'USD',
    maximumFractionDigits: 0
  });
}

function recommendationFor(results) {
  const candidates = results.filter((result) => result.path !== 'manual_ncino_control');
  if (candidates.some((result) => result.passed)) {
    return 'Proceed only with the passing path, subject to credit, model-risk, information-security, compliance, and vendor-documentation approval.';
  }
  if (candidates.length > 0) {
    return 'Do not proceed to production. Classify failed cases, request vendor evidence where applicable, remediate the pilot configuration, and retest the affected scenario groups.';
  }
  return 'Use the manual control path as the baseline before adding AI candidate paths.';
}

function pathLabel(pathName) {
  return {
    ncino_automated_spreading: 'nCino Automated Spreading',
    salesforce_native_staging: 'Salesforce-Native Staging',
    manual_ncino_control: 'Manual nCino Control'
  }[pathName] ?? pathName;
}

function gateName(name) {
  return {
    exactMatchRate: 'Exact Match >= 98%',
    dollarWeightedAccuracy: 'Dollar Accuracy >= 99.5%',
    uncaughtMaterialErrors: 'No Uncaught Material Errors',
    timeReduction: 'Time Reduction >= 30%',
    certificationRate: 'Certification = 100%'
  }[name] ?? name;
}

function statusPill(passed) {
  return `<span class="pill ${passed ? 'pass' : 'fail'}">${passed ? 'Pass' : 'Fail'}</span>`;
}

function summaryCards(results) {
  return results.map((result) => `
    <section class="card">
      <div class="card-title">
        <h2>${escapeHtml(pathLabel(result.path))}</h2>
        ${statusPill(result.passed)}
      </div>
      <dl class="metrics">
        <div><dt>Exact match</dt><dd>${formatPercent(result.exactMatchRate)}</dd></div>
        <div><dt>Dollar accuracy</dt><dd>${formatPercent(result.dollarWeightedAccuracy)}</dd></div>
        <div><dt>Time reduction</dt><dd>${formatPercent(result.timeReduction)}</dd></div>
        <div><dt>Certification</dt><dd>${formatPercent(result.certificationRate)}</dd></div>
        <div><dt>Material errors</dt><dd>${result.uncaughtMaterialErrors}</dd></div>
      </dl>
    </section>
  `).join('');
}

function gateRows(results) {
  return results.flatMap((result) => Object.entries(result.gateResults).map(([gate, passed]) => `
    <tr>
      <td>${escapeHtml(pathLabel(result.path))}</td>
      <td>${escapeHtml(gateName(gate))}</td>
      <td>${statusPill(passed)}</td>
    </tr>
  `)).join('');
}

function materialErrorRows(results) {
  const rows = results.flatMap((result) => result.errors.map((error) => ({ ...error, path: result.path })));
  if (rows.length === 0) {
    return '<tr><td colspan="7">No uncaught material errors.</td></tr>';
  }
  return rows.map((error) => `
    <tr>
      <td>${escapeHtml(pathLabel(error.path))}</td>
      <td>${escapeHtml(error.caseId)}</td>
      <td>${escapeHtml(error.documentId)}</td>
      <td>${escapeHtml(error.line)}</td>
      <td>${formatCurrency(error.manualValue)}</td>
      <td>${formatCurrency(error.candidateValue)}</td>
      <td>${escapeHtml(error.errorType)}</td>
    </tr>
  `).join('');
}

function topMismatchRows(rows) {
  const mismatches = rows
    .map((row) => {
      const manualValue = toNumber(row.manual_value);
      const candidateValue = toNumber(row.candidate_value);
      return {
        ...row,
        manualValue,
        candidateValue,
        absoluteError: Math.abs(manualValue - candidateValue),
        exceptionFlag: toBoolean(row.exception_flag)
      };
    })
    .filter((row) => row.absoluteError > 0)
    .sort((left, right) => right.absoluteError - left.absoluteError)
    .slice(0, 20);

  if (mismatches.length === 0) {
    return '<tr><td colspan="8">No mismatches found.</td></tr>';
  }

  return mismatches.map((row) => `
    <tr>
      <td>${escapeHtml(pathLabel(row.path))}</td>
      <td>${escapeHtml(row.case_id)}</td>
      <td>${escapeHtml(row.document_id)}</td>
      <td>${escapeHtml(row.normalized_line)}</td>
      <td>${formatCurrency(row.manualValue)}</td>
      <td>${formatCurrency(row.candidateValue)}</td>
      <td>${formatCurrency(row.absoluteError)}</td>
      <td>${row.exceptionFlag ? 'Yes' : 'No'}</td>
    </tr>
  `).join('');
}

function documentRows(corpusRows) {
  if (corpusRows.length === 0) {
    return '<tr><td colspan="7">No document corpus file found next to the scorecard.</td></tr>';
  }

  return corpusRows.map((row) => {
    const fileRef = row.file_location_reference ?? '';
    const fileLink = fileRef.startsWith('data/')
      ? `<a href="../${escapeHtml(fileRef.replace(/^data\//, ''))}">${escapeHtml(fileRef)}</a>`
      : escapeHtml(fileRef);
    return `
      <tr>
        <td>${escapeHtml(row.document_id)}</td>
        <td>${escapeHtml(row.borrower)}</td>
        <td>${escapeHtml(row.document_type)}</td>
        <td>${escapeHtml(row.fiscal_period)}</td>
        <td>${escapeHtml(row.scenario_type)}</td>
        <td>${fileLink}</td>
        <td>${escapeHtml(row.notes)}</td>
      </tr>
    `;
  }).join('');
}

async function readOptionalCsv(csvPath) {
  try {
    return parseCsv(await readFile(csvPath, 'utf8'));
  } catch (error) {
    if (error.code === 'ENOENT') return [];
    throw error;
  }
}

function buildHtml({ scorecardPath, rows, results, corpusRows }) {
  const generatedAt = new Date().toISOString();
  const escapedPath = escapeHtml(path.relative(root, scorecardPath));
  const recommendation = recommendationFor(results);

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>C&I Financial Spreading AI Pilot Report</title>
  <style>
    :root {
      color-scheme: light;
      --ink: #17202a;
      --muted: #5b6470;
      --line: #d9dee5;
      --panel: #ffffff;
      --bg: #f5f7fa;
      --pass: #0f7b4f;
      --fail: #b3261e;
      --warn: #8a6100;
      --accent: #255e9c;
    }

    * { box-sizing: border-box; }

    body {
      margin: 0;
      font-family: Arial, Helvetica, sans-serif;
      line-height: 1.45;
      color: var(--ink);
      background: var(--bg);
    }

    header {
      padding: 32px;
      background: #ffffff;
      border-bottom: 1px solid var(--line);
    }

    main {
      max-width: 1200px;
      margin: 0 auto;
      padding: 28px;
    }

    h1, h2, h3 { margin: 0 0 12px; }

    h1 { font-size: 30px; }

    h2 { font-size: 20px; }

    p { margin: 0 0 14px; color: var(--muted); }

    .source {
      color: var(--muted);
      font-size: 14px;
    }

    .recommendation {
      margin: 0 0 24px;
      padding: 18px;
      background: #fff8e1;
      border: 1px solid #ead189;
      border-radius: 8px;
      color: var(--ink);
    }

    .cards {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
      gap: 16px;
      margin-bottom: 24px;
    }

    .card {
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 8px;
      padding: 18px;
    }

    .card-title {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 12px;
      margin-bottom: 12px;
    }

    .metrics {
      display: grid;
      gap: 10px;
      margin: 0;
    }

    .metrics div {
      display: flex;
      justify-content: space-between;
      gap: 12px;
      border-bottom: 1px solid #edf0f4;
      padding-bottom: 8px;
    }

    .metrics dt { color: var(--muted); }

    .metrics dd {
      margin: 0;
      font-weight: 700;
    }

    .pill {
      display: inline-block;
      min-width: 54px;
      padding: 4px 8px;
      border-radius: 8px;
      color: #ffffff;
      font-size: 12px;
      font-weight: 700;
      text-align: center;
    }

    .pill.pass { background: var(--pass); }

    .pill.fail { background: var(--fail); }

    section.table-section {
      margin: 0 0 24px;
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 8px;
      overflow: hidden;
    }

    section.table-section h2 {
      padding: 18px 18px 0;
    }

    .table-wrap {
      overflow-x: auto;
      padding: 14px 18px 18px;
    }

    table {
      width: 100%;
      border-collapse: collapse;
      font-size: 14px;
    }

    th, td {
      padding: 10px;
      border-bottom: 1px solid #edf0f4;
      text-align: left;
      vertical-align: top;
      white-space: nowrap;
    }

    th {
      color: var(--muted);
      font-size: 12px;
      text-transform: uppercase;
      letter-spacing: 0;
    }

    a { color: var(--accent); }

    footer {
      color: var(--muted);
      font-size: 13px;
      padding: 0 32px 28px;
      text-align: center;
    }
  </style>
</head>
<body>
  <header>
    <h1>C&I Financial Spreading AI Pilot Report</h1>
    <p>Draft-only AI spreading evidence for nCino Automated Spreading, Salesforce-native staging, and manual nCino control.</p>
    <div class="source">Generated: ${escapeHtml(generatedAt)} · Scorecard: ${escapedPath}</div>
  </header>
  <main>
    <div class="recommendation"><strong>Recommendation:</strong> ${escapeHtml(recommendation)}</div>

    <div class="cards">
      ${summaryCards(results)}
    </div>

    <section class="table-section">
      <h2>Gate Results</h2>
      <div class="table-wrap">
        <table>
          <thead><tr><th>Path</th><th>Gate</th><th>Status</th></tr></thead>
          <tbody>${gateRows(results)}</tbody>
        </table>
      </div>
    </section>

    <section class="table-section">
      <h2>Uncaught Material Errors</h2>
      <div class="table-wrap">
        <table>
          <thead><tr><th>Path</th><th>Case</th><th>Document</th><th>Line</th><th>Manual</th><th>Candidate</th><th>Error Type</th></tr></thead>
          <tbody>${materialErrorRows(results)}</tbody>
        </table>
      </div>
    </section>

    <section class="table-section">
      <h2>Largest Mismatches</h2>
      <div class="table-wrap">
        <table>
          <thead><tr><th>Path</th><th>Case</th><th>Document</th><th>Line</th><th>Manual</th><th>Candidate</th><th>Error</th><th>Exception Routed</th></tr></thead>
          <tbody>${topMismatchRows(rows)}</tbody>
        </table>
      </div>
    </section>

    <section class="table-section">
      <h2>Document Corpus</h2>
      <div class="table-wrap">
        <table>
          <thead><tr><th>Document</th><th>Borrower</th><th>Type</th><th>Period</th><th>Scenario</th><th>File</th><th>Notes</th></tr></thead>
          <tbody>${documentRows(corpusRows)}</tbody>
        </table>
      </div>
    </section>
  </main>
  <footer>
    Synthetic data is fictional and for pilot workflow testing only. Real production decisions require bank-approved pilot evidence and Salesforce/nCino source validation.
  </footer>
</body>
</html>`;
}

async function main(argv) {
  const scorecardArg = argv[2];
  if (!scorecardArg) {
    console.error('Usage: npm run report -- <pilot-scorecard.csv> [output.html]');
    process.exitCode = 2;
    return;
  }

  const scorecardPath = path.resolve(process.cwd(), scorecardArg);
  const outputPath = path.resolve(process.cwd(), argv[3] ?? path.join('reports', 'pilot-scorecard-report.html'));
  const rows = parseCsv(await readFile(scorecardPath, 'utf8'));
  const results = scoreRows(rows);
  const corpusPath = path.join(path.dirname(scorecardPath), 'document-corpus.csv');
  const corpusRows = await readOptionalCsv(corpusPath);
  const html = buildHtml({ scorecardPath, rows, results, corpusRows });

  await mkdir(path.dirname(outputPath), { recursive: true });
  await writeFile(outputPath, html, 'utf8');
  console.log(`Report written to ${path.relative(process.cwd(), outputPath)}`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  await main(process.argv);
}

