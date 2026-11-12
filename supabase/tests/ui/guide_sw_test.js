// EP-09 thème G (DT14-09) : le service worker garde les 3 guides, guide.js et guide.css pour le hors ligne ; réseau d'abord en ligne.
const { chromium } = require("/opt/npm-tools/node_modules/playwright");
const http = require("http"), fs = require("fs"), path = require("path"), os = require("os");
const ROOT = path.resolve(__dirname, "../../..");
const SITE = fs.mkdtempSync(path.join(os.tmpdir(), "sfsite-"));
fs.cpSync(ROOT + "/app", SITE, { recursive: true }); fs.cpSync(ROOT + "/guide", SITE + "/guide", { recursive: true });
fs.writeFileSync(SITE + "/js/config.js", fs.readFileSync(SITE + "/js/config.js", "utf8").replace("__SUPABASE_URL__", "https://x.test").replace("__SUPABASE_KEY__", "k"));
const MIME = { ".html": "text/html", ".js": "text/javascript", ".json": "application/json", ".css": "text/css", ".png": "image/png", ".jpg": "image/jpeg", ".webmanifest": "application/json" };
let hits = [];
const srv = http.createServer((q, r) => { let p = decodeURIComponent(q.url.split("?")[0]); hits.push(p); if (p.endsWith("/")) p += "index.html"; const f = path.join(SITE, p);
  fs.readFile(f, (e, d) => { if (e) { r.writeHead(404); return r.end(); } r.writeHead(200, { "Content-Type": MIME[path.extname(f)] || "application/octet-stream" }); r.end(d); }); }).listen(8096);
let fails = 0; const ok = (n, c, x = "") => { if (!c) fails++; console.log((c ? "OK  " : "KO  ") + n + (x ? "  [" + x + "]" : "")); };
(async () => {
  const b = await chromium.launch({ executablePath: "/usr/bin/google-chrome" }); const c = await b.newContext(); const p = await c.newPage();
  await p.route(/^https?:\/\/(?!localhost)/, r => r.abort());
  await p.goto("http://localhost:8096/index.html"); await p.evaluate(() => navigator.serviceWorker.ready); await p.waitForTimeout(1500);
  const keys = await p.evaluate(async () => { const out = []; for (const k of await caches.keys()) for (const r of await (await caches.open(k)).keys()) out.push(new URL(r.url).pathname); return out; });
  ok("pré-cache : 3 guides, guide.js, guide.css", ["/guide/", "/guide/en/", "/guide/ar/", "/guide/guide.js", "/guide/guide.css"].every(u => keys.includes(u)), keys.filter(k => k.startsWith("/guide")).join(","));
  // en ligne : réseau d'abord (une nouvelle version publiée s'affiche tout de suite)
  fs.writeFileSync(SITE + "/guide/en/index.html", fs.readFileSync(SITE + "/guide/en/index.html", "utf8").replace("<title>", "<title>NOUVEAU "));
  await p.reload(); await p.goto("http://localhost:8096/guide/en/?from=x#premium"); await p.waitForTimeout(500);
  ok("en ligne : version la plus récente servie (réseau d'abord)", /NOUVEAU/.test(await p.title()), await p.title());
  // hors ligne : copie gardée
  await c.setOffline(true); await p.goto("http://localhost:8096/guide/ar/").catch(() => {}); await p.waitForTimeout(500);
  ok("hors ligne : guide arabe servi depuis la copie, avec son style et son script", (await p.title()).length > 0 && await p.evaluate(() => !!document.querySelector(".gsearch") && getComputedStyle(document.body).backgroundColor !== "rgba(0, 0, 0, 0)" && document.querySelectorAll("#toc .tog").length > 0), await p.title());
  await p.goto("http://localhost:8096/guide/en/").catch(() => {}); await p.waitForTimeout(400);
  ok("hors ligne : dernier guide anglais vu (copie mise à jour au passage en ligne)", /NOUVEAU/.test(await p.title()), await p.title());
  await b.close(); srv.close(); fs.rmSync(SITE, { recursive: true, force: true }); console.log(fails ? `ÉCHECS : ${fails}` : "TOUT OK"); process.exit(fails ? 1 : 0);
})();
