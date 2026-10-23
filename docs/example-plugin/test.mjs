// Runs the example plugin in Node against the live Wikisource API with Yomi's own cheerio bundle and a curl-backed
// SOURCE.fetch — the same code path the app runs. Usage: node test.mjs [plugin.js]
import { readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import vm from "node:vm";

const file = process.argv[2] || new URL("./wikisource.js", import.meta.url).pathname;
const SOURCE = {
  fetch(url, opts = {}) {
    const h = Object.entries(opts.headers || {}).flatMap(([k, v]) => ["-H", `${k}: ${v}`]);
    return execFileSync("curl", ["-gs", "-m", "30", "--fail-with-body", ...h, url], { encoding: "utf8", maxBuffer: 64 << 20 });
  },
};
const ctx = vm.createContext({ SOURCE, console, encodeURIComponent, decodeURIComponent, JSON });
const libs = new URL("../../Yomi/Resources/yomi-js-libs.js", import.meta.url).pathname;
vm.runInContext(readFileSync(libs, "utf8"), ctx);
ctx.cheerio = { load: ctx.__yomiLibs.cheerio.load };
vm.runInContext(readFileSync(file, "utf8"), ctx);
const p = ctx.plugin;

let failures = 0;
const check = (ok, label) => { console.log(`${ok ? "ok  " : "FAIL"} ${label}`); if (!ok) failures++; };

const page1 = p.popularNovels(1);
const page2 = p.popularNovels(2);
check(page1.length > 20 && page1.every(n => n.name && n.path && !n.path.includes("/")), `browse page 1: ${page1.length} works, e.g. ${page1[0]?.name}`);
check(page2.length > 20 && page2[0].path !== page1[0].path, `browse page 2: ${page2.length} works, starts ${page2[0]?.name}`);

const latest = p.popularNovels(1, { showLatestNovels: true });
check(latest.length > 20 && latest[0].path !== page1[0].path, `latest tab: ${latest.length} works, newest ${latest[0]?.name}`);

const found = p.searchNovels("Pride and Prejudice", 1);
check(found.some(n => n.path === "Pride and Prejudice (1813)"), `search: ${found.length} works incl. Pride and Prejudice (1813)`);

const pp = p.parseNovel("Pride and Prejudice (1813)");
check(pp.chapters.length === 61, `Pride and Prejudice: ${pp.chapters.length} chapters (expected 61), author "${pp.author}"`);
check(pp.chapters[0].name === "Volume 1 · Chapter 1" && pp.chapters[60].name === "Volume 3 · Chapter 19", `order: ${pp.chapters[0].name} … ${pp.chapters[60].name}`);
check(pp.chapters.every((c, i) => c.chapterNumber === i + 1), "chapter numbers 1…61 in reading order");

const alice = p.parseNovel("Alice's Adventures in Wonderland (1866)");
check(alice.chapters.length >= 12 && alice.cover.startsWith("https://"), `Alice: ${alice.chapters.length} chapters, cover ${alice.cover ? "yes" : "no"}`);

const html = p.parseChapter(pp.chapters[0].path);
const plain = html.replace(/<[^>]+>/g, "").replace(/\s+/g, " ");
check(plain.includes("t is a truth universally acknowledged"), "chapter 1 text: first sentence present (the I is a drop capital)");
check(!/mw-editsection|wst-header|ws-noexport/.test(html), "chapter 1: header/edit links removed");
check(html.includes("Source: <a href=\"https://en.wikisource.org/wiki/"), "chapter 1: source link appended");

console.log(failures ? `${failures} check(s) failed` : "OK all checks");
process.exit(failures ? 1 : 0);
