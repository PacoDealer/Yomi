// Runs a Format-A Yomi plugin file in Node against the live site (S180). SOURCE.fetch is a curl shim, so this is the
// plugin's own code path, not a re-implementation. Usage: node run.mjs <plugin.js> <function> [args...]
import { readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import vm from "node:vm";

const [file, fn, ...args] = process.argv.slice(2);
const SOURCE = {
  fetch(url, opts = {}) {
    const h = Object.entries(opts.headers || {}).flatMap(([k, v]) => ["-H", `${k}: ${v}`]);
    return execFileSync("curl", ["-gs", "-m", "30", "--fail-with-body", ...h, url], { encoding: "utf8", maxBuffer: 64 << 20 });
  },
};
const ctx = vm.createContext({ SOURCE, console: { log: (...a) => console.error(...a) }, encodeURIComponent, JSON, parseFloat, parseInt, String, Math, Date });
vm.runInContext(readFileSync(file, "utf8"), ctx);
const out = ctx[fn](...args);
console.log(JSON.stringify(out));
