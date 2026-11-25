/* EP-01 lot 2 : plusieurs familles (Mes familles, famille ouverte, changement par rechargement, créer ou rejoindre une autre famille, limite de 3).
   Sans navigateur visible, sans base : le client Supabase est remplacé par un double qui filtre de petites tables fictives. Usage : node ep01_familles_test.js [dossier de captures] */
const { chromium } = require("playwright");
const http = require("http"), fs = require("fs"), path = require("path");
const ROOT = path.resolve(__dirname, "../../../app"), SHOTS = process.argv[2] || null;
const MIME = { ".html": "text/html", ".js": "text/javascript", ".json": "application/json", ".css": "text/css", ".png": "image/png", ".webmanifest": "application/json" };
const srv = http.createServer((q, r) => { let p = decodeURIComponent(q.url.split("?")[0]); if (p.endsWith("/")) p += "index.html"; const f = path.join(ROOT, p);
  fs.readFile(f, (e, d) => { if (e) { r.writeHead(404); return r.end(); } r.writeHead(200, { "Content-Type": MIME[path.extname(f)] || "application/octet-stream" }); r.end(d); }); }).listen(8097);
// Double : chaque requête retient ses filtres « eq » ; le résultat vient de window.__db[table] filtré ; family_members avec la jointure « families ».
const STUB = `window.supabase = { createClient() {
  const sb = { auth: { getSession: async () => ({ data: { session: window.__session } }), onAuthStateChange() {}, signInWithPassword: async () => ({ data: {}, error: null }), updateUser: async () => ({}), signOut: async () => ({}) },
    rpc: async (n, a) => { try { const l = JSON.parse(sessionStorage.getItem("calls") || "[]"); l.push([n, a]); sessionStorage.setItem("calls", JSON.stringify(l)); } catch {} return window.__rpc(n, a); },
    from(table) { const eqs = []; const c = new Proxy({}, { get(_, k) {
      if (k === "eq") return (f, v) => { eqs.push([f, v]); return c; };
      if (k === "then") return r => { const db = window.__db, rows = (db[table] || []).filter(x => eqs.every(([f, v]) => !(f in x) || x[f] === v));
        if (table === "family_members") return r({ data: rows.map(m => ({ ...m, families: db.families.find(f => f.id === m.family_id) })), error: null });
        return r({ data: rows, error: null }); };
      return () => c; } }); return c; } };
  return sb; } };`;
const U = "u1";
const FAMS = [{ id: "fA", name: "Famille Alpha", created_by: "u1", plan: "founder", week_start: 1, weekend_days: [6, 7], timezone: "Europe/Paris", auto_validate: false },
  { id: "fB", name: "Famille Beta", created_by: "u9", plan: "founder", week_start: 1, weekend_days: [6, 7], timezone: "Europe/Paris", auto_validate: false },
  { id: "fC", name: "Famille Gamma", created_by: "u1", plan: "founder", week_start: 1, weekend_days: [6, 7], timezone: "Europe/Paris", auto_validate: false },
  { id: "fNew", name: "Neuve", created_by: "u1", plan: "founder", week_start: 1, weekend_days: [6, 7], timezone: "Europe/Paris", auto_validate: false },
  { id: "fD", name: "Famille Delta", created_by: "u1", plan: "founder", week_start: 1, weekend_days: [6, 7], timezone: "Europe/Paris", auto_validate: false }];
const MEM = id => ({ family_id: id, user_id: U, display_name: "Parent Test", role: id === "fB" ? "helper" : "parent", created_at: "2026-11-0" + (FAMS.findIndex(f => f.id === id) + 1) + "T10:00:00Z" });
const CHILDREN = [{ id: "kA", family_id: "fA", name: "Enfant Alpha", emoji: "🐻", color: "#2E9E5B", position: 0 }, { id: "kB", family_id: "fB", name: "Enfant Beta", emoji: "🦊", color: "#E8484F", position: 0 }];
let browser, fails = 0;
const ok = (n, c, extra = "") => { if (!c) fails++; console.log((c ? "OK  " : "KO  ") + n + (extra ? "  [" + extra + "]" : "")); };
const calls = (p, n) => p.evaluate(n => JSON.parse(sessionStorage.getItem("calls") || "[]").filter(c => c[0] === n).map(c => c[1]), n);   // journal gardé à travers les rechargements
async function open(o = {}) {
  const ctx = o.ctx || await browser.newContext({ locale: o.locale || "fr-FR", viewport: { width: o.w || 390, height: 844 }, colorScheme: o.dark ? "dark" : "light" });
  if (!o.ctx) {
    await ctx.route("**/config.js", r => r.fulfill({ contentType: "text/javascript", body: fs.readFileSync(ROOT + "/js/config.js", "utf8").replace("__SUPABASE_URL__", "https://x.test").replace("__SUPABASE_KEY__", "k") }));
    await ctx.route("**/supabase.min.js", r => r.fulfill({ contentType: "text/javascript", body: STUB }));
    await ctx.route("**/sw.js", r => r.abort());
    await ctx.route(/fonts\.(googleapis|gstatic)\.com/, r => r.abort());
    await ctx.addInitScript(([o, fams, mem, kids]) => {
      window.__session = { user: { id: "u1", email: "parent.test@example.invalid", user_metadata: { display_name: "Parent Test", intro_seen: true } } };
      const ids = [...(o.fams || ["fA", "fB"]), ...JSON.parse(sessionStorage.getItem("joined") || "[]")];   // familles créées ou rejointes depuis le début de la session
      window.__db = { families: fams, family_members: ids.map(i => mem[i]), children: kids, routines: [], completions: [], devices: [], child_devices: [], child_device_children: [] };
      window.__rpc = async (n, a) => {
        if (n === "create_child_code") return { data: "ABC234", error: null };
        if (n === "create_family") { if (o.limitErr) return { data: null, error: { message: "SF:family_limit" } }; sessionStorage.setItem("joined", '["fNew"]'); return { data: "fNew", error: null }; }
        if (n === "join_family") { sessionStorage.setItem("joined", JSON.stringify([o.joinId || "fB"])); return { data: o.joinId || "fB", error: null }; }
        return { data: null, error: null };
      };
      const L = o.ls || {}; for (const k in L) if (!sessionStorage.getItem("seeded")) localStorage.setItem(k, L[k]);
      sessionStorage.setItem("seeded", "1");
    }, [o, FAMS, Object.fromEntries(FAMS.map(f => [f.id, MEM(f.id)])), CHILDREN]);
  }
  const page = await ctx.newPage(); const errs = []; page.on("pageerror", e => errs.push(String(e)));
  await page.goto("http://localhost:8097/index.html" + (o.q || "")); await page.waitForTimeout(900);
  return { page, ctx, errs };
}
const shot = async (p, name) => { if (SHOTS) await p.screenshot({ path: path.join(SHOTS, name + ".png") }); };
const head = p => p.locator(".brand span").last().textContent();
const toast = async p => (await p.locator("#toast").textContent()) || "";
(async () => {
  browser = await chromium.launch({ executablePath: fs.existsSync("/usr/bin/google-chrome") ? "/usr/bin/google-chrome" : undefined, args: ["--no-sandbox"] });
  const PIN = { "sf:pinH": '{"s":"AA==","h":"AA==","i":1}', "sf:famOpen": '{"account":true}' };   // section Compte ouverte : « autre famille » y est avec une seule famille

  // 1. Compte de deux familles : la plus ancienne s'ouvre (R01-07 CA2) ; Mes familles (F01-09 CA2)
  let { page, ctx, errs } = await open({ ls: PIN });
  ok("1.1 première ouverture : la famille la plus ancienne (Alpha), ses enfants", /Alpha/.test(await head(page)) && await page.evaluate(() => S.children.map(k => k.name).join()) === "Enfant Alpha", await head(page));
  ok("1.2 la famille ouverte est gardée sur le téléphone (sf:family:<compte>)", await page.evaluate(() => localStorage.getItem("sf:family:u1")) === '"fA"');
  ok("1.3 Aujourd'hui : aucun moyen de changer de famille (F01-09 CA4)", await page.locator("[data-act=switchFamily]").count() === 0);
  for (const t of ["routines", "rewards", "history"]) { await page.evaluate(t => { S.tab = t; render(); }, t); if (await page.locator("[data-act=switchFamily]").count()) ok("1.3b " + t, false); }
  await page.evaluate(() => { S.tab = "family"; render(); });
  const rows = page.locator(".frow");
  ok("1.4 Mes familles : « Alpha · Parent » et « Beta · Proche »", await rows.count() === 2 && /Alpha · Parent/.test(await rows.nth(0).textContent()) && /Beta · Proche/.test(await rows.nth(1).textContent()), await page.locator(".flist").textContent());
  ok("1.5 la famille ouverte est annoncée sélectionnée (role option, aria-selected)", await page.locator(".flist").getAttribute("role") === "listbox" && await rows.nth(0).getAttribute("aria-selected") === "true" && await rows.nth(1).getAttribute("aria-selected") === "false" && /Ouverte/.test(await rows.nth(0).textContent()));
  await shot(page, "familles-fr-clair");
  // 2. Changer de famille : rechargement complet, Aujourd'hui, droits de la famille B (F01-09 CA3)
  await page.evaluate(() => { localStorage.setItem("sf:parentCache", JSON.stringify({ uid: "u1", family: { id: "fA", name: "Famille Alpha" }, me: { user_id: "u1", role: "parent" }, children: [{ id: "kA", name: "Enfant Alpha", emoji: "x", color: "#111111" }] })); });
  await Promise.all([page.waitForEvent("load"), page.click('[data-id="fB"][data-act=switchFamily]')]); await page.waitForTimeout(900);
  ok("2.1 Famille Beta ouverte sur Aujourd'hui, ses enfants seulement", /Beta/.test(await head(page)) && await page.evaluate(() => S.tab === "today" && S.children.map(k => k.name).join() === "Enfant Beta"), await head(page));
  ok("2.2 droit de B (Proche) : pas d'onglet Routines", await page.locator('[data-tab=routines]').count() === 0 && await page.locator('[data-tab=today]').count() === 1);
  ok("2.3 rien de l'ancienne famille : copie effacée puis remplacée par celle de B", await page.evaluate(() => { const c = JSON.parse(localStorage.getItem("sf:parentCache") || "null"); return !c || c.family.id === "fB"; }));
  ok("2.4 famille gardée : B", await page.evaluate(() => localStorage.getItem("sf:family:u1")) === '"fB"');
  const pg2 = await ctx.newPage(); await pg2.goto("http://localhost:8097/index.html"); await pg2.waitForTimeout(800);
  ok("2.5 fermer puis rouvrir : B se rouvre (R01-07 CA1)", /Beta/.test(await pg2.locator(".brand span").last().textContent()));
  await pg2.close(); await ctx.close();
  // 3. Copie d'une autre famille jamais utilisée (CA7)
  ({ page, ctx, errs } = await open({ ls: { ...PIN, "sf:family:u1": '"fB"' } }));
  await page.evaluate(() => { localStorage.setItem("sf:parentCache", JSON.stringify({ uid: "u1", family: { id: "fA", name: "Famille Alpha" }, me: { user_id: "u1", role: "parent" }, children: [] })); });
  ok("3.1 la copie d'Alpha n'est pas utilisée quand Beta est la famille ouverte", await page.evaluate(() => S.session = { user: { id: "u1" } }) && await page.evaluate(() => parentCache() === null));
  await ctx.close();
  // 4. Hors ligne : refus et on reste (CA5)
  ({ page, ctx, errs } = await open({ ls: PIN }));
  await page.evaluate(() => { S.tab = "family"; render(); }); await ctx.setOffline(true);
  await page.click('[data-id="fB"][data-act=switchFamily]'); await page.waitForTimeout(400);
  ok("4.1 hors ligne : « Il faut une connexion internet pour changer de famille. », Alpha reste", /connexion internet pour changer/.test(await toast(page)) && /Alpha/.test(await head(page)));
  await ctx.setOffline(false);
  // 4b. Écriture en cours : refusé
  await page.evaluate(() => { PENDING = 1; }); await page.click('[data-id="fB"][data-act=switchFamily]'); await page.waitForTimeout(300);
  ok("4.2 écriture en cours : refus et message", /action est en cours/.test(await toast(page)) && /Alpha/.test(await head(page)));
  await page.evaluate(() => { PENDING = 0; }); await ctx.close();
  // 5. Une seule famille : pas de Mes familles, mais « Créer ou rejoindre une autre famille » (CA1) ; Bienvenue avec Retour (F01-04 CA8)
  ({ page, ctx, errs } = await open({ ls: PIN, fams: ["fA"] }));
  await page.evaluate(() => { S.tab = "family"; render(); });
  ok("5.1 une famille : pas de Mes familles, bouton « autre famille » proposé", await page.locator(".flist").count() === 0 && await page.locator("[data-act=anotherFamily]").count() === 1);
  await page.click("[data-act=anotherFamily]"); await page.waitForTimeout(300);
  ok("5.2 Bienvenue avec « Retour » (créer et rejoindre)", await page.locator("#o-name").count() === 1 && await page.locator("#o-code").count() === 1 && await page.locator("[data-act=backFromOnboard]").count() === 1);
  await shot(page, "bienvenue-autre-fr-clair");
  await page.click("[data-act=backFromOnboard]"); await page.waitForTimeout(300);
  ok("5.3 Retour : la famille ouverte (Alpha, onglet Famille)", /Alpha/.test(await head(page)) && await page.locator("[data-act=anotherFamily]").count() === 1);
  await page.click("[data-act=anotherFamily]"); await page.fill("#o-name", "Famille Neuve");
  await Promise.all([page.waitForEvent("load"), page.click("[data-act=createFamily]")]); await page.waitForTimeout(700);
  const cf = await calls(page, "create_family");
  ok("5.4 création : create_family reçoit p_another = true (dernier paramètre, jamais omis)", cf.length === 1 && cf[0].p_another === true && cf[0].p_name === "Famille Neuve", JSON.stringify(cf));
  ok("5.5 la famille créée s'ouvre aussitôt (rechargement) et reste la famille ouverte", await page.evaluate(() => localStorage.getItem("sf:family:u1")) === '"fNew"' && /Neuve/.test(await head(page)), await head(page));
  await ctx.close();
  // 5c. Première famille (aucune) : p_another = false
  ({ page, ctx, errs } = await open({ ls: PIN, fams: [] }));
  ok("5.6 compte sans famille : Bienvenue sans « Retour »", await page.locator("#o-name").count() === 1 && await page.locator("[data-act=backFromOnboard]").count() === 0);
  await page.click("[data-act=createFamily]"); await page.waitForTimeout(500);
  const cf3 = await calls(page, "create_family");
  ok("5.7 première famille : p_another = false", cf3.length === 1 && cf3[0].p_another === false, JSON.stringify(cf3));
  await ctx.close();
  // 6. Limite de 3 familles créées (DEC-19) : message à la place de « Créer », « Rejoindre » reste
  ({ page, ctx, errs } = await open({ ls: PIN, fams: ["fA", "fC", "fD"] }));
  await page.evaluate(() => { S.tab = "family"; render(); }); await page.click("[data-act=anotherFamily]"); await page.waitForTimeout(300);
  ok("6.1 3 familles créées : message du maximum, pas de formulaire de création, rejoindre proposé", /3 familles, le maximum/.test(await page.locator("main").textContent()) && await page.locator("#o-name").count() === 0 && await page.locator("#o-code").count() === 1);
  await shot(page, "limite-fr-clair");
  await ctx.close();
  // 6b. Le serveur refuse aussi (SF:family_limit) : message traduit
  ({ page, ctx, errs } = await open({ ls: PIN, fams: ["fA"], limitErr: true }));
  await page.evaluate(() => { S.tab = "family"; render(); }); await page.click("[data-act=anotherFamily]"); await page.click("[data-act=createFamily]"); await page.waitForTimeout(400);
  ok("6.2 refus du serveur : « Vous avez déjà créé 3 familles… », rien ne change", /3 familles, le maximum/.test(await toast(page)) && await page.locator("#o-name").count() === 1);
  await ctx.close();
  // 7. Rejoindre depuis Famille : la famille rejointe s'ouvre, message gardé (CA5)
  ({ page, ctx, errs } = await open({ ls: PIN, fams: ["fA"], joinId: "fB" }));
  await page.evaluate(() => { S.tab = "family"; render(); }); await page.click("[data-act=anotherFamily]"); await page.fill("#o-code", "ABC234");
  await Promise.all([page.waitForEvent("load"), page.click("[data-act=joinFamily]")]); await page.waitForTimeout(1000);
  ok("7.1 famille rejointe : ouverte (rechargement), message « Vous avez rejoint… »", await page.evaluate(() => localStorage.getItem("sf:family:u1")) === '"fB"' && /Beta/.test(await head(page)) && /./.test(await toast(page)), await toast(page));
  await ctx.close();
  // 8. Retiré de la famille ouverte : une autre s'ouvre (CA3), sinon Bienvenue
  ({ page, ctx, errs } = await open({ ls: { ...PIN, "sf:family:u1": '"fB"' } }));
  ok("8.0 départ : Beta ouverte", /Beta/.test(await head(page)));
  await page.evaluate(() => { window.__db.family_members = window.__db.family_members.filter(m => m.family_id !== "fB"); });
  await Promise.all([page.waitForEvent("load"), page.evaluate(() => { document.dispatchEvent(new Event("visibilitychange")); })]).catch(() => {});
  await page.waitForTimeout(900);
  ok("8.1 retiré de Beta : Alpha s'ouvre", /Alpha/.test(await head(page)) && await page.evaluate(() => localStorage.getItem("sf:family:u1")) === '"fA"', await head(page));
  await page.evaluate(() => { window.__db.family_members = []; S.session = { user: { id: "u1" } }; return loadParent().then(render); });
  ok("8.2 plus aucune famille : Bienvenue, sans « Retour »", await page.locator("#o-name").count() === 1 && await page.locator("[data-act=backFromOnboard]").count() === 0);
  await ctx.close();
  // 9. Arabe et sombre : sens, pas de défilement horizontal, 360 px
  for (const [lang, dark, w] of [["ar", false, 360], ["fr", true, 360], ["ar", true, 390]]) {
    ({ page, ctx, errs } = await open({ ls: PIN, locale: lang, dark, w, q: lang === "ar" ? "?lang=ar" : "" }));
    await page.evaluate(() => { S.tab = "family"; render(); });
    const dir = await page.evaluate(() => document.documentElement.dir), tag = `${lang}-${dark ? "sombre" : "clair"}`;
    ok(`9.${tag}.0 sens de lecture`, lang === "ar" ? dir === "rtl" : dir !== "rtl");
    ok(`9.${tag}.1 Mes familles lu et marqué`, await page.locator(".frow").count() === 2 && await page.locator('.frow[aria-selected="true"]').count() === 1 && await page.locator(".frow .fopen").count() === 1);
    const cr = await page.evaluate(() => { const rgb = c => c.match(/[\d.]+/g).slice(0, 3).map(Number), L = c => { const [r, g, b] = rgb(c).map(v => { v /= 255; return v <= .03928 ? v / 12.92 : ((v + .055) / 1.055) ** 2.4; }); return .2126 * r + .7152 * g + .0722 * b; };
      const e = document.querySelector(".frow .fopen"), a = L(getComputedStyle(e).color), b = L(getComputedStyle(e.parentElement).backgroundColor); return (Math.max(a, b) + .05) / (Math.min(a, b) + .05); });
    ok(`9.${tag}.1b « ✓ Ouverte » : contraste d'au moins 4,5:1 (X-ACC-05)`, cr >= 4.5, cr.toFixed(2));
    ok(`9.${tag}.2 pas de défilement horizontal`, !(await page.evaluate(() => document.documentElement.scrollWidth > document.documentElement.clientWidth)));
    await shot(page, "familles-" + tag);
    await page.click("[data-act=anotherFamily]"); await page.waitForTimeout(200); await shot(page, "bienvenue-autre-" + tag);
    ok(`9.${tag}.3 Bienvenue sans défilement horizontal`, !(await page.evaluate(() => document.documentElement.scrollWidth > document.documentElement.clientWidth)));
    ok(`9.${tag}.4 aucune erreur de script`, errs.length === 0, errs.join(" | "));
    await ctx.close();
  }
  console.log(fails ? `${fails} cas en échec` : "Tous les cas sont conformes");
  await browser.close(); srv.close(); process.exit(fails ? 1 : 0);
})().catch(e => { console.error(e); process.exit(2); });
