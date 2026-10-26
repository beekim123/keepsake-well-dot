import { existsSync } from 'node:fs';
import { assert, readJson, readBytes, safePath, relativePath, validateId, unique, sha256, HASH_PATTERN } from './paths.mjs';

export function loadAssetManifest(root, kind, { optional = false } = {}) {
  assert(kind === 'art' || kind === 'audio', 'Unknown manifest kind');
  const relative = `resources/${kind}/export/manifest.json`;
  const absolute = safePath(root, relative);
  if (optional && !existsSync(absolute)) return null;
  const manifest = readJson(root, relative);
  assert(manifest.format === `${kind}-manifest/1` && Array.isArray(manifest.assets), `${relative}: invalid manifest format`);
  const ids = new Set(), paths = new Set();
  for (const asset of manifest.assets) {
    assert(asset && typeof asset === 'object', `${relative}: invalid asset`);
    validateId(asset.id, relative);
    unique(asset.id, ids, 'asset id');
    relativePath(asset.file, `${asset.id}.file`);
    unique(asset.file.toLowerCase(), paths, 'asset path');
    assert(asset.file.endsWith(kind === 'art' ? '.png' : '.wav'), `${asset.id}: unexpected file extension`);
    assert(HASH_PATTERN.test(asset.hash), `${asset.id}: invalid SHA-256`);
    assert(sha256(readBytes(root, `resources/${kind}/export/${asset.file}`)) === asset.hash, `${asset.id}: source hash mismatch`);
  }
  return manifest;
}

export function loadRegistry(root) {
  const registry = readJson(root, 'content/registry.json');
  assert(registry.format === 'content/1' && Array.isArray(registry.files) && registry.files.length > 0, 'Invalid content registry');
  const ids = new Set(), paths = new Set(), targets = new Set(['registry.json']);
  for (const entry of registry.files) {
    assert(entry && typeof entry === 'object', 'Invalid content registry entry');
    validateId(entry.id, 'registry');
    unique(entry.id, ids, 'registry id');
    relativePath(entry.file, `${entry.id}.file`);
    relativePath(entry.target, `${entry.id}.target`);
    assert(entry.file.endsWith('.json') && entry.target.endsWith('.json'), `${entry.id}: content must be JSON`);
    unique(entry.file.toLowerCase(), paths, 'content source path');
    unique(entry.target.toLowerCase(), targets, 'content target path');
    safePath(root, `content/${entry.file}`, { mustExist: true, file: true });
  }
  return registry;
}
