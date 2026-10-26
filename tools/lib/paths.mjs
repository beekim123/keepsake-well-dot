import { lstatSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';

export const ROOT = fileURLToPath(new URL('../../', import.meta.url));
export const MAX_FILE_BYTES = 2_000_000;
export const ID_PATTERN = /^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$/;
export const HASH_PATTERN = /^[a-f0-9]{64}$/;

export function assert(condition, message) {
  if (!condition) throw new Error(message);
}

export function relativePath(value, label = 'path') {
  assert(typeof value === 'string' && value.length > 0, `${label}: expected a nonempty relative path`);
  assert(!value.includes('\\') && !value.includes(':') && !value.startsWith('/'), `${label}: unsafe path ${value}`);
  assert(value.split('/').every(part => /^[A-Za-z0-9_-][A-Za-z0-9_.-]*$/.test(part) && part !== '..'), `${label}: unsafe path ${value}`);
  return value;
}

// Reject symlinks in all existing components, not just the final file. This also
// protects writes into a missing descendant of an existing linked directory.
export function safePath(root, relative, { mustExist = false, file = false } = {}) {
  relativePath(relative);
  const base = path.resolve(root);
  assert(!lstatSync(base).isSymbolicLink(), `Symlink root is not allowed: ${base}`);
  let current = base;
  const parts = relative.split('/');
  for (let i = 0; i < parts.length; i++) {
    current = path.join(current, parts[i]);
    let stat;
    try { stat = lstatSync(current); } catch (error) {
      if (error.code !== 'ENOENT') throw error;
      assert(!mustExist, `Missing file: ${relative}`);
      continue;
    }
    assert(!stat.isSymbolicLink(), `Symlink is not allowed: ${relative}`);
    if (i < parts.length - 1) assert(stat.isDirectory(), `Expected directory: ${relative}`);
    else if (file) assert(stat.isFile(), `Expected regular file: ${relative}`);
  }
  return current;
}

export function readBytes(root, relative) {
  const absolute = safePath(root, relative, { mustExist: true, file: true });
  assert(lstatSync(absolute).size < MAX_FILE_BYTES, `File must be smaller than 2 MB: ${relative}`);
  return readFileSync(absolute);
}

export function readJson(root, relative) {
  try { return JSON.parse(readBytes(root, relative).toString('utf8')); }
  catch (error) { throw new Error(`${relative}: ${error.message}`); }
}

export function sha256(bytes) { return createHash('sha256').update(bytes).digest('hex'); }
export function jsonBytes(value) { return Buffer.from(`${JSON.stringify(value, null, 2)}\n`); }
export function isMain(url) { return process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(url); }

export function validateId(id, context) { assert(typeof id === 'string' && ID_PATTERN.test(id), `${context}: invalid id ${id}`); }

export function unique(value, seen, label) {
  assert(!seen.has(value), `Duplicate ${label}: ${value}`);
  seen.add(value);
}
