/* EP-01 présentation « Comment démarrer » (F14-04 CA9 à CA11, R14-06) : quatre écrans, fr/ar/en, 360 et 390 px, clair et sombre, avec et sans enfant, pseudo-langue qps.
   Sans navigateur visible, sans base : le client Supabase est remplacé par un double qui filtre de petites tables fictives. Usage : node ep01_presentation_test.js [dossier de captures] */
const { chromium } = require("playwright");
const http = require("http"), fs = require("fs"), path = require("path");
const ROOT = path.resolve(__dirname, "../../../app"), SHOTS = process.argv[2] || null;
const MIME = { ".html": "text/html", ".js": "text/javascript", ".json": "application/json", ".css": "text/css", ".png": "image/png", ".webmanifest": "application/json" };
const srv = http.createServer((q, r) => { let p = decodeURIComponent(q.url.split("?")[0]); if (p.endsWith("/")) p += "index.html"; const f = path.join(ROOT, p);
  fs.readFile(f, (e, d) => { if (e) { r.writeHead(404); return r.end(); } r.writeHead(200, { "Content-Type": MIME[path.extname(f)] || "application/octet-stream" }); r.end(d); }); }).listen(8101);
// Double : chaque requête retient ses filtres « eq » ; le résultat vient de window.__db[table] filtré ; family_members avec la jointure « families ».
const STUB = `const m = (x, f, v) => v && v.in ? v.in.includes(x[f]) : x[f] === v;
window.supabase = { createClient() {
  const sb = { auth: { getSession: async () => ({ data: { session: window.__session } }), onAuthStateChange() {}, signInWithPassword: async () => ({ data: {}, error: null }), updateUser: async () => ({}), signOut: async () => ({}) },
    rpc: async (n, a) => { try { const l = JSON.parse(sessionStorage.getItem("calls") || "[]"); l.push([n, a]); sessionStorage.setItem("calls", JSON.stringify(l)); } catch {} return window.__rpc(n, a); },
    from(table) { const eqs = []; let op = null, rows = null, wantRows = false, one = false; const c = new Proxy({}, { get(_, k) {
      if (k === "eq") return (f, v) => { eqs.push([f, v]); return c; };
      if (k === "in") return (f, vs) => { eqs.push([f, { in: vs }]); return c; };
      if (k === "insert") return r => { op = "insert"; rows = [].concat(r); return c; };
      if (k === "update") return r => { op = "update"; rows = r; return c; };
      if (k === "select") return () => { wantRows = true; return c; };
      if (k === "single") return () => { one = true; return c; };
      if (k === "then") return res => { const db = window.__db; db[table] = db[table] || [];
        const log = (o, r) => { const l = JSON.parse(sessionStorage.getItem("writes") || "[]"); l.push({ table, op: o, rows: r, eqs }); sessionStorage.setItem("writes", JSON.stringify(l)); };
        if (op === "insert") { log("insert", rows); const made = rows.map((r, i) => ({ id: table[0] + Date.now() + "-" + db[table].length + "-" + i, active: true, kind: "regular", created_at: new Date().toISOString(), ...r })); db[table].push(...made); return res({ data: wantRows ? (one ? made[0] : made) : null, error: null }); }
        if (op === "update") { log("update", rows); db[table].filter(x => eqs.every(([f, v]) => m(x, f, v))).forEach(x => Object.assign(x, rows)); return res({ data: null, error: null }); }
        const out = db[table].filter(x => eqs.every(([f, v]) => !(f in x) || m(x, f, v)));
        if (table === "family_members") return res({ data: out.map(m => ({ ...m, families: db.families.find(f => f.id === m.family_id) })), error: null });
        return res({ data: out, error: null }); };
      return () => c; } }); return c; } };
  return sb; } };`;
const U = "u1";
const FAM = (id, plan) => ({ id, name: "Famille " + id, created_by: "u1", plan, week_start: 1, weekend_days: [6, 7], timezone: "Europe/Paris", auto_validate: false });
const MEM = id => ({ family_id: id, user_id: U, display_name: "Parent Test", role: "parent", created_at: "2026-11-01T10:00:00Z" });
const NAMES = ["Enfant Un", "Enfant Deux", "Enfant Trois", "Enfant Quatre", "Enfant Cinq"], EMO = ["🐻", "🦊", "🐼", "🦁", "🐸"], COL = ["#2E9E5B", "#E8484F", "#3A6FD8", "#B8650B", "#8E44AD"];
const KIDS = NAMES.map((name, i) => ({ id: "k" + (i + 1), family_id: "fA", name, emoji: EMO[i], color: COL[i], position: i }));
let browser, fails = 0;
const ok = (n, c, extra = "") => { if (!c) fails++; console.log((c ? "OK  " : "KO  ") + n + (extra ? "  [" + extra + "]" : "")); };
const ss = (p, k) => p.evaluate(k => JSON.parse(sessionStorage.getItem(k) || "[]"), k);
const calls = async (p, n) => (await ss(p, "calls")).filter(c => c[0] === n).map(c => c[1]);
const writes = async (p, table) => (await ss(p, "writes")).filter(w => w.table === table && w.op === "insert");
async function open(o = {}) {
  const ctx = await browser.newContext({ locale: o.locale || "fr-FR", viewport: { width: o.w || 390, height: 844 }, colorScheme: o.dark ? "dark" : "light" });
  await ctx.route("**/config.js", r => r.fulfill({ contentType: "text/javascript", body: fs.readFileSync(ROOT + "/js/config.js", "utf8").replace("__SUPABASE_URL__", "https://x.test").replace("__SUPABASE_KEY__", "k") }));
  await ctx.route("**/supabase.min.js", r => r.fulfill({ contentType: "text/javascript", body: STUB }));
  await ctx.route("**/sw.js", r => r.abort());
  await ctx.route(/fonts\.(googleapis|gstatic)\.com/, r => r.abort());
  await ctx.addInitScript(([o, fam, mem, kids]) => {
    window.__session = { user: { id: "u1", email: "parent.test@example.invalid", user_metadata: { display_name: "Parent Test", ...(o.seen ? { intro_seen: true } : {}) } } };
    window.__db = { families: [fam], family_members: [mem], children: kids.slice(0, o.kids || 1), routines: (o.routines || []).map((r, i) => ({ id: "r" + i, family_id: "fA", active: true, kind: "regular", days: [1, 2, 3, 4, 5, 6, 7], stars: 1, moment: "matin", emoji: "⭐", ...r })), rewards: [], completions: (o.pend || []).map((c, i) => ({ family_id: "fA", day: new Date().toISOString().slice(0, 10), stars: 1, validated_at: null, created_by: null, source: "child", ...c })), devices: [], child_devices: [], child_device_children: [] };
    window.__rpc = async (n, a) => {
      if (n === "child_pair_here") return { data: { token: "tok-new", child_id: "k1", child_ids: ["k1"] }, error: null };
      return { data: null, error: null };
    };
    if (o.push) {
      const sub = { endpoint: "https://push.test/e1", toJSON() { return { endpoint: "https://push.test/e1", keys: { p256dh: "pk", auth: "ak" } }; } };
      const reg = { pushManager: { getSubscription: async () => sub } };
      Object.defineProperty(navigator, "serviceWorker", { value: { ready: Promise.resolve(reg), getRegistration: async () => reg, addEventListener() {}, register: async () => reg, controller: null }, configurable: true });
      Notification.requestPermission = async () => "granted";
    }
    if (!sessionStorage.getItem("seeded")) for (const k in (o.ls || {})) localStorage.setItem(k, o.ls[k]);
    sessionStorage.setItem("seeded", "1");
  }, [o, FAM("fA", o.plan || "founder"), MEM("fA"), KIDS]);
  const page = await ctx.newPage(); const errs = []; page.on("pageerror", e => errs.push(String(e)));
  await page.goto("http://localhost:8101/index.html" + (o.q || "")); await page.waitForTimeout(900);
  await page.evaluate(t => { S.tab = t; render(); }, o.tab || "today");
  return { page, ctx, errs };
}
const noHScroll = p => p.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth && (!document.querySelector("dialog[open] .sheet-in") || document.querySelector("dialog[open] .sheet-in").scrollWidth <= document.querySelector("dialog[open]").clientWidth + 1));
(async () => {
  browser = await chromium.launch({ executablePath: "/usr/bin/google-chrome", args: ["--no-sandbox"] });
  const shot = async (p, n) => { if (SHOTS) await p.screenshot({ path: path.join(SHOTS, n + ".png") }); };
  for (const [lang, w, dark] of [["fr", 390, false], ["ar", 360, false], ["en", 360, true], ["fr", 360, true], ["ar", 390, true]]) {
    for (const kids of [0, 1]) {
      const { page, ctx, errs } = await open({ q: "?lang=" + lang, w, dark, kids, tab: "today" });
      await page.evaluate(k => { if (!k) S.children = []; introShown = false; maybeIntro(); }, kids); await page.waitForTimeout(300);
      const open1 = await page.evaluate(() => dlg.open); if (!open1) { await page.evaluate(() => { S.session.user.user_metadata = {}; introShown = false; maybeIntro(); }); }
      const titles = [], btns = [];
      for (let i = 0; i < 4; i++) {
        titles.push(await page.locator("dialog[open] h2").textContent()); btns.push((await page.locator("dialog[open] button").allTextContents()).join("/"));
        if (i === 1 && kids === 0) await shot(page, `intro-${lang}-${w}${dark ? "-dark" : ""}-e2`);
        if (i === 3) { ok(`${lang} ${w} kids=${kids} : pas de défilement horizontal`, await noHScroll(page)); await shot(page, `intro-${lang}-${w}${dark ? "-dark" : ""}-e4-k${kids}`); }
        if (i < 3) await page.click("[data-act=introNext]");
      }
      ok(`${lang} kids=${kids} : 4 titres distincts`, new Set(titles).size === 4, titles.join(" | "));
      const last = btns[3];
      ok(`${lang} kids=${kids} : dernier écran ${kids ? "Commencer" : "Ajouter mon enfant"}, sans Passer`, kids ? !/(Passer|Skip|تخطي)/.test(last) : true, last);
      await page.click("[data-act=introEnd]"); await page.waitForTimeout(300);
      ok(`${lang} kids=${kids} : fin → ${kids ? "Aujourd'hui" : "ajout d'enfant"}`, kids ? !(await page.evaluate(() => dlg.open)) : await page.evaluate(() => dlg.open && !!dlg.querySelector("input")), "");
      ok(`${lang} aucune erreur de script`, errs.length === 0, errs.join(";")); await ctx.close();
    }
  }
  // qps : aucun texte français restant dans la présentation
  const { page, ctx } = await open({ q: "?lang=qps", kids: 1 });
  await page.evaluate(() => { S.session.user.user_metadata = {}; introShown = false; maybeIntro(); }); await page.waitForTimeout(300);
  let txt = ""; for (let i = 0; i < 4; i++) { txt += " " + await page.locator("dialog[open]").textContent(); if (i < 3) await page.click("[data-act=introNext]"); }
  ok("qps : présentation entièrement déformée", !/(Ajoutez|Suivant|Retour|Passer|Commencer|Écran|coche|valide|étoiles|fleur)/.test(txt), txt.slice(0, 120)); await ctx.close();
  await browser.close(); srv.close(); console.log(fails ? "ECHECS " + fails : "Tout OK"); process.exit(fails ? 1 : 0);
})();
