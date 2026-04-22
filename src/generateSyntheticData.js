import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const outputDir = path.join(root, 'data', 'synthetic');
const documentDir = path.join(outputDir, 'documents');

const borrowers = [
  {
    borrower: 'Aster Machine Works LLC',
    loan: 'LOAN-SYN-1001',
    documents: [
      {
        id: 'DOC-SYN-1001-AUDIT',
        type: 'audited_financials',
        statementType: 'income_statement',
        fiscalPeriod: 'FY2025',
        scenario: 'clean_native_pdf',
        file: 'aster-machine-works-fy2025-audited-financials.pdf',
        title: 'Aster Machine Works LLC - Audited Financial Statements',
        pages: [
          [
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
          ],
          [
            'Balance Sheet',
            'Cash: $690,000',
            'Accounts Receivable: $1,280,000',
            'Inventory: $2,110,000',
            'Current Assets: $4,080,000',
            'Current Liabilities: $1,740,000',
            'Total Liabilities: $4,950,000',
            'Net Worth / Equity: $3,620,000'
          ]
        ],
        lines: {
          revenue: 8450000,
          ebitda: 1530000,
          debt_service: 720000,
          cash: 690000,
          current_assets: 4080000,
          current_liabilities: 1740000,
          total_liabilities: 4950000,
          net_worth_equity: 3620000
        }
      },
      {
        id: 'DOC-SYN-1001-TAX',
        type: 'tax_return',
        statementType: 'tax_return',
        fiscalPeriod: 'FY2025',
        scenario: 'tax_return',
        file: 'aster-machine-works-2025-form-1120.pdf',
        title: 'Aster Machine Works LLC - Synthetic Form 1120 Extract',
        pages: [
          [
            'U.S. Corporation Income Tax Return - Synthetic',
            'Form 1120 style training example',
            'Borrower: Aster Machine Works LLC',
            'Tax year: 2025',
            '',
            'Line 1a Gross receipts or sales: $8,610,000',
            'Line 2 Cost of goods sold: $5,240,000',
            'Line 11 Total income: $3,370,000',
            'Line 26 Total deductions: $2,140,000',
            'Line 28 Taxable income before NOL: $1,230,000'
          ]
        ],
        lines: {
          revenue: 8610000,
          ebitda: 1440000,
          cash: 690000,
          total_liabilities: 4950000
        }
      }
    ]
  },
  {
    borrower: 'Bright Harbor Foods Inc.',
    loan: 'LOAN-SYN-1002',
    documents: [
      {
        id: 'DOC-SYN-1002-COMPANY',
        type: 'company_prepared_statement',
        statementType: 'income_statement',
        fiscalPeriod: 'FY2025',
        scenario: 'borrower_prepared_statement',
        file: 'bright-harbor-foods-fy2025-company-prepared.pdf',
        title: 'Bright Harbor Foods Inc. - Company Prepared Financials',
        pages: [
          [
            'Company Prepared Financial Statement',
            'Borrower: Bright Harbor Foods Inc.',
            'Period: Fiscal Year 2025',
            'Prepared by borrower management',
            '',
            'Sales: $12,200,000',
            'Returns and Allowances: ($180,000)',
            'Net Revenue: $12,020,000',
            'Operating EBITDA: $1,020,000',
            'Debt Service: $1,160,000',
            'Management note: one-time equipment repair included in expenses.'
          ],
          [
            'Balance Sheet',
            'Cash: $410,000',
            'Current Assets: $2,950,000',
            'Current Liabilities: $2,610,000',
            'Total Liabilities: $7,840,000',
            'Shareholder Equity: $2,240,000'
          ]
        ],
        lines: {
          revenue: 12020000,
          ebitda: 1020000,
          debt_service: 1160000,
          cash: 410000,
          current_assets: 2950000,
          current_liabilities: 2610000,
          total_liabilities: 7840000,
          net_worth_equity: 2240000
        }
      }
    ]
  },
  {
    borrower: 'Cobalt Components Co.',
    loan: 'LOAN-SYN-1003',
    documents: [
      {
        id: 'DOC-SYN-1003-SCAN',
        type: 'scanned_financials',
        statementType: 'balance_sheet',
        fiscalPeriod: 'FY2025',
        scenario: 'poor_quality_scan',
        file: 'cobalt-components-fy2025-poor-scan.pdf',
        title: 'Cobalt Components Co. - Poor Quality Scan Simulation',
        pages: [
          [
            'LOW QUALITY SCAN SIMULATION',
            'Borrower: Cobalt Components Co.',
            'FY2025 financial package',
            'Some values are intentionally close together for extraction testing.',
            '',
            'Revenue            $4,980,000',
            'EBITDA             $620,000',
            'Debt Service       $590,000',
            'Cash               $95,000',
            'Current Assets     $1,140,000',
            'Current Liabilities $1,090,000',
            'Total Liabilities  $3,700,000',
            'Equity             $1,050,000'
          ]
        ],
        lines: {
          revenue: 4980000,
          ebitda: 620000,
          debt_service: 590000,
          cash: 95000,
          current_assets: 1140000,
          current_liabilities: 1090000,
          total_liabilities: 3700000,
          net_worth_equity: 1050000
        }
      }
    ]
  },
  {
    borrower: 'Delta Tooling Group Inc.',
    loan: 'LOAN-SYN-1004',
    documents: [
      {
        id: 'DOC-SYN-1004-10Q',
        type: '10q',
        statementType: 'income_statement',
        fiscalPeriod: 'Q3-2025',
        scenario: 'multi_period_10q',
        file: 'delta-tooling-group-q3-2025-10q-extract.pdf',
        title: 'Delta Tooling Group Inc. - Synthetic 10-Q Extract',
        pages: [
          [
            'Quarterly Report Extract - Synthetic',
            'Borrower: Delta Tooling Group Inc.',
            'Quarter ended: September 30, 2025',
            '',
            'Nine Months Revenue: $18,300,000',
            'Quarter Revenue: $6,400,000',
            'Adjusted EBITDA: $1,870,000',
            'Cash and Cash Equivalents: $1,120,000',
            'Current Assets: $5,900,000',
            'Current Liabilities: $3,430,000',
            'Total Liabilities: $8,260,000',
            'Stockholders Equity: $6,770,000'
          ]
        ],
        lines: {
          revenue: 6400000,
          ebitda: 1870000,
          cash: 1120000,
          current_assets: 5900000,
          current_liabilities: 3430000,
          total_liabilities: 8260000,
          net_worth_equity: 6770000
        }
      }
    ]
  }
];

const materialLines = new Set([
  'revenue',
  'ebitda',
  'debt_service',
  'cash',
  'current_assets',
  'current_liabilities',
  'total_liabilities',
  'net_worth_equity'
]);

function pdfEscape(value) {
  return String(value).replace(/\\/g, '\\\\').replace(/\(/g, '\\(').replace(/\)/g, '\\)');
}

function pdfPageStream(lines) {
  const commands = ['BT', '/F1 12 Tf', '72 742 Td'];
  lines.forEach((line, index) => {
    if (index > 0) commands.push('0 -18 Td');
    commands.push(`(${pdfEscape(line)}) Tj`);
  });
  commands.push('ET');
  return commands.join('\n');
}

function buildPdf(title, pages) {
  const objects = [];
  const addObject = (body) => {
    objects.push(body);
    return objects.length;
  };

  const catalogRef = addObject('<< /Type /Catalog /Pages 2 0 R >>');
  const pagesRef = addObject('');
  const fontRef = addObject('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');
  const pageRefs = [];

  for (const pageLines of pages) {
    const stream = pdfPageStream([title, '', ...pageLines]);
    const contentRef = addObject(`<< /Length ${Buffer.byteLength(stream, 'utf8')} >>\nstream\n${stream}\nendstream`);
    const pageRef = addObject(`<< /Type /Page /Parent ${pagesRef} 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 ${fontRef} 0 R >> >> /Contents ${contentRef} 0 R >>`);
    pageRefs.push(pageRef);
  }

  objects[pagesRef - 1] = `<< /Type /Pages /Kids [${pageRefs.map((ref) => `${ref} 0 R`).join(' ')}] /Count ${pageRefs.length} >>`;

  const chunks = ['%PDF-1.4\n'];
  const offsets = [0];
  for (let index = 0; index < objects.length; index += 1) {
    offsets.push(Buffer.byteLength(chunks.join(''), 'utf8'));
    chunks.push(`${index + 1} 0 obj\n${objects[index]}\nendobj\n`);
  }

  const xrefOffset = Buffer.byteLength(chunks.join(''), 'utf8');
  chunks.push(`xref\n0 ${objects.length + 1}\n`);
  chunks.push('0000000000 65535 f \n');
  for (let index = 1; index < offsets.length; index += 1) {
    chunks.push(`${String(offsets[index]).padStart(10, '0')} 00000 n \n`);
  }
  chunks.push(`trailer\n<< /Size ${objects.length + 1} /Root ${catalogRef} 0 R >>\nstartxref\n${xrefOffset}\n%%EOF\n`);
  return chunks.join('');
}

function csvEscape(value) {
  const text = String(value ?? '');
  return /[",\n\r]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

function csv(headers, rows) {
  return [
    headers.join(','),
    ...rows.map((row) => headers.map((header) => csvEscape(row[header])).join(','))
  ].join('\n') + '\n';
}

function money(value) {
  return `$${Number(value).toLocaleString('en-US')}`;
}

function makeCandidateValue(pathName, doc, line, value) {
  if (pathName === 'manual_ncino_control') return value;
  if (pathName === 'ncino_automated_spreading' && doc.id === 'DOC-SYN-1002-COMPANY' && line === 'debt_service') return 116000;
  if (pathName === 'ncino_automated_spreading' && doc.id === 'DOC-SYN-1003-SCAN' && line === 'current_liabilities') return 109000;
  if (pathName === 'salesforce_native_staging' && doc.id === 'DOC-SYN-1001-TAX' && line === 'revenue') return 8160000;
  if (pathName === 'salesforce_native_staging' && doc.id === 'DOC-SYN-1004-10Q' && line === 'revenue') return 18300000;
  return value;
}

function isException(pathName, doc, line) {
  return pathName === 'ncino_automated_spreading' && doc.id === 'DOC-SYN-1003-SCAN' && line === 'current_liabilities';
}

function confidenceFor(pathName, doc, line) {
  if (pathName === 'manual_ncino_control') return '';
  if (doc.scenario === 'poor_quality_scan') return line === 'current_liabilities' ? 0.48 : 0.79;
  if (pathName === 'salesforce_native_staging' && doc.type === '10q') return 0.74;
  if (pathName === 'ncino_automated_spreading') return 0.93;
  return 0.86;
}

async function main() {
  await mkdir(documentDir, { recursive: true });
  await mkdir(path.join(outputDir, 'pilot-results'), { recursive: true });

  const documents = borrowers.flatMap((borrower) => borrower.documents.map((doc) => ({ ...doc, borrower: borrower.borrower, loan: borrower.loan })));

  for (const doc of documents) {
    await writeFile(path.join(documentDir, doc.file), buildPdf(doc.title, doc.pages), 'utf8');
  }

  const corpusRows = documents.map((doc) => ({
    document_id: doc.id,
    borrower: doc.borrower,
    loan_or_opportunity: doc.loan,
    document_type: doc.type,
    statement_type: doc.statementType,
    fiscal_period: doc.fiscalPeriod,
    scenario_type: doc.scenario,
    file_location_reference: `data/synthetic/documents/${doc.file}`,
    source_system: 'synthetic_demo',
    contains_confidential_data: 'false',
    notes: 'Synthetic test document. No real customer data.'
  }));

  const goldRows = [];
  const extractionRows = [];
  const scorecardRows = [];
  const paths = ['ncino_automated_spreading', 'salesforce_native_staging', 'manual_ncino_control'];

  for (const doc of documents) {
    let lineIndex = 0;
    for (const [line, value] of Object.entries(doc.lines)) {
      lineIndex += 1;
      const caseId = `${doc.id}-${line.toUpperCase()}`;
      goldRows.push({
        case_id: caseId,
        borrower: doc.borrower,
        loan_or_opportunity: doc.loan,
        document_id: doc.id,
        statement_type: doc.statementType,
        fiscal_period: doc.fiscalPeriod,
        normalized_line: line,
        manual_value: value,
        material: materialLines.has(line),
        analyst: 'synthetic.senior.analyst@example.bank',
        certification_timestamp: '2026-04-19T14:00:00Z',
        source_page: doc.pages.length > 1 && lineIndex > 4 ? 2 : 1,
        source_coordinates: `synthetic-line-${lineIndex}`,
        notes: 'Gold-standard synthetic value.'
      });

      for (const pathName of paths) {
        const candidateValue = makeCandidateValue(pathName, doc, line, value);
        const exceptionFlag = isException(pathName, doc, line);
        const certified = pathName === 'manual_ncino_control' || !exceptionFlag;
        const confidence = confidenceFor(pathName, doc, line);
        const manualMinutes = pathName === 'manual_ncino_control' ? 12 : 12;
        const candidateMinutes = pathName === 'manual_ncino_control'
          ? 12
          : pathName === 'ncino_automated_spreading'
            ? 7
            : 8;

        extractionRows.push({
          case_id: caseId,
          path: pathName,
          borrower: doc.borrower,
          loan_or_opportunity: doc.loan,
          document_id: doc.id,
          statement_type: doc.statementType,
          fiscal_period: doc.fiscalPeriod,
          source_page: doc.pages.length > 1 && lineIndex > 4 ? 2 : 1,
          source_coordinates: `synthetic-line-${lineIndex}`,
          extracted_raw_value: money(candidateValue),
          normalized_line: line,
          confidence,
          exception_reason: exceptionFlag ? 'Low confidence on poor-quality scan; routed to reviewer.' : '',
          reviewer: certified ? 'synthetic.reviewer@example.bank' : '',
          certification_timestamp: certified ? '2026-04-19T15:00:00Z' : '',
          final_spread_reference: certified ? `SYN-SPREAD-${doc.loan}` : '',
          status: certified ? 'certified' : 'exception',
          notes: candidateValue === value ? 'Synthetic extracted value matches baseline.' : 'Synthetic mismatch for control testing.'
        });

        scorecardRows.push({
          case_id: caseId,
          path: pathName,
          borrower: doc.borrower,
          loan_or_opportunity: doc.loan,
          document_id: doc.id,
          statement_type: doc.statementType,
          fiscal_period: doc.fiscalPeriod,
          normalized_line: line,
          material: materialLines.has(line),
          manual_value: value,
          candidate_value: candidateValue,
          manual_minutes: manualMinutes,
          candidate_minutes: candidateMinutes,
          exception_flag: exceptionFlag,
          certified,
          error_type: candidateValue === value ? '' : line === 'revenue' && doc.type === '10q' ? 'period' : 'extraction',
          notes: candidateValue === value ? 'Synthetic pass row.' : 'Intentional synthetic error to test gate behavior.'
        });
      }
    }
  }

  await writeFile(path.join(outputDir, 'document-corpus.csv'), csv([
    'document_id',
    'borrower',
    'loan_or_opportunity',
    'document_type',
    'statement_type',
    'fiscal_period',
    'scenario_type',
    'file_location_reference',
    'source_system',
    'contains_confidential_data',
    'notes'
  ], corpusRows), 'utf8');

  await writeFile(path.join(outputDir, 'gold-standard-spread.csv'), csv([
    'case_id',
    'borrower',
    'loan_or_opportunity',
    'document_id',
    'statement_type',
    'fiscal_period',
    'normalized_line',
    'manual_value',
    'material',
    'analyst',
    'certification_timestamp',
    'source_page',
    'source_coordinates',
    'notes'
  ], goldRows), 'utf8');

  await writeFile(path.join(outputDir, 'extraction-results.csv'), csv([
    'case_id',
    'path',
    'borrower',
    'loan_or_opportunity',
    'document_id',
    'statement_type',
    'fiscal_period',
    'source_page',
    'source_coordinates',
    'extracted_raw_value',
    'normalized_line',
    'confidence',
    'exception_reason',
    'reviewer',
    'certification_timestamp',
    'final_spread_reference',
    'status',
    'notes'
  ], extractionRows), 'utf8');

  await writeFile(path.join(outputDir, 'pilot-scorecard.csv'), csv([
    'case_id',
    'path',
    'borrower',
    'loan_or_opportunity',
    'document_id',
    'statement_type',
    'fiscal_period',
    'normalized_line',
    'material',
    'manual_value',
    'candidate_value',
    'manual_minutes',
    'candidate_minutes',
    'exception_flag',
    'certified',
    'error_type',
    'notes'
  ], scorecardRows), 'utf8');

  console.log(`Synthetic pilot data generated in ${path.relative(root, outputDir)}`);
  console.log(`Documents: ${documents.length}`);
  console.log(`Gold-standard rows: ${goldRows.length}`);
  console.log(`Scorecard rows: ${scorecardRows.length}`);
}

await main();
