import assert from 'node:assert/strict';
import { mkdtemp, readFile, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import test from 'node:test';

const execFileAsync = promisify(execFile);

test('generates an HTML report from a scorecard CSV', async () => {
  const tempDir = await mkdtemp(path.join(os.tmpdir(), 'spreading-report-'));
  const scorecardPath = path.join(tempDir, 'pilot-scorecard.csv');
  const outputPath = path.join(tempDir, 'report.html');
  await writeFile(
    scorecardPath,
    [
      'case_id,path,document_id,normalized_line,material,manual_value,candidate_value,manual_minutes,candidate_minutes,exception_flag,certified,error_type',
      'CASE-001,ncino_automated_spreading,DOC-001,revenue,true,1000000,900000,12,7,false,true,extraction'
    ].join('\n'),
    'utf8'
  );

  await execFileAsync(process.execPath, ['src/report.js', scorecardPath, outputPath], {
    cwd: path.resolve(import.meta.dirname, '..')
  });

  const html = await readFile(outputPath, 'utf8');
  assert.match(html, /C&I Financial Spreading AI Pilot Report/);
  assert.match(html, /nCino Automated Spreading/);
  assert.match(html, /Uncaught Material Errors/);
  assert.match(html, /CASE-001/);
});
