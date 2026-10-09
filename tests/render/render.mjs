// Renders exported scenes to PNG with three.js in headless Chromium.
// Usage: node tests/render/render.mjs <scenes.json> <outDir>
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const depsDir = process.env.RENDER_DEPS || path.resolve("node_modules");
const { chromium } = require(path.join(depsDir, "playwright"));
const threeDir = path.join(depsDir, "three");
const here = path.dirname(new URL(import.meta.url).pathname);

const [scenesPath, outDir] = process.argv.slice(2);
const scenes = JSON.parse(fs.readFileSync(scenesPath, "utf8"));
fs.mkdirSync(outDir, { recursive: true });

const server = http.createServer((req, res) => {
  let file;
  if (req.url.startsWith("/three/")) file = path.join(threeDir, req.url.slice(7));
  else file = path.join(here, req.url === "/" ? "viewer.html" : req.url);
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404); res.end(); return; }
    const type = file.endsWith(".js") ? "text/javascript" : "text/html";
    res.writeHead(200, { "Content-Type": type });
    res.end(data);
  });
});
await new Promise((r) => server.listen(0, r));
const port = server.address().port;

const browser = await chromium.launch({
  executablePath: process.env.CHROMIUM_PATH || undefined,
  args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"],
});
const page = await browser.newPage({ viewport: { width: 900, height: 700 } });
page.on("console", (m) => { if (m.type() === "error") console.error("viewer:", m.text()); });
await page.goto(`http://127.0.0.1:${port}/viewer.html`);
await page.waitForFunction(() => window.viewerReady === true);
for (const scene of scenes) {
  for (const view of scene.views) {
    await page.setViewportSize({ width: view.width || 900, height: view.height || 700 });
    await page.evaluate((d) => window.renderScene(d), { ...view, parts: scene.parts, groundY: scene.groundY });
    const file = path.join(outDir, `${scene.name}_${view.name}.png`);
    await page.locator("canvas").screenshot({ path: file });
    console.log("wrote", file);
  }
}
await browser.close();
server.close();
