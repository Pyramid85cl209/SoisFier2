// EP-09 thème G : guide commun (guide.js, guide.css) — recherche fr/en/ar, ancres communes, sommaire replié, sans débordement.
const { chromium } = require("/opt/npm-tools/node_modules/playwright");
const http = require("http"), fs = require("fs"), path = require("path");
const ROOT = path.resolve(__dirname, "../../..");
const MIME = { ".html": "text/html", ".js": "text/javascript", ".json": "application/json", ".css": "text/css", ".png": "image/png", ".jpg": "image/jpeg" };
const srv = http.createServer((q, r) => { let p = decodeURIComponent(q.url.split("?")[0]); if (p.endsWith("/")) p += "index.html"; const f = path.join(ROOT, p);
  fs.readFile(f, (e, d) => { if (e) { r.writeHead(404); return r.end(); } r.writeHead(200, { "Content-Type": MIME[path.extname(f)] || "application/octet-stream" }); r.end(d); }); }).listen(8098);
let fails = 0; const ok = (n, c, x = "") => { if (!c) fails++; console.log((c ? "OK  " : "KO  ") + n + (x ? "  [" + x + "]" : "")); };
const PAGES = { fr: "/guide/", en: "/guide/en/", ar: "/guide/ar/" };
const Q = { fr: ["Pause", "récompense", "zzzzqq"], en: ["pause", "reward", "zzzzqq"], ar: ["التوقّف", "مكافأة", "zzzzqq"] };
(async () => {
  const b = await chromium.launch({ executablePath: "/usr/bin/google-chrome" });
  for (const lg of ["fr", "en", "ar"]) for (const [w, h, nm] of [[1280, 800, "bureau"], [390, 800, "mobile"]]) {
    const c = await b.newContext({ viewport: { width: w, height: h } }); const p = await c.newPage(); const errs = [];
    p.on("pageerror", e => errs.push(String(e)));
    await p.route(/^https?:\/\/(?!localhost)/, r => r.abort());
    await p.goto("http://localhost:8098" + PAGES[lg]); await p.waitForTimeout(300);
    const T = `${lg} ${nm} `;
    ok(T + "aucune erreur JS", errs.length === 0, errs.join("|"));
    ok(T + "pas de débordement horizontal", await p.evaluate(() => document.documentElement.scrollWidth - innerWidth) <= 0);
    if (nm === "mobile") { await p.click("#menu"); await p.waitForTimeout(250); }
    // sommaire réduit : une partie seulement dépliée au départ
    const open = await p.evaluate(() => [...document.querySelectorAll("#toc .tog")].filter(b => b.getAttribute("aria-expanded") === "true").length);
    ok(T + "sommaire réduit (1 partie dépliée)", open === 1, "dépliées=" + open);
    await p.click("#toc .tog[aria-expanded=false]"); const open2 = await p.evaluate(() => [...document.querySelectorAll("#toc .tog")].filter(b => b.getAttribute("aria-expanded") === "true").length);
    ok(T + "une partie se déplie à la main", open2 === 2);
    // recherche
    await p.fill("#gq", Q[lg][0]); await p.waitForTimeout(150);
    const n1 = await p.locator("#gres a").count(); const st = await p.textContent("#gstat");
    ok(T + "recherche « " + Q[lg][0] + " » : résultats en liens", n1 > 0 && !!st, n1 + " / " + st);
    ok(T + "zone d'annonce en direct", await p.getAttribute("#gstat", "aria-live") === "polite" && await p.getAttribute("#gstat", "role") === "status");
    await p.fill("#gq", Q[lg][2]); await p.waitForTimeout(100);
    const none = (await p.textContent("#gstat")).trim();
    ok(T + "« aucun résultat » annoncé", none === { fr: "Aucun résultat.", en: "No results.", ar: "لا توجد نتائج." }[lg] && await p.locator("#gres a").count() === 0, none);
    await p.fill("#gq", Q[lg][1]); await p.waitForTimeout(100);
    ok(T + "2e recherche", await p.locator("#gres a").count() > 0);
    // suivre un résultat : la cible est en haut de page
    const href = await p.getAttribute("#gres a >> nth=0", "href"); await p.click("#gres a >> nth=0"); await p.waitForTimeout(1500);
    const top = await p.evaluate(h => document.getElementById(h.slice(1)).getBoundingClientRect().top, href);
    ok(T + "résultat → cible visible en haut", top >= -5 && top < 140, href + " top=" + Math.round(top));
    if (nm === "bureau") {
      // ancres communes : mêmes identifiants dans les 3 langues, liens du sommaire sans cible manquante
      const miss = await p.evaluate(() => [...document.querySelectorAll('a[href^="#"]')].map(a => a.getAttribute("href").slice(1)).filter(i => i && !document.getElementById(i)));
      ok(T + "aucun lien interne cassé", miss.length === 0, miss.join(","));
      // DT14-11 : clic sur un lien du sommaire loin dans la page, images paresseuses au-dessus
      await p.evaluate(() => scrollTo(0, 0)); const target = "p5-week"; await p.click("#toc a[href='#" + target + "']", { force: true }).catch(async () => { await p.evaluate(t => { location.hash = t; }, target); });
      await p.waitForTimeout(1800);
      const t2 = await p.evaluate(t => document.getElementById(t).getBoundingClientRect().top, target);
      ok(T + "ancre lointaine " + target + " en haut après chargement des images", t2 >= -5 && t2 < 140, "top=" + Math.round(t2));
      const ids = await p.evaluate(() => ["p0", "p1", "p2a", "p2b", "p2c", "p2d", "p3", "p4", "p5", "p6", "premium", "p7"].filter(i => !document.getElementById(i)));
      ok(T + "ancres communes #p0..#p7 et #premium", ids.length === 0, ids.join(","));
    }
    await c.close();
  }
  const sets = {}; for (const lg of ["fr", "en", "ar"]) sets[lg] = (fs.readFileSync(ROOT + (lg === "fr" ? "/guide/index.html" : `/guide/${lg}/index.html`), "utf8").match(/(?:<section class="part" id|<h3 id)="[^"]+"/g) || []).map(s => s.replace(/.*="/, "")).join(",");
  ok("mêmes ancres dans les trois langues (DT14-08)", sets.fr === sets.en && sets.en === sets.ar);
  await b.close(); srv.close(); console.log(fails ? `ÉCHECS : ${fails}` : "TOUT OK"); process.exit(fails ? 1 : 0);
})();
