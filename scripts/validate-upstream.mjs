#!/usr/bin/env node
// Offline syntax sweep: no Bend programs, effects or imports are executed.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const root = fs.realpathSync(process.argv[2] ?? path.join(repo, '../bend'));
function walk(dir) {
  return fs.readdirSync(dir, {withFileTypes: true}).flatMap(e => {
    if (e.name === '.git' || e.name === 'node_modules') return [];
    const p = path.join(dir, e.name);
    return e.isDirectory() ? walk(p) : e.isFile() && p.endsWith('.bend') ? [p] : [];
  });
}
const files = walk(root).sort();
if (!files.length) throw new Error(`No .bend files in ${root}`);
fs.mkdirSync(path.join(repo, 'build'), {recursive: true});
const list = path.join(repo, 'build/upstream-paths.txt');
fs.writeFileSync(list, files.join('\n') + '\n');
const run = spawnSync('tree-sitter', ['parse', '--paths', list, '--quiet', '--json-summary', '--timeout', '10000000'], {
  cwd: repo, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024, timeout: 180000,
});
if (run.error) throw run.error;
if (run.stderr) process.stderr.write(run.stderr);
// CLI 0.26 also prints human-readable failure lines before its JSON object.
const jsonStart = run.stdout.search(/^\{/m);
if (jsonStart < 0) throw new Error(`No parse summary (exit ${run.status}): ${run.stdout}`);
const summary = JSON.parse(run.stdout.slice(jsonStart));
if (summary.parse_summaries.length !== files.length) throw new Error('Incomplete sweep');
const results = summary.parse_summaries.map(p => {
  const text = fs.readFileSync(p.file, 'utf8');
  const expected = text.split('\n').filter(l => l.startsWith('#|')).map(l => l.slice(2));
  return {...p, file: path.relative(root, p.file),
    expectsDiagnostic: expected.some(l => l.startsWith('Error:') || /^exit [1-9]/.test(l)),
    expectedOutput: expected,
  };
});
const failures = results.filter(p => !p.successful);
const unexpected = failures.filter(p => !p.expectsDiagnostic);
const baselinePath = path.join(repo, 'test/upstream-rejections.json');
const baseline = fs.existsSync(baselinePath) ? JSON.parse(fs.readFileSync(baselinePath, 'utf8')) : null;
const newRejections = baseline ? failures.filter(p => !baseline.files.includes(p.file)) : unexpected;
const noLongerRejected = baseline ? baseline.files.filter(f => results.some(p => p.file === f && p.successful)) : [];
const report = {reference: root, total: results.length, clean: results.length - failures.length,
  rejected: failures.length, rejectedNonDiagnostic: unexpected.length, results};
const out = path.join(repo, 'build/upstream-report.json');
fs.writeFileSync(out, JSON.stringify(report, null, 2) + '\n');
console.log(`${report.total} files: ${report.clean} clean, ${report.rejected} rejected, ${unexpected.length} rejected non-diagnostic fixtures.`);
console.log('Diagnostic fixtures include semantic/runtime errors: this classification alone is NOT a syntax oracle.');
for (const f of failures) console.log(`${f.expectsDiagnostic ? 'DIAGNOSTIC' : 'UNEXPECTED'} ${f.file}`);
for (const p of newRejections) console.error(`NEW REJECTION (review required): ${p.file}`);
for (const f of noLongerRejected) console.error(`NO LONGER REJECTED (review required): ${f}`);
console.log(`Full per-file report: ${out}`);
process.exitCode = unexpected.length || newRejections.length || noLongerRejected.length || (run.status !== 0 && run.status !== 1) ? 1 : 0;
