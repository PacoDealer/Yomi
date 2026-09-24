// Bundles the real cheerio / htmlparser2 / dayjs into one file JSBridge evaluates in every JSContext.
// Run after changing versions in package.json:  node scripts/build-js-libs.mjs
import { build } from 'esbuild';

await build({
  entryPoints: ['scripts/js-libs/entry.js'],
  outfile: 'Yomi/Resources/yomi-js-libs.js',
  bundle: true,
  format: 'iife',
  platform: 'browser',   // cheerio's browser build — no Node-only fromURL/undici
  target: 'safari17',    // JavaScriptCore on iOS 26
  minify: true,
  legalComments: 'eof',  // keep the MIT licence notices in the file
  define: { 'process.env.NODE_ENV': '"production"' },
});
console.log('wrote Yomi/Resources/yomi-js-libs.js');
