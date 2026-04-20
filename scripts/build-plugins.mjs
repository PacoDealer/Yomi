// Setup: npm install -g esbuild
// Run:   node scripts/build-plugins.mjs
// Place LNReader v2.x TypeScript plugins in scripts/plugins-src/
// Output: Yomi/Resources/*.js + ~/Desktop/yomi-firebase/public/*.js + index.json

import { readFileSync, writeFileSync, existsSync, mkdirSync, readdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { join, basename, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT  = join(__dirname, '..');
const SRC_DIR    = join(__dirname, 'plugins-src');
const OUT_DIR    = join(REPO_ROOT, 'Yomi', 'Resources');
const FIREBASE_DIR = process.env.BUILD_FIREBASE_DIR
    ?? join(process.env.HOME, 'Desktop', 'yomi-firebase', 'public');
const CATALOG_BASE_URL = 'https://yomi-plugins.web.app/';

// ── Guard: plugins-src must exist ────────────────────────────────────────────

if (!existsSync(SRC_DIR)) {
    console.log(`ℹ️  scripts/plugins-src/ does not exist yet.`);
    console.log(`   Create the folder and place LNReader v2.x TypeScript plugins inside.`);
    process.exit(0);
}

// ── Ensure output directories exist ──────────────────────────────────────────

mkdirSync(OUT_DIR, { recursive: true });
mkdirSync(FIREBASE_DIR, { recursive: true });

// ── Metadata extraction from plugin header comments ──────────────────────────

function extractMeta(source, filename) {
    function tag(name) {
        const m = source.match(new RegExp(`\\/\\/\\s*@${name}\\s+(.+)`));
        return m ? m[1].trim() : null;
    }
    const stem = basename(filename, '.ts');
    return {
        name:        tag('name')        ?? stem,
        version:     tag('version')     ?? '1.0.0',
        language:    tag('lang')        ?? 'en',
        description: tag('description') ?? '',
        iconURL:     tag('icon')        ?? null,
        isNSFW:      tag('nsfw') === 'true',
    };
}

// ── sha256 helper ─────────────────────────────────────────────────────────────

function sha256hex(str) {
    return createHash('sha256').update(str).digest('hex');
}

// ── Process each .ts file ─────────────────────────────────────────────────────

const tsFiles = readdirSync(SRC_DIR).filter(f => f.endsWith('.ts'));

if (tsFiles.length === 0) {
    console.log(`ℹ️  No .ts files found in scripts/plugins-src/. Nothing to build.`);
    process.exit(0);
}

const catalogEntries = [];
let bundledCount = 0;

for (const tsFile of tsFiles) {
    const stem     = basename(tsFile, '.ts');
    const srcPath  = join(SRC_DIR, tsFile);
    const outName  = stem + '.js';
    const outPath  = join(OUT_DIR, outName);
    const fbPath   = join(FIREBASE_DIR, outName);
    const fileURL  = CATALOG_BASE_URL + outName;

    console.log(`\n📦 Bundling ${tsFile}...`);

    try {
        const result = await build({
            entryPoints: [srcPath],
            format:      'iife',
            bundle:      true,
            minify:      false,
            platform:    'browser',
            target:      'es6',
            write:       false,   // capture output in memory
        });

        const code = result.outputFiles[0].text;

        // Write to Yomi/Resources/
        writeFileSync(outPath, code, 'utf8');
        console.log(`   ✅ Yomi/Resources/${outName}`);

        // Write to Firebase public/
        writeFileSync(fbPath, code, 'utf8');
        console.log(`   ✅ ${FIREBASE_DIR}/${outName}`);

        // Build catalog entry
        const source = readFileSync(srcPath, 'utf8');
        const meta   = extractMeta(source, tsFile);
        catalogEntries.push({
            id:          sha256hex(fileURL).slice(0, 32),
            name:        meta.name,
            version:     meta.version,
            language:    meta.language,
            description: meta.description,
            iconURL:     meta.iconURL,
            fileURL:     fileURL,
            isNSFW:      meta.isNSFW,
        });

        bundledCount++;
    } catch (err) {
        console.error(`   ❌ Failed to bundle ${tsFile}:`, err.message);
    }
}

// ── Merge with existing catalog (preserve hand-built entries) ─────────────────

const indexPath = join(FIREBASE_DIR, 'index.json');
let existingEntries = [];
if (existsSync(indexPath)) {
    try {
        existingEntries = JSON.parse(readFileSync(indexPath, 'utf8'));
    } catch { /* invalid JSON — start fresh */ }
}

// New TS-built entries override existing by fileURL; otherwise keep existing
const newURLs = new Set(catalogEntries.map(e => e.fileURL));
const preserved = existingEntries.filter(e => !newURLs.has(e.fileURL));
const merged = [...preserved, ...catalogEntries].sort((a, b) =>
    a.name.localeCompare(b.name, undefined, { sensitivity: 'base' })
);

writeFileSync(indexPath, JSON.stringify(merged, null, 2), 'utf8');
console.log(`\n📋 index.json written → ${indexPath}`);
console.log(`   ${merged.length} plugin(s) listed (${preserved.length} existing + ${catalogEntries.length} new).`);

// ── Summary ───────────────────────────────────────────────────────────────────

console.log(`\n✅ Done. ${bundledCount}/${tsFiles.length} plugin(s) bundled.`);
console.log(`   Resources → ${OUT_DIR}`);
console.log(`   Firebase  → ${FIREBASE_DIR}`);
