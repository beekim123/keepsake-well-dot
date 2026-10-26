import { existsSync, lstatSync, mkdirSync, readdirSync, renameSync, unlinkSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { ROOT, assert, isMain, readBytes, readJson, relativePath, safePath, sha256, jsonBytes, unique, validateId, HASH_PATTERN } from '../lib/paths.mjs';
import { loadAssetManifest, loadRegistry } from '../lib/manifests.mjs';
import { checkContent } from '../qa/content-check.mjs';

const PACK = 'godot/resource-pack.json';
const FONT_ROOT = 'third_party/fonts/fusion-pixel-12px';
const FONT_FILE = 'fusion-pixel-12px-proportional-zh_hans.otf.woff2';
const FONT_LICENSES = ['OFL.txt', 'LICENSES/ark-pixel/OFL.txt', 'LICENSES/cubic-11/OFL.txt', 'LICENSES/galmuri/LICENSE.txt'];

function managedPath(relative) {
  relativePath(relative, 'managed path');
  assert(/^(resources\/(art|audio|fonts)\/|data\/)/.test(relative), `Not a managed resource path: ${relative}`);
  return relative;
}

function filesIn(root, relative) {
  const absolute = safePath(root, relative, { mustExist: true });
  assert(lstatSync(absolute).isDirectory(), `Expected directory: ${relative}`);
  return readdirSync(absolute).sort().flatMap(name => {
    const child = `${relative}/${name}`;
    const stat = lstatSync(safePath(root, child, { mustExist: true }));
    assert(stat.isDirectory() || stat.isFile(), `Unsupported font file type: ${child}`);
    return stat.isDirectory() ? filesIn(root, child) : [child];
  });
}

export function buildPlan(root = ROOT) {
  checkContent(root);
  const files = [], payloads = new Map(), ids = new Set(), targets = new Set();
  function add(id, source, target) {
    validateId(id, 'pack');
    unique(id, ids, 'pack id');
    managedPath(target);
    unique(target.toLowerCase(), targets, 'pack target');
    const bytes = readBytes(root, source);
    const entry = { id, source, path: target, hash: sha256(bytes) };
    files.push(entry);
    payloads.set(target, bytes);
  }
  for (const kind of ['art', 'audio']) {
    const manifest = loadAssetManifest(root, kind);
    add(`manifest.${kind}`, `resources/${kind}/export/manifest.json`, `resources/${kind}/manifest.json`);
    for (const asset of manifest.assets) add(asset.id, `resources/${kind}/export/${asset.file}`, `resources/${kind}/${asset.file}`);
  }
  const registry = loadRegistry(root);
  add('content.registry', 'content/registry.json', 'data/registry.json');
  for (const entry of registry.files) add(`content.${entry.id}`, `content/${entry.file}`, `data/${entry.target}`);
  for (const file of [FONT_FILE, ...FONT_LICENSES]) readBytes(root, `${FONT_ROOT}/${file}`);
  for (const source of filesIn(root, FONT_ROOT)) {
    const file = source.slice(FONT_ROOT.length + 1);
    const id = `font.fusion_pixel_12px.${file.toLowerCase().replace(/[^a-z0-9_]/g, '_')}`;
    add(id, source, `resources/fonts/fusion-pixel-12px/${file}`);
  }
  files.sort((a, b) => a.path < b.path ? -1 : a.path > b.path ? 1 : 0);
  return { pack: { format: 'resource-pack/1', files }, payloads };
}

function previousPack(root) {
  const absolute = safePath(root, PACK, { file: true });
  if (!existsSync(absolute)) return { format: 'resource-pack/1', files: [] };
  const previous = readJson(root, PACK);
  assert(previous.format === 'resource-pack/1' && Array.isArray(previous.files), 'Invalid previous resource pack');
  const ids = new Set(), paths = new Set();
  for (const entry of previous.files) {
    validateId(entry.id, 'previous pack');
    unique(entry.id, ids, 'previous pack id');
    managedPath(entry.path);
    relativePath(entry.source, 'previous pack source');
    assert(/^(resources\/(art|audio)\/export\/|content\/|third_party\/fonts\/)/.test(entry.source), `Invalid previous pack source: ${entry.source}`);
    unique(entry.path.toLowerCase(), paths, 'previous pack path');
    assert(HASH_PATTERN.test(entry.hash), `Invalid previous pack hash: ${entry.path}`);
    safePath(root, `godot/${entry.path}`, { file: true });
  }
  return previous;
}

function writeAtomic(root, relative, bytes) {
  const destination = safePath(root, relative, { file: true });
  mkdirSync(path.dirname(destination), { recursive: true });
  // Recheck after creating parents; never follow linked destinations.
  safePath(root, relative, { file: true });
  const temporary = `${relative}.sync-${process.pid}`;
  const tempPath = safePath(root, temporary, { file: true });
  assert(!existsSync(tempPath), `Temporary file already exists: ${temporary}`);
  writeFileSync(tempPath, bytes, { flag: 'wx' });
  try { renameSync(tempPath, destination); }
  catch (error) { unlinkSync(tempPath); throw error; }
}

export function syncGodot(root = ROOT, { verify = false } = {}) {
  const { pack, payloads } = buildPlan(root);
  const previous = previousPack(root);
  const desired = new Set(pack.files.map(entry => entry.path));
  const old = new Set(previous.files.map(entry => entry.path));
  const stale = previous.files.filter(entry => !desired.has(entry.path));
  const expectedPack = jsonBytes(pack);
  if (verify) {
    assert(readBytes(root, PACK).equals(expectedPack), 'Resource pack is stale; run npm run sync');
    for (const entry of pack.files) assert(readBytes(root, `godot/${entry.path}`).equals(payloads.get(entry.path)), `Synced bytes differ: ${entry.path}`);
    return { files: pack.files.length, removed: 0, verified: true };
  }
  // Preflight all destinations and stale files before writing anything. Unmanaged
  // collisions and locally changed stale files are errors, never arbitrary deletion.
  for (const entry of pack.files) {
    const destination = safePath(root, `godot/${entry.path}`, { file: true });
    if (existsSync(destination) && !old.has(entry.path)) {
      assert(readBytes(root, `godot/${entry.path}`).equals(payloads.get(entry.path)), `Refusing to overwrite unmanaged file: ${entry.path}`);
    }
  }
  for (const entry of stale) {
    const destination = safePath(root, `godot/${entry.path}`, { file: true });
    if (existsSync(destination)) assert(sha256(readBytes(root, `godot/${entry.path}`)) === entry.hash, `Stale managed file was modified; preserving it: ${entry.path}`);
  }
  for (const entry of pack.files) {
    const relative = `godot/${entry.path}`;
    if (!existsSync(safePath(root, relative)) || !readBytes(root, relative).equals(payloads.get(entry.path))) writeAtomic(root, relative, payloads.get(entry.path));
  }
  for (const entry of stale) {
    const destination = safePath(root, `godot/${entry.path}`, { file: true });
    if (existsSync(destination)) unlinkSync(destination);
  }
  if (!existsSync(safePath(root, PACK)) || !readBytes(root, PACK).equals(expectedPack)) writeAtomic(root, PACK, expectedPack);
  return { files: pack.files.length, removed: stale.length, verified: false };
}

if (isMain(import.meta.url)) {
  try {
    assert(process.argv.slice(2).every(arg => arg === '--verify') && process.argv.length <= 3, 'Usage: node tools/resources/sync-godot.mjs [--verify]');
    const result = syncGodot(ROOT, { verify: process.argv.includes('--verify') });
    console.log(`sync${result.verified ? ':verify' : ''} PASS — ${result.files} managed files; ${result.removed} stale entries removed`);
  } catch (error) { console.error(`sync FAIL — ${error.message}`); process.exitCode = 1; }
}
