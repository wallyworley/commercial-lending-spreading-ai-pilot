export const PARSER_VERSION = 'deterministic-synthetic-v1';

export const DEFAULT_LINE_MAPPINGS = [
  { normalizedLine: 'revenue', labels: ['revenue', 'sales', 'net revenue', 'gross receipts or sales'] },
  { normalizedLine: 'cost_of_goods_sold', labels: ['cost of goods sold', 'cogs'] },
  { normalizedLine: 'gross_profit', labels: ['gross profit'] },
  { normalizedLine: 'operating_expenses', labels: ['operating expenses', 'total deductions'] },
  { normalizedLine: 'ebitda', labels: ['ebitda', 'operating ebitda', 'adjusted ebitda'] },
  { normalizedLine: 'interest_expense', labels: ['interest expense'] },
  { normalizedLine: 'debt_service', labels: ['debt service'] },
  { normalizedLine: 'cash', labels: ['cash', 'cash and cash equivalents'] },
  { normalizedLine: 'current_assets', labels: ['current assets'] },
  { normalizedLine: 'current_liabilities', labels: ['current liabilities'] },
  { normalizedLine: 'total_liabilities', labels: ['total liabilities'] },
  { normalizedLine: 'net_worth_equity', labels: ['net worth / equity', 'equity', 'shareholder equity', 'stockholders equity'] }
];

export function parseSpreadCandidates({
  documentId,
  borrower = '',
  loanOrOpportunity = '',
  statementType,
  fiscalPeriod,
  evidenceBlocks,
  lineMappings = DEFAULT_LINE_MAPPINGS
}) {
  assertRequired(documentId, 'documentId');
  assertRequired(statementType, 'statementType');
  assertRequired(fiscalPeriod, 'fiscalPeriod');
  if (!Array.isArray(evidenceBlocks) || evidenceBlocks.length === 0) {
    throw new Error('evidenceBlocks must contain at least one evidence block');
  }

  const candidates = [];
  const exceptions = [];
  const seenLines = new Set();

  for (const block of evidenceBlocks) {
    const rawText = String(block.rawText ?? block.raw_text ?? '');
    const sourcePage = Number(block.sourcePage ?? block.source_page ?? 1);
    const evidenceId = block.evidenceId ?? block.evidence_id;

    for (const rawLine of rawText.split(/\r?\n/)) {
      const parsedLine = parseEvidenceLine(rawLine);
      if (!parsedLine) continue;

      const mapping = findMapping(parsedLine.label, lineMappings);
      if (!mapping) continue;

      if (seenLines.has(mapping.normalizedLine)) {
        exceptions.push({
          reason: `Duplicate candidate for ${mapping.normalizedLine}`,
          severity: 'warning',
          evidence_id: evidenceId,
          source_page: sourcePage,
          raw_text: rawLine.trim()
        });
        continue;
      }

      seenLines.add(mapping.normalizedLine);
      candidates.push({
        normalized_line: mapping.normalizedLine,
        raw_label: parsedLine.label,
        raw_value: parsedLine.valueText,
        normalized_value: parseFinancialNumber(parsedLine.valueText),
        evidence_id: evidenceId,
        source_page: sourcePage,
        source_coordinates: block.sourceCoordinates ?? block.source_coordinates ?? '',
        confidence: confidenceForMatch(parsedLine.label, mapping),
        exception_reason: null,
        status: 'draft'
      });
    }
  }

  return {
    document_id: documentId,
    borrower,
    loan_or_opportunity: loanOrOpportunity,
    statement_type: statementType,
    fiscal_period: fiscalPeriod,
    parser_version: PARSER_VERSION,
    candidates,
    exceptions
  };
}

export function parseEvidenceLine(line) {
  const trimmed = String(line ?? '').trim();
  if (!trimmed) return null;

  const match = trimmed.match(/^(.+?)(?::\s*|\s{2,}|\s+(?=\$|\())(\(?\$?[\d,]+(?:\.\d{1,2})?\)?)/);
  if (!match) return null;

  return {
    label: match[1].trim(),
    valueText: match[2].trim()
  };
}

export function parseFinancialNumber(value) {
  const raw = String(value ?? '').trim();
  const negative = raw.startsWith('(') && raw.endsWith(')');
  const normalized = raw.replace(/[,$()\s]/g, '');
  const number = Number(normalized);
  if (!Number.isFinite(number)) {
    throw new Error(`Unable to parse financial value: ${value}`);
  }
  return negative ? -number : number;
}

function findMapping(label, lineMappings) {
  const normalizedLabel = normalizeLabel(label);
  return lineMappings.find((mapping) => mapping.labels.some((candidate) => normalizeLabel(candidate) === normalizedLabel));
}

function confidenceForMatch(label, mapping) {
  const normalizedLabel = normalizeLabel(label);
  if (mapping.labels.some((candidate) => normalizeLabel(candidate) === normalizedLabel)) return 0.96;
  return 0.75;
}

function normalizeLabel(value) {
  return String(value ?? '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()
    .replace(/\s+/g, ' ');
}

function assertRequired(value, name) {
  if (!String(value ?? '').trim()) {
    throw new Error(`${name} is required`);
  }
}
