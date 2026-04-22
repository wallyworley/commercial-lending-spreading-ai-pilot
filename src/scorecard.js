import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

export const DEFAULT_GATES = {
  exactMatchRate: 0.98,
  dollarWeightedAccuracy: 0.995,
  maxUncaughtMaterialErrors: 0,
  timeReduction: 0.30,
  certificationRate: 1
};

export function parseCsv(text) {
  const rows = [];
  let row = [];
  let field = '';
  let inQuotes = false;

  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];
    const next = text[index + 1];

    if (char === '"' && inQuotes && next === '"') {
      field += '"';
      index += 1;
      continue;
    }

    if (char === '"') {
      inQuotes = !inQuotes;
      continue;
    }

    if (char === ',' && !inQuotes) {
      row.push(field);
      field = '';
      continue;
    }

    if ((char === '\n' || char === '\r') && !inQuotes) {
      if (char === '\r' && next === '\n') index += 1;
      row.push(field);
      if (row.some((value) => value.trim() !== '')) rows.push(row);
      row = [];
      field = '';
      continue;
    }

    field += char;
  }

  if (field.length > 0 || row.length > 0) {
    row.push(field);
    if (row.some((value) => value.trim() !== '')) rows.push(row);
  }

  if (rows.length === 0) return [];
  const headers = rows[0].map((header) => header.trim());
  return rows.slice(1).map((values) => Object.fromEntries(headers.map((header, index) => [header, values[index] ?? ''])));
}

export function toBoolean(value) {
  return ['true', 'yes', 'y', '1'].includes(String(value ?? '').trim().toLowerCase());
}

export function toNumber(value) {
  const raw = String(value ?? '').trim();
  if (!raw) return 0;
  const negative = raw.startsWith('(') && raw.endsWith(')');
  const normalized = raw.replace(/[,$%()\s]/g, '');
  const number = Number(normalized);
  if (!Number.isFinite(number)) return 0;
  return negative ? -number : number;
}

export function scoreRows(rows, gates = DEFAULT_GATES) {
  const byPath = new Map();

  for (const row of rows) {
    const path = row.path || 'unknown';
    const bucket = byPath.get(path) ?? {
      path,
      rowCount: 0,
      exactMatches: 0,
      absoluteManualValue: 0,
      absoluteError: 0,
      manualMinutes: 0,
      candidateMinutes: 0,
      materialRows: 0,
      uncaughtMaterialErrors: 0,
      certifiedRequiredRows: 0,
      certifiedRows: 0,
      errors: []
    };

    const manualValue = toNumber(row.manual_value);
    const candidateValue = toNumber(row.candidate_value);
    const exact = manualValue === candidateValue;
    const material = toBoolean(row.material);
    const exceptionFlag = toBoolean(row.exception_flag);
    const certified = toBoolean(row.certified);
    const error = Math.abs(manualValue - candidateValue);

    bucket.rowCount += 1;
    if (exact) bucket.exactMatches += 1;
    bucket.absoluteManualValue += Math.abs(manualValue);
    bucket.absoluteError += error;
    bucket.manualMinutes += toNumber(row.manual_minutes);
    bucket.candidateMinutes += toNumber(row.candidate_minutes);

    if (material) {
      bucket.materialRows += 1;
      bucket.certifiedRequiredRows += 1;
      if (certified) bucket.certifiedRows += 1;
      if (!exact && !exceptionFlag) {
        bucket.uncaughtMaterialErrors += 1;
        bucket.errors.push({
          caseId: row.case_id,
          documentId: row.document_id,
          line: row.normalized_line,
          manualValue,
          candidateValue,
          errorType: row.error_type || 'unclassified'
        });
      }
    }

    byPath.set(path, bucket);
  }

  return [...byPath.values()].map((bucket) => {
    const exactMatchRate = bucket.rowCount > 0 ? bucket.exactMatches / bucket.rowCount : 0;
    const dollarWeightedAccuracy = bucket.absoluteManualValue > 0
      ? Math.max(0, 1 - (bucket.absoluteError / bucket.absoluteManualValue))
      : exactMatchRate;
    const timeReduction = bucket.manualMinutes > 0
      ? Math.max(0, 1 - (bucket.candidateMinutes / bucket.manualMinutes))
      : 0;
    const certificationRate = bucket.certifiedRequiredRows > 0
      ? bucket.certifiedRows / bucket.certifiedRequiredRows
      : 1;

    const isManualControl = bucket.path === 'manual_ncino_control';
    const gateResults = {
      exactMatchRate: exactMatchRate >= gates.exactMatchRate,
      dollarWeightedAccuracy: dollarWeightedAccuracy >= gates.dollarWeightedAccuracy,
      uncaughtMaterialErrors: bucket.uncaughtMaterialErrors <= gates.maxUncaughtMaterialErrors,
      timeReduction: isManualControl ? true : timeReduction >= gates.timeReduction,
      certificationRate: certificationRate >= gates.certificationRate
    };

    return {
      ...bucket,
      exactMatchRate,
      dollarWeightedAccuracy,
      timeReduction,
      certificationRate,
      gateResults,
      passed: Object.values(gateResults).every(Boolean)
    };
  });
}

export function formatPercent(value) {
  return `${(value * 100).toFixed(2)}%`;
}

export function formatResults(results) {
  const lines = ['Pilot scorecard results', ''];
  for (const result of results) {
    lines.push(`Path: ${result.path}`);
    lines.push(`  Passed: ${result.passed ? 'yes' : 'no'}`);
    lines.push(`  Exact match rate: ${formatPercent(result.exactMatchRate)}`);
    lines.push(`  Dollar-weighted accuracy: ${formatPercent(result.dollarWeightedAccuracy)}`);
    lines.push(`  Time reduction: ${formatPercent(result.timeReduction)}`);
    lines.push(`  Certification rate: ${formatPercent(result.certificationRate)}`);
    lines.push(`  Uncaught material errors: ${result.uncaughtMaterialErrors}`);
    if (result.errors.length > 0) {
      lines.push('  Error examples:');
      for (const error of result.errors.slice(0, 5)) {
        lines.push(`    - ${error.caseId}/${error.documentId}/${error.line}: ${error.manualValue} vs ${error.candidateValue} (${error.errorType})`);
      }
    }
    lines.push('');
  }
  return lines.join('\n');
}

async function main(argv) {
  const csvPath = argv[2];
  if (!csvPath) {
    console.error('Usage: npm run scorecard -- <pilot-scorecard.csv> [--json]');
    process.exitCode = 2;
    return;
  }

  const text = await readFile(csvPath, 'utf8');
  const results = scoreRows(parseCsv(text));
  const asJson = argv.includes('--json');
  const noExitCode = argv.includes('--no-exit-code');
  console.log(asJson ? JSON.stringify(results, null, 2) : formatResults(results));
  if (!noExitCode && results.some((result) => !result.passed)) process.exitCode = 1;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  await main(process.argv);
}
