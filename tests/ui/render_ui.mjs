// Renders UI snapshots (tests/ui/run_ui.luau) to PNG in headless Chromium and reports layout issues.
// Usage: node tests/ui/render_ui.mjs <snapshotDir> [--annotate]
//   RENDER_DEPS  node_modules containing `playwright`
//   CHROMIUM_PATH  chromium / headless_shell binary
//   UI_FONTS     folder with Bangers-400, PermanentMarker-400, Montserrat-500/700 .woff2 (scripts/fetch_ui_fonts.sh)
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const depsDir = process.env.RENDER_DEPS || path.resolve("node_modules");
const { chromium } = require(path.join(depsDir, "playwright"));
const here = path.dirname(new URL(import.meta.url).pathname);
const fontsDir = process.env.UI_FONTS || path.join(here, "fonts");
const rendersDir = path.resolve("tests/renders/out");

const snapDir = process.argv[2];
const annotate = process.argv.includes("--annotate");
const files = fs.readdirSync(snapDir).filter((f) => f.endsWith(".json") && f !== "report.json").sort();

const server = http.createServer((req, res) => {
  const url = decodeURIComponent(req.url.split("?")[0]);
  let file;
  if (url.startsWith("/fonts/")) file = path.join(fontsDir, url.slice(7));
  else if (url.startsWith("/renders/")) file = path.join(rendersDir, url.slice(9));
  else file = path.join(here, "ui_viewer.html");
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404); res.end(); return; }
    const type = file.endsWith(".html") ? "text/html" : file.endsWith(".woff2") ? "font/woff2" : "image/png";
    res.writeHead(200, { "Content-Type": type });
    res.end(data);
  });
});
await new Promise((r) => server.listen(0, r));
const port = server.address().port;

const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined });
const page = await browser.newPage();
page.on("console", (m) => { if (m.type() === "error") console.error("viewer:", m.text()); });
await page.goto(`http://127.0.0.1:${port}/`);
await page.waitForFunction(() => window.viewerReady === true);

const report = {};
let total = 0;
for (const f of files) {
  const snap = JSON.parse(fs.readFileSync(path.join(snapDir, f), "utf8"));
  await page.setViewportSize({ width: snap.viewport[0], height: snap.viewport[1] });
  const issues = await page.evaluate((s) => window.render(s), snap);
  if (!annotate) await page.evaluate(() => window.clearFlags());
  const out = path.join(snapDir, f.replace(/\.json$/, ".png"));
  await page.screenshot({ path: out });
  report[f] = issues;
  total += issues.length;
  console.log(`${issues.length ? "⚠" : "✓"} ${f.replace(/\.json$/, "")}${issues.length ? `  (${issues.length} issue${issues.length > 1 ? "s" : ""})` : ""}`);
  for (const i of issues) console.log(`    ${i.kind}: ${i.path}${i.text ? ` "${i.text}"` : ""} ${JSON.stringify(i.over || i.rect)}`);
}
fs.writeFileSync(path.join(snapDir, "report.json"), JSON.stringify(report, null, 2));
console.log(`\n${files.length} screens, ${total} layout issue(s)`);
await browser.close();
server.close();
process.exit(0);
