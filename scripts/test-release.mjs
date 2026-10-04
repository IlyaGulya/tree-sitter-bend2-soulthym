#!/usr/bin/env node
// Offline metadata gate; does not install, tag, publish or contact registries.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = name => fs.readFileSync(path.join(root, name), 'utf8');
const json = name => JSON.parse(read(name));
const version = json('package.json').version;
assert.match(version, /^\d+\.\d+\.\d+$/);
assert.equal(json('tree-sitter.json').metadata.version, version);
for (const file of ['Cargo.toml', 'pyproject.toml'])
  assert.equal(read(file).match(/^version = "([^"]+)"/m)?.[1], version, file);
assert.equal(read('CMakeLists.txt').match(/VERSION "([^"]+)"/)?.[1], version);
assert.equal(read('Makefile').match(/^VERSION := (.+)$/m)?.[1], version);
const parser = read('src/parser.c');
const embedded = ['major', 'minor', 'patch'].map(k => parser.match(new RegExp(`\\.${k}_version = (\\d+)`))?.[1]).join('.');
assert.equal(embedded, version, 'regenerate the parser after bumping metadata');
assert.match(parser, /#define LANGUAGE_VERSION 15\b/);
assert.match(read('pyproject.toml'), /tree-sitter~=0\.25/, 'Python optional core must support ABI 15');
assert(read('CHANGELOG.md').includes(`## ${version}`), 'missing release notes');
assert(read('LICENSE').startsWith('MIT License'), 'include the declared license text');
for (const entry of ['LICENSE', 'CHANGELOG.md', 'docs/**/*.md'])
  assert(json('package.json').files.includes(entry), 'missing packaged documentation: ' + entry);
const reference = json('test/bend-reference.json');
assert.equal(reference.tag, 'v' + reference.version);
assert.match(reference.commit, /^[0-9a-f]{40}$/);
assert(read('README.md').includes(reference.tag), 'README tag differs');
assert(read('README.md').includes(reference.commit), 'README commit differs');
assert(json('test/upstream-rejections.json').reference.includes(reference.commit), 'rejection baseline pin differs');
const upstream = process.env.BEND2_UPSTREAM ?? path.join(root, '../bend');
if (fs.existsSync(upstream)) {
  for (const entry of reference.stdlib) {
    const source = fs.readFileSync(path.join(upstream, entry.file));
    assert.equal(createHash('sha256').update(source).digest('hex'), entry.sha256, entry.file + ' differs from the release pin');
    assert.equal(source.length, entry.bytes);
    assert.equal(source.toString('utf8').split('\n').length - 1, entry.lines);
  }
  if (fs.existsSync(path.join(upstream, '.git'))) {
    const git = (...args) => execFileSync('git', ['-C', upstream, ...args], {encoding: 'utf8'}).trim();
    assert.equal(git('rev-parse', 'HEAD'), reference.commit, 'upstream checkout must be at the release pin, not main');
    assert.equal(git('rev-parse', reference.tag + '^{commit}'), reference.commit, 'local release tag differs');
    assert.equal(git('status', '--porcelain', '--untracked-files=no'), '', 'upstream has tracked modifications');
  }
}
console.log(`Release metadata: parser ${version}, ABI 15, Bend ${reference.tag} at ${reference.commit}.`);
