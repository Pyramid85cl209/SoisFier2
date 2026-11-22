/* EP-01 lot 3 : modèles par catégorie (33), démarrage rapide par âge, ajout groupé à plusieurs enfants, « Rappel à », adresse d'envoi des rappels (jetons Mode enfant ici).
   Sans navigateur visible, sans base : le client Supabase est remplacé par un double qui filtre de petites tables fictives. Usage : node ep01_familles_test.js [dossier de captures] */
const { chromium } = require("playwright");
const http = require("http"), fs = require("fs"), path = require("path");
const ROOT = path.resolve(__dirname, "../../../app"), SHOTS = process.argv[2] || null;
const MIME = { ".html": "text/html", ".js": "text/javascript", ".json": "application/json", ".css": "text/css", ".png": "image/png", ".webmanifest": "application/json" };
const srv = http.createServer((q, r) => { let p = decodeURIComponent(q.url.split("?")[0]); if (p.endsWith("/")) p += "index.html"; const f = path.join(ROOT, p);
  fs.readFile(f, (e, d) => { if (e) { r.writeHead(404); return r.end(); } r.writeHead(200, { "Content-Type": MIME[path.extname(f)] || "application/octet-stream" }); r.end(d); }); }).listen(8098);
// Double : chaque requête retient ses filtres « eq » ; le résultat vient de window.__db[table] filtré ; family_members avec la jointure « families ».
const STUB = `window.supabase = { createClient() {
  const sb = { auth: { getSession: async () => ({ data: { session: window.__session } }), onAuthStateChange() {}, signInWithPassword: async () => ({ data: {}, error: null }), updateUser: async () => ({}), signOut: async () => ({}) },
    rpc: async (n, a) => { try { const l = JSON.parse(sessionStorage.getItem("calls") || "[]"); l.push([n, a]); sessionStorage.setItem("calls", JSON.stringify(l)); } catch {} return window.__rpc(n, a); },
    from(table) { const eqs = []; let op = null, rows = null, wantRows = false, one = false; const c = new Proxy({}, { get(_, k) {
      if (k === "eq") return (f, v) => { eqs.push([f, v]); return c; };
      if (k === "insert") return r => { op = "insert"; rows = [].concat(r); return c; };
      if (k === "update") return r => { op = "update"; rows = r; return c; };
      if (k === "select") return () => { wantRows = true; return c; };
      if (k === "single") return () => { one = true; return c; };
      if (k === "then") return res => { const db = window.__db; db[table] = db[table] || [];
        const log = (o, r) => { const l = JSON.parse(sessionStorage.getItem("writes") || "[]"); l.push({ table, op: o, rows: r, eqs }); sessionStorage.setItem("writes", JSON.stringify(l)); };
        if (op === "insert") { log("insert", rows); const made = rows.map((r, i) => ({ id: table[0] + Date.now() + "-" + db[table].length + "-" + i, active: true, kind: "regular", created_at: new Date().toISOString(), ...r })); db[table].push(...made); return res({ data: wantRows ? (one ? made[0] : made) : null, error: null }); }
        if (op === "update") { log("update", rows); db[table].filter(x => eqs.every(([f, v]) => x[f] === v)).forEach(x => Object.assign(x, rows)); return res({ data: null, error: null }); }
        const out = db[table].filter(x => eqs.every(([f, v]) => !(f in x) || x[f] === v));
        if (table === "family_members") return res({ data: out.map(m => ({ ...m, families: db.families.find(f => f.id === m.family_id) })), error: null });
        return res({ data: out, error: null }); };
      return () => c; } }); return c; } };
  return sb; } };`;
const U = "u1";
const FAM = (id, plan) => ({ id, name: "Famille " + id, created_by: "u1", plan, week_start: 1, weekend_days: [6, 7], timezone: "Europe/Paris", auto_validate: false });
const MEM = id => ({ family_id: id, user_id: U, display_name: "Parent Test", role: "parent", created_at: "2026-11-01T10:00:00Z" });
const KIDS = [{ id: "k1", family_id: "fA", name: "Enfant Un", emoji: "🐻", color: "#2E9E5B", position: 0 }, { id: "k2", family_id: "fA", name: "Enfant Deux", emoji: "🦊", color: "#E8484F", position: 1 }];
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
    window.__db = { families: [fam], family_members: [mem], children: kids.slice(0, o.kids || 1), routines: (o.routines || []).map((r, i) => ({ id: "r" + i, family_id: "fA", active: true, kind: "regular", days: [1, 2, 3, 4, 5, 6, 7], stars: 1, moment: "matin", emoji: "⭐", ...r })), rewards: [], completions: [], devices: [], child_devices: [], child_device_children: [] };
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
  await page.goto("http://localhost:8098/index.html" + (o.q || "")); await page.waitForTimeout(900);
  await page.evaluate(() => { S.tab = "routines"; render(); });
  return { page, ctx, errs };
}
const shot = async (p, name) => { if (SHOTS) await p.screenshot({ path: path.join(SHOTS, name + ".png") }); };
const toast = async p => (await p.locator("#toast").textContent()) || "";
const noHScroll = p => p.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth && (!document.querySelector("dialog[open] .sheet-in") || document.querySelector("dialog[open] .sheet-in").scrollWidth <= document.querySelector("dialog[open]").clientWidth + 1));
const PIN = { "sf:pinH": '{"s":"AA==","h":"AA==","i":1}' };
(async () => {
  browser = await chromium.launch({ executablePath: fs.existsSync("/usr/bin/google-chrome") ? "/usr/bin/google-chrome" : undefined, args: ["--no-sandbox"] });

  // 1. Choisir des modèles : 33 modèles, 6 catégories dans l'ordre (F04-02 CA8, CA12)
  let { page, ctx, errs } = await open({ ls: PIN });
  await page.click("[data-act=routineTemplates]"); await page.waitForTimeout(200);
  const heads = await page.locator("dialog h3.grp").allTextContents();
  ok("1.1 six catégories dans l'ordre", heads.join("|") === "Hygiène|Autonomie|École|Maison|Comportement|Spiritualité", heads.join("|"));
  ok("1.2 33 modèles", await page.locator(".tpl input").count() === 33);
  ok("1.3 chaque ligne donne son moment ; le matin pour la première", /Se brosser les dents \(matin\).*Matin/.test(await page.locator(".tpl li").first().textContent()), await page.locator(".tpl li").first().textContent());
  ok("1.4 un seul enfant : « Pour » absent (CA12)", await page.locator(".for-chip").count() === 0);
  ok("1.5 « Démarrage rapide par âge » proposé (F04-10 CA9)", await page.locator("[data-act=quickStart]").count() === 1);
  const spir = await page.locator(".tpl").nth(5).locator("li").allTextContents();
  ok("1.6 Spiritualité : 5 modèles, sans nom de pratique propre à une religion ni symbole religieux", spir.length === 5 && !/messe|salat|pri[eè]re musulmane|bible|coran|église|mosquée|✝|☪|✡|🕌|⛪/i.test(spir.join(" ")) , spir.join(" / "));
  await shot(page, "modeles-fr-clair");
  // 1b. Aucune case : message ; une case : ajout sans catégorie
  await page.click("[data-act=addRoutineTpl]"); await page.waitForTimeout(150);
  ok("1.7 aucune case : « Cochez au moins une routine. » (CA3)", /Cochez au moins une routine/.test(await toast(page)) && (await writes(page, "routines")).length === 0);
  await page.locator(".tpl label", { hasText: "Aider quelqu'un de la maison" }).click(); await page.locator(".tpl label", { hasText: "Prendre sa douche" }).click();
  await page.click("[data-act=addRoutineTpl]"); await page.waitForTimeout(500);
  let w = await writes(page, "routines");
  ok("1.8 une écriture de 2 lignes ; aucune catégorie ni tranche enregistrée (DEC-08, CA11)", w.length === 1 && w[0].rows.length === 2 && w[0].rows.every(r => !("c" in r) && !("category" in r) && !("age" in r) && !("k" in r)), JSON.stringify(w[0] && Object.keys(w[0].rows[0])));
  const help = w[0].rows.find(r => r.title.startsWith("Aider")), douche = w[0].rows.find(r => r.title === "Prendre sa douche");
  ok("1.9 nouveaux modèles : 1 étoile, sans lieu ni minuteur ; « Aider » bonus ; douche le soir", help.stars === 1 && help.is_bonus && help.place === null && help.timer_minutes === null && douche.moment === "soir" && douche.emoji === "🚿");
  ok("1.10 message « 2 routines ajoutées. »", /2 routines ajoutées/.test(await toast(page)), await toast(page));
  await page.click("[data-act=routineTemplates]"); await page.waitForTimeout(200);
  ok("1.11 déjà ajoutée : grisée, dite par un texte, non cochable (CA2)", await page.locator(".tpl label.had", { hasText: "déjà ajoutée" }).count() === 2 && await page.locator(".tpl label.had input:disabled").count() === 2);
  await ctx.close();

  // 2. Démarrage rapide (F04-10, R04-12)
  ({ page, ctx, errs } = await open({ ls: PIN }));
  await page.click("[data-act=routineTemplates]"); await page.click("[data-act=quickStart]"); await page.waitForTimeout(200);
  ok("2.1 « Quel âge a Enfant Un ? » : 3 tranches et « Choisir moi-même » (CA1)", /Quel âge a .*Enfant Un.* \?/.test(await page.locator("dialog h2").textContent()) && await page.locator("[data-act=quickAge]").count() === 3 && await page.locator("[data-act=quickSelf]").count() === 1 && /3-5 ans/.test(await page.locator("[data-act=quickAge]").first().textContent()));
  await shot(page, "rapide-age-fr-clair");
  await page.click("[data-act=quickSelf]"); await page.waitForTimeout(200);
  ok("2.2 « Choisir moi-même » : la liste des modèles s'ouvre (CA2)", await page.locator(".tpl input").count() === 33);
  const counts = [];
  for (const i of [0, 1, 2]) {
    await page.click("[data-act=quickStart]"); await page.click(`[data-act=quickAge][data-i="${i}"]`); await page.waitForTimeout(150);
    const txt = await page.locator("dialog").textContent();
    counts.push([await page.locator(".qr:checked").count(), await page.locator(".qw:checked").count(), await page.locator(".qr:not(:checked), .qw:not(:checked)").count(),
      /Aider quelqu|Parler calmement|Écouter la première|Dire bonjour|prière|inspire|Dire merci pour un moment/.test(txt)].join("/"));
  }
  ok("2.3 3-5 : 5 routines et 4 récompenses cochées ; 6-7 : 7 et 4 ; 8-10 : 8 et 4 ; jamais de Comportement ni de Spiritualité (R04-12 CA1)", counts.join(" ") === "5/4/0/false 7/4/0/false 8/4/0/false", counts.join(" "));
  await page.click("[data-act=quickStart]"); await page.click('[data-act=quickAge][data-i="1"]'); await page.waitForTimeout(150);
  const first = await page.locator(".qr").first().locator("xpath=ancestor::li").textContent(), rw = await page.locator(".qw").first().locator("xpath=ancestor::li").textContent();
  ok("2.4 routine avec icône et moment ; récompense avec son niveau (CA3)", /🪥.*Se brosser les dents \(matin\).*Matin/.test(first) && /🍽️.*Choisir le dessert.*Petits plaisirs/.test(rw), first + " | " + rw);
  await shot(page, "rapide-67-fr-clair");
  await page.locator(".qr").nth(1).uncheck(); await page.locator(".qr").nth(2).uncheck(); await page.locator(".qw").nth(3).uncheck();
  await page.click("[data-act=quickAdd]"); await page.waitForTimeout(700);
  w = await writes(page, "routines"); const wr = await writes(page, "rewards");
  ok("2.5 routines en une écriture de 5 lignes, puis récompenses en une écriture de 3 lignes (CA4)", w.length === 1 && w[0].rows.length === 5 && wr.length === 1 && wr[0].rows.length === 3, `${w.length}/${w[0]?.rows.length} ${wr.length}/${wr[0]?.rows.length}`);
  const order = (await ss(page, "writes")).map(x => x.table).join(",");
  ok("2.6 routines avant récompenses", /routines,rewards/.test(order), order);
  ok("2.7 message « 5 routines et 3 récompenses ajoutées. »", /5 routines et 3 récompenses ajoutées\./.test(await toast(page)), await toast(page));
  ok("2.8 aucune tranche d'âge ni catégorie dans les lignes (DEC-03, CA8)", [...w[0].rows, ...wr[0].rows].every(r => !Object.keys(r).some(k => /age|tranche|cat|^c$|^k$/i.test(k))), JSON.stringify(Object.keys(wr[0].rows[0])));
  ok("2.9 récompenses pour tous les enfants (sans child_id), prix calculés sur les routines ajoutées", wr[0].rows.every(r => r.child_id === undefined && r.cost >= 1 && r.costs.k1 >= 1), JSON.stringify(wr[0].rows.map(r => [r.title, r.cost])));
  await page.click("[data-act=routineTemplates]"); await page.click("[data-act=quickStart]"); await page.click('[data-act=quickAge][data-i="1"]'); await page.waitForTimeout(200);
  ok("2.10 déjà présentes : grisées, dites « déjà ajoutée », non cochées (CA6)", await page.locator(".qr:disabled").count() === 5 && await page.locator(".qw:disabled").count() === 3 && await page.locator("dialog .had", { hasText: "déjà ajoutée" }).count() === 8 && await page.locator(".qr:checked").count() === 2, `${await page.locator(".qr:disabled").count()}`);
  await ctx.close();
  // 2b. aucune routine cochée
  ({ page, ctx, errs } = await open({ ls: PIN }));
  await page.click("[data-act=routineTemplates]"); await page.click("[data-act=quickStart]"); await page.click('[data-act=quickAge][data-i="0"]');
  for (const i of [0, 1, 2, 3, 4]) await page.locator(".qr").nth(i).uncheck();
  await page.click("[data-act=quickAdd]"); await page.waitForTimeout(250);
  ok("2.11 aucune routine cochée : « Cochez au moins une routine. », rien créé (CA5)", /Cochez au moins une routine/.test(await toast(page)) && (await ss(page, "writes")).length === 0);
  await ctx.close();
  // 2c. Après l'ajout d'un enfant : la fenêtre s'ouvre ; fermée sans ajout, rien n'est créé (CA1, CA7)
  ({ page, ctx, errs } = await open({ ls: PIN }));
  await page.evaluate(() => { S.tab = "family"; render(); }); await page.click("[data-act=newChild]"); await page.fill("#k-name", "Enfant Trois"); await page.click("[data-act=saveChild]"); await page.waitForTimeout(500);
  ok("2.12 enfant ajouté : « Quel âge a Enfant Trois ? »", /Quel âge a .*Enfant Trois/.test(await page.locator("dialog h2").textContent()) && await page.evaluate(() => S.tab === "routines"));
  await page.keyboard.press("Escape"); await page.waitForTimeout(250);
  ok("2.13 fermée sans ajout : rien créé, invitation à choisir des modèles (CA7)", (await writes(page, "routines")).length === 0 && /n'a pas encore de routine/.test(await page.locator("main").textContent()));
  await ctx.close();

  // 3. Plusieurs enfants : « Pour », ajout en une écriture (DEC-09, F04-02 CA9, CA10)
  ({ page, ctx, errs } = await open({ ls: PIN, kids: 2 }));
  await page.click("[data-act=routineTemplates]"); await page.waitForTimeout(200);
  ok("3.1 « Pour » : 2 enfants, l'enfant affiché coché", await page.locator(".for-chip").count() === 2 && await page.locator('.for-chip[aria-pressed="true"]').count() === 1 && /Pour/.test(await page.locator("dialog").textContent()));
  await page.locator(".for-chip").nth(0).click(); await page.waitForTimeout(100);
  ok("3.2 le dernier enfant coché ne se décoche pas", await page.locator('.for-chip[aria-pressed="true"]').count() === 1);
  await page.locator(".for-chip").nth(1).click();
  for (const x of ["Faire son lit", "Se coiffer", "Parler calmement"]) await page.locator(".tpl label", { hasText: x }).click();
  await shot(page, "modeles-pour-fr-clair");
  await page.click("[data-act=addRoutineTpl]"); await page.waitForTimeout(500);
  w = await writes(page, "routines");
  ok("3.3 une seule écriture de 6 lignes (3 par enfant) ; « 6 routines ajoutées. »", w.length === 1 && w[0].rows.length === 6 && w[0].rows.filter(r => r.child_id === "k1").length === 3 && w[0].rows.filter(r => r.child_id === "k2").length === 3 && /6 routines ajoutées/.test(await toast(page)), `${w.length}/${w[0]?.rows.length} ${await toast(page)}`);
  await page.click("[data-act=routineTemplates]"); await page.locator(".for-chip").nth(1).click(); await page.waitForTimeout(150);
  ok("3.4 deux enfants cochés, modèle présent pour les deux : grisé « déjà ajoutée »", await page.locator(".tpl label.had", { hasText: "Faire son lit" }).count() === 1);
  await page.locator(".for-chip").nth(0).click(); await page.waitForTimeout(100);
  ok("3.5 un enfant seul : « déjà ajoutée »", await page.locator(".tpl label.had", { hasText: "Se coiffer" }).count() === 1);
  // enfant 2 seul a une routine en plus → ajouté au volet : « déjà ajoutée pour »
  await page.evaluate(() => { S.routines = S.routines.filter(r => !(r.child_id === "k2" && r.title === "Se coiffer")); S.routinesAll = S.routines; });
  await page.locator(".for-chip").nth(0).click(); await page.waitForTimeout(100);
  const li = page.locator(".tpl label", { hasText: "Se coiffer" });
  ok("3.6 présent pour un seul des enfants cochés : cochable, « déjà ajoutée pour Enfant Un » (CA10)", /déjà ajoutée pour .*Enfant Un/.test(await li.textContent()) && await li.locator("input:disabled").count() === 0, await li.textContent());
  await li.click(); await page.click("[data-act=addRoutineTpl]"); await page.waitForTimeout(500);
  w = await writes(page, "routines");
  ok("3.7 créé seulement pour l'enfant qui ne l'a pas", w.length === 2 && w[1].rows.length === 1 && w[1].rows[0].child_id === "k2" && /1 routine ajoutée/.test(await toast(page)), JSON.stringify(w[1]?.rows.map(r => r.child_id)));
  // formulaire
  await page.evaluate(() => { closeSheet(); }); await page.click("[data-act=newRoutine]"); await page.waitForTimeout(200);
  ok("3.8 formulaire : « Pour » (enfant affiché coché) et « Rappel à »", await page.locator(".for-chip").count() === 2 && await page.locator("#f-remind").count() === 1);
  const opts = await page.locator("#f-remind option").allTextContents();
  ok("3.9 « Rappel à » : Sans rappel, puis 05:00 à 23:45 au quart d'heure (76 heures)", opts[0] === "Sans rappel" && opts[1] === "05:00" && opts[opts.length - 1] === "23:45" && opts.length === 77 && opts.slice(1).every(v => /^\d\d:(00|15|30|45)$/.test(v)), opts.length + " " + opts.slice(0, 3));
  ok("3.10 Premium : champ actif, sans étiquette", await page.locator("#f-remind:disabled").count() === 0 && await page.locator("dialog .ptag").count() === 0);
  await page.fill("#f-title", "Ranger le cartable"); await page.locator(".for-chip").nth(1).click(); await page.selectOption("#f-remind", "17:30");
  await page.click("[data-act=saveRoutine]"); await page.waitForTimeout(500);
  w = await writes(page, "routines");
  ok("3.11 création pour 2 enfants en une écriture, avec remind_at « 17:30 »", w.length === 3 && w[2].rows.length === 2 && w[2].rows.every(r => r.remind_at === "17:30" && r.title === "Ranger le cartable") && /2 routines ajoutées/.test(await toast(page)), JSON.stringify(w[2]?.rows.map(r => r.remind_at)));
  const rowTxt = await page.locator(".rt", { hasText: "Ranger le cartable" }).first().textContent();
  ok("3.12 la ligne montre « ⏰ 17:30 » et son nom accessible « Rappel à 17:30 »", /⏰ 17:30/.test(rowTxt) && /Rappel à 17:30/.test(rowTxt), rowTxt);
  await page.locator(".rt", { hasText: "Ranger le cartable" }).first().click(); await page.waitForTimeout(200);
  ok("3.13 modification : heure relue (17:30), pas de « Pour »", await page.locator("#f-remind").inputValue() === "17:30" && await page.locator(".for-chip").count() === 0);
  await page.selectOption("#f-remind", ""); await page.click("[data-act=saveRoutine]"); await page.waitForTimeout(400);
  const up = (await ss(page, "writes")).filter(x => x.table === "routines" && x.op === "update").pop();
  ok("3.14 « Sans rappel » : remind_at nul envoyé", up && up.rows.remind_at === null, JSON.stringify(up && up.rows.remind_at));
  await ctx.close();

  // 4. Gratuit : « Rappel à » porte l'étiquette Premium et l'incitation, le serveur refuse aussi
  ({ page, ctx, errs } = await open({ ls: PIN, plan: "free", routines: [{ child_id: "k1", title: "Routine ancienne", remind_at: "08:15:00" }] }));
  await page.click("[data-act=newRoutine]"); await page.waitForTimeout(200);
  ok("4.1 gratuit : champ fermé, étiquette Premium, incitation avec lien", await page.locator("#f-remind:disabled").count() === 1 && await page.locator("dialog .ptag").count() >= 1 && /fait partie du Premium/.test(await page.locator("#f-remind-h").textContent()) && await page.locator("#f-remind-h a").count() === 1);
  await shot(page, "rappel-gratuit-fr-clair");
  await page.fill("#f-title", "Test gratuit"); await page.click("[data-act=saveRoutine]"); await page.waitForTimeout(400);
  w = await writes(page, "routines");
  ok("4.2 gratuit : aucune heure envoyée", w.length === 1 && !("remind_at" in w[0].rows[0]), JSON.stringify(Object.keys(w[0].rows[0])));
  await page.locator(".rt", { hasText: "Routine ancienne" }).click(); await page.waitForTimeout(150);
  ok("4.3 offre perdue : l'heure gardée reste lue (08:15), champ fermé", await page.locator("#f-remind").inputValue() === "08:15" && await page.locator("#f-remind:disabled").count() === 1);
  await page.click("[data-act=saveRoutine]"); await page.waitForTimeout(300);
  const up2 = (await ss(page, "writes")).filter(x => x.table === "routines" && x.op === "update").pop();
  ok("4.4 enregistrer sans toucher : remind_at non envoyé (le serveur garde l'heure)", up2 && !("remind_at" in up2.rows));
  await ctx.close();

  // 5. Adresse d'envoi des rappels (ADR-57) : jetons à parent_push_subscribe, adresse à child_pair_here
  const LS5 = { ...PIN, "sf:sameDevice": '{"k1":"tok-a","k2":"tok-a","k9":"tok-b"}' };
  ({ page, ctx, errs } = await open({ ls: LS5, push: true }));
  await page.evaluate(() => { S.tab = "family"; render(); });
  await page.evaluate(() => { return A.pushParent(); }); await page.waitForTimeout(300);
  let ps = await calls(page, "parent_push_subscribe");
  ok("5.1 pushParent : 7 paramètres, jetons Mode enfant ici uniques (sans doublon)", ps.length === 1 && Object.keys(ps[0]).sort().join() === "p_auth,p_endpoint,p_family,p_locale,p_p256dh,p_times,p_tokens" && JSON.stringify(ps[0].p_tokens.sort()) === '["tok-a","tok-b"]' && ps[0].p_family === "fA", JSON.stringify(ps[0]));
  ok("5.2 famille du réglage gardée (pushFamily)", await page.evaluate(() => store.get("pushFamily")) === "fA");
  await ctx.close();
  ({ page, ctx, errs } = await open({ ls: { ...LS5, "sf:pushOn": "true", "sf:pushTimes": '["07:30","18:30"]', "sf:pushFamily": '"fA"' }, push: true }));
  await page.waitForTimeout(500); ps = await calls(page, "parent_push_subscribe");
  ok("5.3 ouverture du parent : adresse notée sur les lignes existantes (mêmes heures, même famille)", ps.length === 1 && ps[0].p_endpoint === "https://push.test/e1" && ps[0].p_family === "fA" && ps[0].p_times.join() === "07:30,18:30" && ps[0].p_tokens.length === 2, JSON.stringify(ps[0]));
  await page.evaluate(() => { enterParent(); }); await page.waitForTimeout(600); ps = await calls(page, "parent_push_subscribe");
  ok("5.4 rouverte avec les mêmes jetons : pas de nouvel appel", ps.length === 1);
  await ctx.close();
  ({ page, ctx, errs } = await open({ ls: { ...LS5, "sf:pushOn": "true", "sf:pushFamily": '"fZ"' }, push: true }));
  await page.waitForTimeout(400);
  ok("5.5 famille ouverte différente de celle du réglage : aucun appel (jamais de changement de famille d'abonnement)", (await calls(page, "parent_push_subscribe")).length === 0);
  await ctx.close();
  ({ page, ctx, errs } = await open({ ls: { ...PIN, "sf:pushOn": "true" }, push: true }));
  await page.evaluate(() => { S.tab = "family"; render(); }); await page.click('[data-act=childHere][data-id="k1"]'); await page.waitForTimeout(500);
  let ch = await calls(page, "child_pair_here");
  ok("5.6 Mode enfant ici avec rappels activés : p_endpoint = adresse d'envoi du téléphone", ch.length === 1 && ch[0].p_endpoint === "https://push.test/e1" && Object.keys(ch[0]).length === 5, JSON.stringify(ch[0]));
  await ctx.close();
  ({ page, ctx, errs } = await open({ ls: PIN, push: true }));
  await page.evaluate(() => { S.tab = "family"; render(); }); await page.click('[data-act=childHere][data-id="k1"]'); await page.waitForTimeout(500);
  ch = await calls(page, "child_pair_here");
  ok("5.7 rappels non activés : p_endpoint nul (renseigné à l'activation, par les jetons)", ch.length === 1 && ch[0].p_endpoint === null, JSON.stringify(ch[0]));
  await ctx.close();

  // 6. Arabe et sombre, 360 px : sens, pas de défilement horizontal, captures
  for (const [lang, dark, w6] of [["ar", false, 360], ["fr", true, 360], ["ar", true, 390]]) {
    const tag = `${lang}-${dark ? "sombre" : "clair"}`;
    ({ page, ctx, errs } = await open({ ls: PIN, locale: lang, dark, w: w6, q: lang === "ar" ? "?lang=ar" : "", kids: 2 }));
    ok(`6.${tag}.0 sens de lecture`, lang === "ar" ? await page.evaluate(() => document.documentElement.dir) === "rtl" : true);
    await page.click("[data-act=routineTemplates]"); await page.waitForTimeout(250); await shot(page, "modeles-" + tag);
    ok(`6.${tag}.1 modèles : pas de défilement horizontal, 33 modèles, « Pour »`, await noHScroll(page) && await page.locator(".tpl input").count() === 33 && await page.locator(".for-chip").count() === 2);
    await page.click("[data-act=quickStart]"); await page.waitForTimeout(200); await shot(page, "rapide-age-" + tag);
    ok(`6.${tag}.2 tranches : pas de défilement horizontal, chiffres 0123`, await noHScroll(page) && /3-5/.test(await page.locator("[data-act=quickAge]").first().textContent()));
    await page.click('[data-act=quickAge][data-i="2"]'); await page.waitForTimeout(200); await shot(page, "rapide-ensemble-" + tag);
    ok(`6.${tag}.3 ensemble : pas de défilement horizontal`, await noHScroll(page));
    await page.evaluate(() => closeSheet()); await page.click("[data-act=newRoutine]"); await page.waitForTimeout(250); await shot(page, "formulaire-rappel-" + tag);
    ok(`6.${tag}.4 formulaire : pas de défilement horizontal, « Rappel à » présent`, await noHScroll(page) && await page.locator("#f-remind").count() === 1);
    ok(`6.${tag}.5 aucune erreur de script`, errs.length === 0, errs.join(" | "));
    await ctx.close();
  }
  console.log(fails ? `${fails} cas en échec` : "Tous les cas sont conformes");
  await browser.close(); srv.close(); process.exit(fails ? 1 : 0);
})().catch(e => { console.error(e); process.exit(2); });
