/* EP-01 lot 3 : rangée d'avatars commune (R00-10, DEC-12) et « Tout valider » selon l'enfant affiché (F05-03 CA9, DEC-09).
   Sans navigateur visible, sans base : le client Supabase est remplacé par un double qui filtre de petites tables fictives. Usage : node ep01_rangee_test.js [dossier de captures] */
const { chromium } = require("playwright");
const http = require("http"), fs = require("fs"), path = require("path");
const ROOT = path.resolve(__dirname, "../../../app"), SHOTS = process.argv[2] || null;
const MIME = { ".html": "text/html", ".js": "text/javascript", ".json": "application/json", ".css": "text/css", ".png": "image/png", ".webmanifest": "application/json" };
const srv = http.createServer((q, r) => { let p = decodeURIComponent(q.url.split("?")[0]); if (p.endsWith("/")) p += "index.html"; const f = path.join(ROOT, p);
  fs.readFile(f, (e, d) => { if (e) { r.writeHead(404); return r.end(); } r.writeHead(200, { "Content-Type": MIME[path.extname(f)] || "application/octet-stream" }); r.end(d); }); }).listen(8097);
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
    window.__session = { user: { id: "u1", email: "parent.test@example.invalid", user_metadata: { display_name: "Parent Test", intro_seen: true } } };
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
  await page.goto("http://localhost:8097/index.html" + (o.q || "")); await page.waitForTimeout(900);
  await page.evaluate(t => { S.tab = t; render(); }, o.tab || "today");
  return { page, ctx, errs };
}
const shot = async (p, name) => { if (SHOTS) await p.screenshot({ path: path.join(SHOTS, name + ".png") }); };
const toast = async p => (await p.locator("#toast").textContent()) || "";
const noHScroll = p => p.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth && (!document.querySelector("dialog[open] .sheet-in") || document.querySelector("dialog[open] .sheet-in").scrollWidth <= document.querySelector("dialog[open]").clientWidth + 1));
const PIN = { "sf:pinH": '{"s":"AA==","h":"AA==","i":1}' };

const rts = n => Array.from({ length: n }, (_, i) => ({ child_id: "k" + (i + 1), title: "Routine de " + NAMES[i] }));
const pend = [{ routine_id: "r0", child_id: "k1" }, { routine_id: "r1", child_id: "k2" }, { routine_id: "r1", child_id: "k2", day: "2020-01-01" }];
const row = p => p.locator(".kidrow .kidchip");
(async () => {
  browser = await chromium.launch({ executablePath: fs.existsSync("/usr/bin/google-chrome") ? "/usr/bin/google-chrome" : undefined, args: ["--no-sandbox"] });
  // 1. Deux enfants : « Tous » d'abord, choisi (CA1) ; Aujourd'hui montre tous les enfants
  let { page, ctx, errs } = await open({ kids: 2, routines: rts(2), pend });
  const lbl = async () => (await row(page).allTextContents()).map(x => x.replace(/\s+/g, " ").trim());
  const l1 = await lbl();
  ok("1.1 rangée : Tous puis les deux enfants (CA1)", l1.length === 3 && /Tous/.test(l1[0]) && /Enfant Un/.test(l1[1]), l1.join("|"));
  ok("1.2 Tous est choisi (aria-selected)", await row(page).first().getAttribute("aria-selected") === "true");
  ok("1.3 deux blocs d'enfants et « Tout valider (3) »", await page.locator("section.kid").count() === 2 && /Tout valider \(3\)/.test(await page.locator("[data-act=validateAll]").textContent()));
  ok("1.4 cibles >= 44 px", await page.evaluate(() => [...document.querySelectorAll(".kidchip")].every(b => b.getBoundingClientRect().height >= 43.5 && b.getBoundingClientRect().width >= 43.5)));
  // 2. Choisir le premier enfant (CA2, CA3)
  await row(page).nth(1).click();
  ok("2.1 un seul enfant sur Aujourd'hui (CA2)", await page.locator("section.kid").count() === 1 && /Enfant Un/.test(await page.locator("section.kid h2").textContent()));
  ok("2.2 l'enfant est marqué, Tous ne l'est plus (CA6)", await row(page).nth(1).getAttribute("aria-selected") === "true" && await row(page).first().getAttribute("aria-selected") === "false");
  ok("2.3 « À valider » ne compte que lui : Tout valider (1)", /Tout valider \(1\)/.test(await page.locator("[data-act=validateAll]").textContent()));
  await shot(page, "rangee-aujourdhui-fr-390");
  await page.click("[data-act=tab][data-tab=routines]");
  ok("2.4 Routines : même enfant, rangée sans Tous (CA3)", (await lbl()).length === 2 && await row(page).first().getAttribute("aria-selected") === "true" && /Routine de Enfant Un/.test(await page.locator(".rlist").first().textContent()));
  await row(page).nth(1).click();
  await page.click("[data-act=tab][data-tab=rewards]");
  ok("2.5 Récompenses : l'enfant choisi sur Routines est gardé", await row(page).nth(1).getAttribute("aria-selected") === "true" && (await lbl()).length === 2);
  await page.click("[data-act=tab][data-tab=history]");
  ok("2.6 Historique : même enfant, rangée présente", await row(page).nth(1).getAttribute("aria-selected") === "true");
  await page.click("[data-act=tab][data-tab=today]");
  ok("2.7 retour sur Aujourd'hui : enfant 2 toujours choisi", await page.locator("section.kid").count() === 1 && /Enfant Deux/.test(await page.locator("section.kid h2").textContent()));
  // 3. Tout valider ne valide que l'enfant affiché (CA9)
  await page.click("[data-act=validateAll]"); await page.waitForTimeout(400);
  const up = (await ss(page, "writes")).filter(w => w.table === "completions" && w.op === "update");
  const left = await page.evaluate(() => S.completions.filter(c => !c.validated_at).map(c => c.child_id));
  ok("3.1 une écriture, bornée à l'enfant (in child_id)", up.length === 1, JSON.stringify(up.map(u => u.eqs)));
  ok("3.2 restent en attente : celles de l'enfant 1 seulement", left.length === 1 && left[0] === "k1", left.join(","));
  // 4. Tous : tout valider comme avant (CA6 de F05-03)
  await row(page).first().click();
  ok("4.1 Tous : deux blocs, Tout valider (1)", await page.locator("section.kid").count() === 2 && /Tout valider \(1\)/.test(await page.locator("[data-act=validateAll]").textContent()));
  await page.click("[data-act=tab][data-tab=routines]");
  ok("4.2 depuis Tous, Routines montre le dernier enfant choisi (Enfant Deux)", await row(page).nth(1).getAttribute("aria-selected") === "true");
  // 5. Choix gardé sur le téléphone, retour à Tous au changement de famille
  await page.click("[data-act=tab][data-tab=today]"); await row(page).nth(1).click();
  const kept = await page.evaluate(() => localStorage.getItem("sf:shown:fA"));
  ok("5.1 choix gardé sur le téléphone", /"all":false/.test(kept || "") && /k1/.test(kept), kept);
  await page.reload(); await page.waitForTimeout(900);
  ok("5.2 après rechargement, enfant 1 toujours choisi", await page.locator("section.kid").count() === 1 && /Enfant Un/.test(await page.locator("section.kid h2").textContent()));
  ok("5.3 pas d'erreur", errs.length === 0, errs.join(";")); await ctx.close();

  // 6. Un seul enfant : aucune rangée sur Aujourd'hui, Récompenses, Historique ; Routines garde le choix (CA5)
  ({ page, ctx, errs } = await open({ kids: 1, routines: rts(1) }));
  ok("6.1 Aujourd'hui : aucune rangée", await row(page).count() === 0);
  for (const tb of ["rewards", "history"]) { await page.click(`[data-act=tab][data-tab=${tb}]`); ok("6.2 " + tb + " : aucune rangée", await row(page).count() === 0); }
  await page.click("[data-act=tab][data-tab=routines]");
  ok("6.3 Routines : le choix de l'enfant reste (F04-01 CA1)", await row(page).count() === 1);
  await ctx.close();

  // 7. Cinq enfants à 360 px, fr et ar, clair et sombre
  for (const [lang, dark] of [["fr", false], ["ar", true], ["en", false]]) {
    ({ page, ctx, errs } = await open({ kids: 5, routines: rts(5), pend, w: 360, locale: lang + "-" + (lang === "ar" ? "SA" : lang.toUpperCase()), dark, q: "?lang=" + lang }));
    const n = await row(page).count();
    ok(`7.${lang} cinq enfants + Tous, aucun défilement horizontal de la page`, n === 6 && await noHScroll(page), "n=" + n);
    ok(`7.${lang} toutes les puces dans l'écran`, await page.evaluate(() => [...document.querySelectorAll(".kidchip")].every(b => { const r = b.getBoundingClientRect(); return r.left >= 0 && r.right <= innerWidth + 0.5; })));
    ok(`7.${lang} puces >= 44 px`, await page.evaluate(() => [...document.querySelectorAll(".kidchip")].every(b => b.getBoundingClientRect().height >= 43.5)));
    if (lang === "ar") ok("7.ar sens droite à gauche : Tous à droite du premier enfant", await page.evaluate(() => { const b = [...document.querySelectorAll(".kidchip")]; return b[0].getBoundingClientRect().right > b[1].getBoundingClientRect().right || b[0].getBoundingClientRect().top < b[1].getBoundingClientRect().top; }));
    await row(page).nth(2).click();
    ok(`7.${lang} annonce : aria-label du groupe et sélection`, !!(await page.locator(".kidrow").getAttribute("aria-label")) && await row(page).nth(2).getAttribute("aria-selected") === "true");
    await shot(page, `rangee-5-${lang}-360-${dark ? "sombre" : "clair"}`);
    await page.click("[data-act=tab][data-tab=routines]"); await shot(page, `rangee-routines-${lang}-360-${dark ? "sombre" : "clair"}`);
    ok(`7.${lang} pas d'erreur`, errs.length === 0, errs.join(";")); await ctx.close();
  }
  console.log(fails ? "\n" + fails + " KO" : "\nTous conformes"); await browser.close(); srv.close(); process.exit(fails ? 1 : 0);
})();
