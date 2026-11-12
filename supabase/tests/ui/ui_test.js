const { chromium } = require("/opt/npm-tools/node_modules/playwright");
const http = require("http"), fs = require("fs"), path = require("path");
const ROOT = "/home/claude/soisfier2/app";
const MIME = { ".html": "text/html", ".js": "text/javascript", ".json": "application/json", ".css": "text/css", ".png": "image/png", ".webmanifest": "application/json" };
const srv = http.createServer((q, r) => { let p = decodeURIComponent(q.url.split("?")[0]); if (p.endsWith("/")) p += "index.html"; const f = path.join(ROOT, p);
  fs.readFile(f, (e, d) => { if (e) { r.writeHead(404); return r.end(); } r.writeHead(200, { "Content-Type": MIME[path.extname(f)] || "application/octet-stream" }); r.end(d); }); }).listen(8099);
const STUB = `window.supabase = { createClient() { const M = () => window.__mock;
  const sb = { auth: { getSession: async () => ({ data: { session: M().session } }), onAuthStateChange() {}, signInWithPassword: async a => M().signIn(a), updateUser: async () => ({}) },
    rpc: async (n, a) => { (window.__calls = window.__calls || []).push([n, a]); return M().rpc(n, a); },
    from() { const c = { select: () => c, eq: () => c, order: () => c, limit: () => c, then: r => r({ data: [], error: null }), update: () => c, insert: () => c, delete: () => c, single: () => c }; return c; } };
  return sb; } };`;
const CHILD_STATE = { today: "2026-11-11", premium: false, child: { id: "c1", name: "Enfant Test", emoji: "🐻", color: "#2E9E5B", garden_start: "2026-10-01" }, routines: [], holidays: [], completions: [], oneoff_done: 0, rewards: [], redemptions: [], penalties: [], badges: [], badge_dates: {},
  stats: { earned: 0, done_count: 0, pending_stars: 0, pending_count: 0, spent: 0, redeemed_count: 0, broken: 0, broken_count: 0 },
  garden: { today: "2026-11-11", period_start: "2026-11-09", period_end: "2026-11-15", period_len: 7, season: "autumn", garden_year: 1, days: [], flowers: [], pauses: [], streak: 0, best_streak: 0, counters: { timers: 0, bonus: 0, oneoff: 0, sortie: 0, grand: 0, last_redeem: null, matin: 0, soir: 0, full: 0, weeks: 0, weekends: 0 } },
  family: { week_start: 1, weekend_days: [6, 7], timezone: "Europe/Paris" } };
let browser, fails = 0;
const ok = (n, c, extra = "") => { if (!c) fails++; console.log((c ? "OK  " : "KO  ") + n + (extra ? "  [" + extra + "]" : "")); };
async function open(opts) {
  const ctx = await browser.newContext({ locale: opts.locale || "fr-FR" });
  await ctx.route("**/config.js", r => r.fulfill({ contentType: "text/javascript", body: fs.readFileSync(ROOT + "/js/config.js", "utf8").replace("__SUPABASE_URL__", "https://x.test").replace("__SUPABASE_KEY__", "k") }));
  await ctx.route("**/supabase.min.js", r => r.fulfill({ contentType: "text/javascript", body: STUB }));
  await ctx.route("**/sw.js", r => r.abort());
  const page = await ctx.newPage(); const errs = []; page.on("pageerror", e => errs.push(String(e)));
  await page.addInitScript(([o, cs]) => {
    window.__rpcLog = []; window.__net = o.offline ? "off" : "on";
    window.__mock = { session: o.session ? { user: { id: "u1", email: "parent.test@example.invalid" } } : null,
      signIn: async a => a.password === "bonmotdepasse" ? { data: { session: {} }, error: null } : (window.__signInError || { data: null, error: { message: "Invalid login credentials", status: 400 } }),
      rpc: async (n, a) => {
        if (window.__net === "off" && n === "child_unpair") return { data: null, error: { message: "TypeError: Failed to fetch" } };
        if (n === "child_state") return window.__stateError ? { data: null, error: { message: window.__stateError } } : { data: window.__cs, error: null };
        if (n === "child_unpair") return { data: { ok: true }, error: null };
        if (n === "child_pair") return { data: window.__pair, error: null };
        if (n === "join_family") return { data: window.__join, error: window.__joinErr || null };
        return { data: null, error: null };
      } };
    window.__cs = cs;
    const L = JSON.parse(o.ls || "{}"); for (const k in L) localStorage.setItem(k, L[k]);
  }, [opts, opts.cs || CHILD_STATE]);
  await page.goto("http://localhost:8099/index.html" + (opts.q || ""));
  await page.waitForTimeout(700);
  return { page, ctx, errs };
}
const txt = async p => (await p.locator("#toast").textContent()) || "";
const lsGet = (p, k) => p.evaluate(k => localStorage.getItem(k), k);
async function typeCode(p, c) { await p.fill("#pin-in", c); await p.click("#pin-ok"); await p.waitForTimeout(500); }
(async () => {
  browser = await chromium.launch({ executablePath: "/usr/bin/google-chrome", args: ["--no-sandbox"] });
  // empreinte de 1234 générée par la page elle-même
  const mk = async () => { const { page, ctx } = await open({ ls: "{}" }); const h = await page.evaluate(async () => { await pinSave("1234"); return localStorage.getItem("sf:pinH"); }); await ctx.close(); return h; };
  const PINH = await mk();

  if (process.env.ONLY10) { var SKIP = true; }
  // 1. Téléphone propre de l'enfant : paliers, sortie, retrait de l'appareil
  let { page, ctx, errs } = await open({ ls: JSON.stringify({ "sf:childToken": '"tok-enfant"', "sf:childCache": JSON.stringify(CHILD_STATE), "sf:pinH": PINH }) });
  ok("1.0 écran de l'enfant affiché", await page.locator("button.lock").count() === 1);
  await page.click("button.lock"); await page.waitForTimeout(300);
  ok("1.1 pas de lien « Code oublié ? » sans parent connecté", await page.locator("#pin-forgot").count() === 0);
  for (let i = 1; i <= 4; i++) { await typeCode(page, "0000"); const m = await txt(page); if (i < 4) { await page.click("button.lock"); await page.waitForTimeout(200); } else ok("1.2 4e code faux : « Code incorrect. »", /Code incorrect/.test(m), m); }
  await page.click("button.lock"); await page.waitForTimeout(200); await typeCode(page, "0000");
  ok("1.3 5e code faux : attente 1 min", /Trop d'essais\. Réessayez dans 1 min\./.test(await txt(page)), await txt(page));
  await page.click("button.lock"); await page.waitForTimeout(300);
  ok("1.4 attente affichée à la réouverture, saisie désactivée", await page.locator("#pin-in[disabled]").count() === 1 && /Réessayez dans 1 min/.test(await page.locator("dialog").textContent()));
  await page.click("#pin-no"); await page.reload(); await page.waitForTimeout(600);
  await page.click("button.lock"); await page.waitForTimeout(300);
  ok("1.5 attente conservée après fermeture de l'application", await page.locator("#pin-in[disabled]").count() === 1);
  await page.click("#pin-no");
  await page.evaluate(() => { const g = JSON.parse(localStorage.getItem("sf:pinGuard")); g.until = 0; localStorage.setItem("sf:pinGuard", JSON.stringify(g)); });
  await page.click("button.lock"); await page.waitForTimeout(200); await typeCode(page, "0000");
  ok("1.6 6e faux : 5 min", /Réessayez dans 5 min/.test(await txt(page)), await txt(page));
  await page.evaluate(() => { const g = JSON.parse(localStorage.getItem("sf:pinGuard")); g.until = 0; localStorage.setItem("sf:pinGuard", JSON.stringify(g)); });
  await page.click("button.lock"); await page.waitForTimeout(200); await typeCode(page, "0000");
  ok("1.7 7e faux : 30 min", /Réessayez dans 30 min/.test(await txt(page)), await txt(page));
  await page.evaluate(() => { const g = JSON.parse(localStorage.getItem("sf:pinGuard")); g.until = 0; localStorage.setItem("sf:pinGuard", JSON.stringify(g)); });
  await page.click("button.lock"); await page.waitForTimeout(200); await typeCode(page, "1234"); await page.waitForTimeout(800);
  const calls = await page.evaluate(() => window.__calls.map(c => c[0] + ":" + JSON.stringify(c[1])));
  ok("1.8 code juste : child_unpair envoyé avec le jeton", calls.includes('child_unpair:{"p_token":"tok-enfant"}'), calls.join(" "));
  ok("1.9 jeton, cache et compteur effacés ; écran d'accueil", (await lsGet(page, "sf:childToken")) === null && (await lsGet(page, "sf:pinGuard")) === null && /Créer un compte|Connexion/.test(await page.locator("#app").textContent()));
  ok("1.10 aucune erreur de script", errs.length === 0, errs.join(";")); await ctx.close();

  // 2. Sortie hors ligne : file locale puis envoi au retour du réseau
  ({ page, ctx, errs } = await open({ offline: true, ls: JSON.stringify({ "sf:childToken": '"tok-hors-ligne"', "sf:childCache": JSON.stringify(CHILD_STATE), "sf:pinH": PINH }) }));
  await page.click("button.lock"); await page.waitForTimeout(200); await typeCode(page, "1234"); await page.waitForTimeout(800);
  ok("2.1 hors ligne : jeton gardé dans la file locale", (await lsGet(page, "sf:unpairQueue")) === '["tok-hors-ligne"]', await lsGet(page, "sf:unpairQueue"));
  await page.evaluate(() => { window.__net = "on"; window.__calls = []; window.dispatchEvent(new Event("online")); });
  await page.waitForTimeout(600);
  ok("2.2 retour du réseau : file envoyée puis vidée", (await lsGet(page, "sf:unpairQueue")) === null && (await page.evaluate(() => window.__calls.map(c => c[0]).join())) === "child_unpair"); await ctx.close();

  // 3. Mode enfant ici (parent connecté) : « Code oublié ? », compteur propre, aucun retrait d'appareil
  ({ page, ctx, errs } = await open({ session: true, ls: JSON.stringify({ "sf:childToken": '"tok-ici"', "sf:childFromParent": "true", "sf:childCache": JSON.stringify(CHILD_STATE), "sf:pinH": PINH }) }));
  await page.click("button.lock"); await page.waitForTimeout(300);
  ok("3.1 lien « Code oublié ? » proposé", await page.locator("#pin-forgot").count() === 1);
  for (let i = 1; i <= 5; i++) { if (i > 1) { await page.click("button.lock"); await page.waitForTimeout(200); } await page.click("#pin-forgot"); await page.waitForTimeout(300); await page.fill("#pw-in", "faux"); await page.click("#pw-ok"); await page.waitForTimeout(500);
    const m = await txt(page); if (i === 1) ok("3.2 mot de passe faux : message", /Mot de passe incorrect\./.test(m), m); if (i === 5) ok("3.3 5e faux : attente 1 min (compteur du mot de passe)", /Trop d'essais\. Réessayez dans 1 min\./.test(m), m); }
  ok("3.4 compteur du code resté à zéro (indépendant)", (await lsGet(page, "sf:pinGuard")) === null && (await lsGet(page, "sf:pwdGuard")) !== null);
  await page.click("button.lock"); await page.waitForTimeout(300);
  ok("3.5 pendant l'attente du mot de passe, le code reste saisissable", await page.locator("#pin-in[disabled]").count() === 0);
  await page.click("#pin-forgot"); await page.waitForTimeout(300);
  ok("3.6 attente vérifiée avant l'envoi (aucune demande de mot de passe)", await page.locator("#pw-in").count() === 0 && /Réessayez dans 1 min/.test(await txt(page)));
  await page.evaluate(() => { const g = JSON.parse(localStorage.getItem("sf:pwdGuard")); g.until = 0; localStorage.setItem("sf:pwdGuard", JSON.stringify(g)); window.__calls = []; });
  await page.click("button.lock"); await page.waitForTimeout(300); await page.click("#pin-forgot"); await page.waitForTimeout(300); await page.fill("#pw-in", "bonmotdepasse"); await page.click("#pw-ok"); await page.waitForTimeout(1200);
  ok("3.7 mot de passe juste : code effacé, compteurs remis à zéro", (await lsGet(page, "sf:pinH")) === null && (await lsGet(page, "sf:pwdGuard")) === null);
  ok("3.8 création d'un nouveau code proposée", await page.locator("#pin-in").count() === 1, (await page.locator("dialog").textContent()).slice(0, 80));
  ok("3.9 Mode enfant ici : l'appareil n'est pas retiré", !(await page.evaluate(() => window.__calls.map(c => c[0]))).includes("child_unpair"));
  ok("3.10 aucune erreur de script", errs.length === 0, errs.join(";")); await ctx.close();

  // 3b. Mot de passe hors ligne : message, pas de compte d'échec
  ({ page, ctx } = await open({ session: true, ls: JSON.stringify({ "sf:childToken": '"t"', "sf:childFromParent": "true", "sf:childCache": JSON.stringify(CHILD_STATE), "sf:pinH": PINH }) }));
  await page.click("button.lock"); await page.waitForTimeout(200); await page.click("#pin-forgot"); await page.waitForTimeout(300); await page.fill("#pw-in", "x");
  await page.context().setOffline(true); await page.click("#pw-ok"); await page.waitForTimeout(500);
  ok("3b.1 hors ligne : « Il faut une connexion internet… »", /connexion internet pour vérifier/.test(await txt(page)), await txt(page));
  ok("3b.2 échec non compté", (await lsGet(page, "sf:pwdGuard")) === null); await ctx.close();

  // 4. Migration de l'ancien code
  ({ page, ctx } = await open({ ls: JSON.stringify({ "sf:pin": '"4321"' }) }));
  ok("4.1 ancien code converti puis effacé", (await lsGet(page, "sf:pin")) === null && (await lsGet(page, "sf:pinH")) !== null && !(await lsGet(page, "sf:pinH")).includes("4321"));
  ok("4.2 même code fonctionne", await page.evaluate(() => pinCheck("4321")) === true && await page.evaluate(() => pinCheck("1234")) === false); await ctx.close();

  // 5. Jeton périmé 3 mois
  ({ page, ctx } = await open({ ls: JSON.stringify({ "sf:childToken": '"vieux"', "sf:childCache": JSON.stringify(CHILD_STATE) }) }));
  await page.evaluate(() => { window.__stateError = "SF:device_expired"; window.__calls = []; }); await page.reload(); await page.waitForTimeout(300);
  await page.evaluate(() => { window.__stateError = "SF:device_expired"; });
  await page.evaluate(() => loadChild()); await page.waitForTimeout(800);
  ok("5.1 message propre « Ce téléphone n'a pas servi depuis 3 mois… »", /n'a pas servi depuis 3 mois/.test(await txt(page)), await txt(page));
  ok("5.2 retour à l'accueil, jeton effacé", (await lsGet(page, "sf:childToken")) === null && /Connexion|Créer un compte/.test(await page.locator("#app").textContent())); await ctx.close();

  // 6. Codes faux et blocage, en fr, ar, en
  for (const [lang, rx1, rx2, rx3] of [["fr", /Code invalide ou expiré/, /dans 15 minutes au plus/, /déjà membre/], ["en", /Invalid or expired code/, /in 15 minutes at most/, /already a member/], ["ar", /رمز غير صالح/, /بعد 15 دقيقة/, /أنتم عضو بالفعل/]]) {
    ({ page, ctx, errs } = await open({ q: "?lang=" + lang }));
    await page.evaluate(() => { window.__pair = { error: "bad_code" }; }); await page.waitForTimeout(200);
    const r = await page.evaluate(async () => { const out = []; for (const f of [() => ({ error: "bad_code" }), null]) { } window.__pair = { error: "bad_code" }; document.body.insertAdjacentHTML("beforeend", '<input id="p-code" value="ABCDEF">'); try { await A.pair(); } catch (e) { out.push(errMsg(e)); } try { throw new Error("SF:code_locked:15"); } catch (e) { out.push(errMsg(e)); } try { throw new Error("SF:already_member"); } catch (e) { out.push(errMsg(e)); } out.push(errMsg(new Error("SF:device_expired"))); out.push(errMsg(new Error("SF:not_due"))); return out; });
    ok(`6.${lang} bad_code / blocage / déjà membre / périmé / pas dû`, rx1.test(r[0]) && rx2.test(r[1]) && rx3.test(r[2]) && r[3] && r[4], r.join(" | "));
    ok(`6.${lang} aucune erreur de script`, errs.length === 0, errs.join(";")); await ctx.close();
  }
  // 7. join_family : réponse vide = code faux
  ({ page, ctx } = await open({ session: true }));
  const j = await page.evaluate(async () => { window.__join = null; if (!document.getElementById("o-code")) document.body.insertAdjacentHTML("beforeend", '<input id="o-code">'); document.getElementById("o-code").value = "ABCDEF"; try { await A.joinFamily(); await new Promise(r => setTimeout(r, 300)); return document.getElementById("toast").textContent || "pas d'erreur"; } catch (e) { return errMsg(e); } });
  ok("7.1 join_family vide => « Code invalide ou expiré. »", /Code invalide ou expiré/.test(j), j); await ctx.close();
  // 8. pseudo-langue qps : aucun texte en clair dans la fenêtre du code
  ({ page, ctx } = await open({ q: "?lang=qps", ls: JSON.stringify({ "sf:childToken": '"t"', "sf:childCache": JSON.stringify(CHILD_STATE), "sf:pinH": PINH }) }));
  await page.click("button.lock"); await page.waitForTimeout(300);
  const dlgTxt = await page.locator("dialog").textContent(); ok("8.1 qps : fenêtre du code déformée (aucun texte en dur)", !/Espace parent|Code à 4 chiffres|Annuler|Valider/.test(dlgTxt), dlgTxt.slice(0, 90)); await ctx.close();
  // 9. Thème C : réglages historisés, compteur du jour, badges annoncés par le serveur
  const CS9 = JSON.parse(JSON.stringify(CHILD_STATE));
  const iso = d => d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
  const D0 = new Date(), D1 = new Date(Date.now() + 864e5), Dm = new Date(Date.now() - 864e5), D2 = new Date(Date.now() + 2 * 864e5);
  const dow1 = D1.getDay() || 7;
  CS9.today = iso(D0); CS9.family = { week_start: 1, weekend_days: [6, 7], timezone: Intl.DateTimeFormat().resolvedOptions().timeZone };
  CS9.routines = [
    { id: "r1", title: "Routine réglée", emoji: "⭐", moment: "matin", stars: 1, days: [dow1], is_bonus: false, kind: "regular", created_at: "2026-09-01T08:00:00Z", position: 1,
      settings: [{ valid_from: "2026-09-01", days: [1, 2, 3, 4, 5, 6, 7], is_bonus: false, stars: 1 }, { valid_from: iso(D1), days: [dow1], is_bonus: false, stars: 1 }] },
    { id: "o1", title: "Avant vendredi", emoji: "🎯", moment: "journee", stars: 3, days: [1, 2, 3, 4, 5, 6, 7], is_bonus: false, kind: "oneoff", start_day: iso(Dm), end_day: iso(D2), created_at: iso(Dm) + "T08:00:00Z", position: 2 }];
  CS9.completions = []; CS9.badges = ["first"]; CS9.badges_new = ["first"];
  ({ page, ctx, errs } = await open({ ls: JSON.stringify({ "sf:childToken": '"tok-enfant"', "sf:childCache": JSON.stringify(CS9) }), cs: CS9 }));
  await page.waitForTimeout(500);
  const body9 = await page.locator("main").textContent();
  ok("9.1 routine réglée : due ce jour avec ses anciens jours", /Routine réglée/.test(body9));
  ok("9.2 exceptionnelle listée avant son dernier jour", /Avant vendredi/.test(body9));
  const count9 = (await page.locator(".today-count span").first().textContent()) || "";
  ok("9.3 compteur : l'exceptionnelle « Avant le » n'est pas comptée avant son dernier jour (1 routine)", /1/.test(count9) && !/2/.test(count9), count9);
  const calls9 = await page.evaluate(() => (window.__calls || []).map(c => c[0]));
  ok("9.4 badges à annoncer envoyés au serveur (child_badges_seen)", calls9.includes("child_badges_seen"), calls9.join(","));
  ok("9.5 plus d'enregistrement de badge par l'application", !calls9.includes("child_award_badges"), calls9.join(","));
  ok("9.6 aucune erreur de script", errs.length === 0, errs.join(";")); await ctx.close();

  // 10. Thème D : repli anglais, message générique, langue enregistrée, rappels, fenêtres nommées, astuces
  ({ page, ctx, errs } = await open({ locale: "de-DE" }));
  const h10 = await page.evaluate(() => ({ lang: document.documentElement.lang, dir: document.documentElement.dir, title: document.title, desc: document.querySelector('meta[name="description"]').content, stored: localStorage.getItem("sf:lang") }));
  ok("10.1 téléphone en allemand : l'application s'ouvre en anglais (lang, titre, description)", h10.lang === "en" && h10.dir === "ltr" && /^Routines, stars/.test(h10.desc) && h10.title === "SoisFier", JSON.stringify(h10));
  const lc = await page.evaluate(async () => { const r = await (await caches.open("soisfier-lang")).match("./sf-lang"); return r ? await r.text() : null; });
  ok("10.2 la langue est écrite pour le service worker (./sf-lang)", lc === "en", String(lc));
  const miss = await page.evaluate(() => { I18N.lang = "ar"; I18N.d = JSON.parse(JSON.stringify(I18N.en)); delete I18N.d.err.network; I18N.d.lang = {}; return [t("err.network"), I18N.en.err.network]; });
  ok("10.3 texte absent du dictionnaire : repli sur l'anglais", miss[0] === miss[1] && miss[0].length > 3, miss.join(" | ")); await ctx.close();
  ({ page, ctx } = await open({ q: "?lang=xx" }));
  ok("10.4 ?lang= inconnu : langue de secours (anglais)", (await page.evaluate(() => document.documentElement.lang)) === "en"); await ctx.close();
  ({ page, ctx } = await open({ q: "?lang=ar" }));
  const h10b = await page.evaluate(() => ({ dir: document.documentElement.dir, desc: document.querySelector('meta[name="description"]').content, title: document.title }));
  ok("10.5 arabe : dir rtl et description arabe", h10b.dir === "rtl" && /[؀-ۿ]/.test(h10b.desc), JSON.stringify(h10b));
  const gen = await page.evaluate(async () => { const o = []; for (const l of ["fr", "en", "ar"]) { I18N.lang = l; I18N.d = l === "ar" ? I18N.d : I18N.en; o.push(errMsg(new Error('duplicate key value violates unique constraint "x_pkey"'))); } await loadI18n(); return o; });
  ok("10.6 erreur inconnue : message générique, jamais le texte technique", gen.every(m => !/duplicate|constraint/.test(m) && m.length > 5), gen.join(" | "));
  const fn = await page.evaluate(() => [famName({ name: "Ma famille" }), famName({ name: "Les Test" }), famName(null)]);
  ok("10.7 « Ma famille » traduit tant qu'il n'a pas été changé", /[؀-ۿ]/.test(fn[0]) && fn[1] === "Les Test", fn.join(" | "));
  await page.evaluate(() => A.pickLang()); await page.waitForTimeout(200);
  const nm = await page.evaluate(() => { const d = document.getElementById("sheet"); const id = d.getAttribute("aria-labelledby"); return [id, d.hasAttribute("aria-label"), id && document.getElementById(id).textContent, document.querySelector("#sheet h2").textContent]; });
  ok("10.8 fenêtre nommée par son titre traduit (aria-labelledby)", nm[0] === "sheet-title" && !nm[1] && nm[2] === nm[3] && /[؀-ۿ]/.test(nm[2]), nm.join(" | "));
  // astuces : langue en cours, anglais à défaut
  const tips = await page.evaluate(async () => {
    sb.from = () => { const q = {}; const c = { select: () => c, order: () => c, eq: (k, v) => { q.v = v; return c; }, then: r => { (window.__tq = window.__tq || []).push(q.v); r({ data: q.v === "ar" ? [] : [{ text: "tip-" + q.v }], error: null }); } }; return c; };
    S.screen = "loading"; S.tip = null; I18N.lang = "ar"; await loadTip(); const a = S.tip; I18N.lang = "fr"; await loadTip(); return [a, S.tip, window.__tq.join(",")]; });
  ok("10.9 astuces : langue demandée puis anglais à défaut (jamais le français par défaut)", tips[0] === "tip-en" && tips[1] === "tip-fr" && tips[2] === "ar,en,fr", tips.join(" | "));
  // langue enregistrée (DT13-03) : pour le membre, pas pour qps
  const sv = await page.evaluate(async () => { const log = []; sb.from = t => ({ update: v => ({ eq: () => ({ eq: () => { log.push(t + ":" + JSON.stringify(v)); return Promise.resolve({}); } }) }) });
    S.screen = "parent"; S.family = { id: "f1" }; S.session = { user: { id: "u1" } };
    I18N.lang = "ar"; await saveLang(); I18N.lang = "qps"; await saveLang(); return log; });
  ok("10.10 langue enregistrée pour le membre (ar) mais jamais qps", sv.length === 1 && sv[0] === 'family_members:{"locale":"ar"}', sv.join(" | "));
  // heures après 23:45 refusées
  const late = await page.evaluate(async () => { S.screen = "parent"; document.body.insertAdjacentHTML("beforeend", '<input id="t1" value="07:30"><input id="t2" value="23:50">'); window.__calls = [];
    await A.pushParent(); const a = document.getElementById("toast").textContent, calls = window.__calls.length;
    document.getElementById("t2").value = "23:45"; getPushSub = async () => { throw new Error("stub"); }; let b = ""; try { await A.pushParent(); b = document.getElementById("toast").textContent; } catch (e) { b = "err:" + e.message; }
    return [a, t("push.timeTooLate"), calls, b]; });
  ok("10.11 23:50 refusé (message traduit, rien envoyé)", late[0] === late[1] && late[2] === 0, late.join(" | "));
  ok("10.12 23:45 accepté (pas de refus pour l'heure)", late[3] !== late[1], late[3]);
  ok("10.13 aucune erreur de script", errs.length === 0, errs.join(";")); await ctx.close();
  // Mode enfant ici : pas de rappels
  for (const [fp, want] of [[false, 1], [true, 0]]) {
    ({ page, ctx, errs } = await open({ ls: JSON.stringify({ "sf:childToken": '"tok"', "sf:childCache": JSON.stringify(CHILD_STATE), ...(fp ? { "sf:childFromParent": "true" } : {}) }) }));
    const nb = await page.locator("button.bell").count();
    await page.evaluate(() => A.cReminders()); await page.waitForTimeout(200);
    const open2 = await page.evaluate(() => !!document.getElementById("rem-sheet"));
    ok(`10.14 ${fp ? "Mode enfant ici" : "téléphone de l'enfant"} : cloche ${want ? "présente" : "absente"}, fenêtre ${want ? "ouverte" : "jamais ouverte"}`, nb === want && open2 === !!want, nb + "/" + open2); await ctx.close();
  }
  // service worker : texte de secours traduit (DT11-02) et en.json préchargé
  const vm = require("vm"), swSrc = fs.readFileSync(ROOT + "/sw.js", "utf8");
  const runSw = async (store, data) => {
    const L = {}, shown = []; const mk = m => ({ match: async k => (m[k] ? { text: async () => m[k], json: async () => JSON.parse(m[k]) } : undefined) });
    const cs = { open: async n => mk(store[n] || {}) };
    const ctxv = { self: { registration: { scope: "http://x/app/", showNotification: async (t, o) => shown.push([t, o.body]) }, addEventListener: (n, f) => { L[n] = f; }, location: { origin: "http://x" } }, caches: cs, URL, Request, Response, console, fetch: async () => { throw 0; } };
    vm.runInNewContext(swSrc, ctxv); let pr; L.push({ data: data, waitUntil: p => { pr = p; } }); await pr; return shown[0];
  };
  const dict = l => JSON.stringify(JSON.parse(fs.readFileSync(ROOT + "/i18n/" + l + ".json", "utf8")));
  const C = "soisfier-v32-ep09g";
  const sw1 = await runSw({ "soisfier-lang": { "./sf-lang": "ar" }, [C]: { "./i18n/ar.json": dict("ar"), "./i18n/en.json": dict("en") } }, null);
  ok("10.15 notification sans texte, téléphone en arabe : texte de secours arabe", sw1[1] === JSON.parse(dict("ar")).push.fallback && /[؀-ۿ]/.test(sw1[1]), sw1.join(" | "));
  const sw2 = await runSw({ [C]: { "./i18n/en.json": dict("en") } }, null);
  ok("10.16 langue inconnue : anglais neutre", sw2[1] === JSON.parse(dict("en")).push.fallback, sw2.join(" | "));
  const sw3 = await runSw({}, null);
  ok("10.17 rien en cache : anglais neutre en dur", sw3[1] === "Today's routines 🌱", sw3.join(" | "));
  const sw4 = await runSw({}, { json: () => ({ title: "T", body: "B" }) });
  ok("10.18 texte reçu du serveur : gardé tel quel", sw4[0] === "T" && sw4[1] === "B", sw4.join(" | "));
  ok("10.19 en.json préchargé avec fr.json ; version de cache", /"\.\/i18n\/fr\.json", "\.\/i18n\/en\.json"/.test(swSrc) && swSrc.includes(C));

  // 11. Thème E : palette, accessibilité, prix, jour en cours, avertissement de sortie
  const CS11 = JSON.parse(JSON.stringify(CHILD_STATE)); CS11.today = iso(new Date());
  CS11.routines = [{ id: "rb", title: "Défi", emoji: "💪", moment: "journee", stars: 1, days: [1, 2, 3, 4, 5, 6, 7], is_bonus: true, kind: "regular", created_at: "2026-09-01T08:00:00Z", position: 1 }];
  ({ page, ctx, errs } = await open({ ls: JSON.stringify({ "sf:childToken": '"tok"', "sf:childCache": JSON.stringify(CS11), "sf:pinH": PINH }), cs: CS11 }));
  const pal = await page.evaluate(() => { const c = getComputedStyle(document.documentElement); return [c.getPropertyValue("--leaf").trim(), c.getPropertyValue("--poppy").trim(), c.getPropertyValue("--muted").trim(), document.getElementById("app").hasAttribute("aria-live")]; });
  ok("11.1 palette : leaf #237A49, poppy #C8323A, muted #6B5C52 ; #app sans aria-live", pal[0].toUpperCase() === "#237A49" && pal[1].toUpperCase() === "#C8323A" && pal[2].toUpperCase() === "#6B5C52" && pal[3] === false, pal.join(" "));
  ok("11.2 DT05-04 : que des défis bonus (et non « Pas de routine »)", /Que des défis bonus/.test(await page.locator("main").textContent()));
  const sz = await page.evaluate(() => ["lang-btn", "lock", "bell"].map(c => { const e = document.querySelector("." + c); if (!e) return c + ":absent"; const r = e.getBoundingClientRect(); return c + ":" + Math.round(r.width) + "x" + Math.round(r.height); }));
  ok("11.3 cibles de l'enfant d'au moins 44 px (langue, espace parent, rappels)", sz.every(x => { const m = /(\d+)x(\d+)/.exec(x); return m && +m[1] >= 44 && +m[2] >= 44; }), sz.join(" "));
  await page.click(".lang-btn"); await page.waitForTimeout(200); await page.keyboard.press("Escape"); await page.waitForTimeout(200);
  ok("11.4 focus rendu au bouton qui a ouvert la fenêtre après Échap", await page.evaluate(() => document.activeElement && document.activeElement.classList.contains("lang-btn")));
  const nm11 = await page.evaluate(() => [colorName(COLORS[0]), colorName("#123456"), t("child.colorNames").length]);
  ok("11.5 couleurs : nom traduit, code gardé si inconnue", nm11[0] === "Vert" && nm11[1] === "#123456" && nm11[2] === 6, nm11.join(" "));
  const rel = await page.evaluate(() => { document.body.insertAdjacentHTML("beforeend", `<div id="rt">${relationField(null, "zz")}</div>`); const l = document.getElementById("zz-txtl"), s = document.getElementById("zz-sel"); const a = l.hidden; s.value = "__autre"; s.dispatchEvent(new Event("change", { bubbles: true })); return [a, l.hidden]; });
  ok("11.6 DT02-06 : champ du lien en toutes lettres seulement avec « Autre… »", rel[0] === true && rel[1] === false, rel.join(" "));
  // DT15-01 : retour après minuit
  const mid = await page.evaluate(async () => { S.screen = "parent"; S.family = { id: "f" }; refreshParent = async () => {}; render = () => {};
    const out = []; S.lastToday = "2000-01-01"; S.day = "2000-01-01"; document.dispatchEvent(new Event("visibilitychange")); out.push(S.day === todayISO());
    S.lastToday = "2000-01-01"; S.day = "1999-12-31"; document.dispatchEvent(new Event("visibilitychange")); out.push(S.day === "1999-12-31"); return out; });
  ok("11.7 DT15-01 : retour au jour en cours, sauf jour choisi par l'adulte", mid[0] && mid[1], mid.join(" "));
  // Prix : rythme, prix commun, niveaux, plafond
  const pr = await page.evaluate(() => {
    const mk = (id, child, stars, n) => Array.from({ length: n }, (_, i) => ({ id: id + i, child_id: child, kind: "regular", is_bonus: false, stars, days: [1, 2, 3, 4, 5, 6, 7], active: true }));
    S.children = [{ id: "A", name: "Enfant A" }, { id: "B", name: "Enfant B" }, { id: "C", name: "Enfant C" }];
    S.routines = [...mk("a", "A", 3, 1), ...mk("c", "C", 5, 4), { id: "bo", child_id: "A", kind: "regular", is_bonus: true, stars: 9, days: [1, 2, 3, 4, 5, 6, 7] }, { id: "o1", child_id: "B", kind: "oneoff", is_bonus: false, stars: 9, days: [1], start_day: "2026-01-01", end_day: "2026-01-02" }];
    S.rewards = [];
    const o = {}; o.rA = rhythmOf("A"); o.rB = rhythmOf("B"); o.rC = rhythmOf("C");
    const p1 = pricesFor(10, ["A", "B"], "moment"); o.p1 = JSON.stringify(p1);
    o.p2 = pricesFor(10, ["B"], "moment");
    S.rewards = [{ id: "w1", tier: "petit", duration_days: 3, child_id: null, costs: { A: 25 }, cost: 25 }];
    o.p3 = pricesFor(10, ["A"], "moment").costs.A;
    o.p3b = pricesFor(10, ["A"], "petit").costs.A;
    o.cap = pricesFor(365, ["C"], "grand").costs.C;
    o.fallback = costFor({ costs: { A: 30 }, cost: 30 }, "B");
    o.round = [roundPrice(12.4), roundPrice(47), roundPrice(233), roundPrice(1140), roundPrice(0.3), roundPrice(99999)];
    return o; });
  ok("11.8 rythme : 2,25 ; 0 sans routine obligatoire (exceptionnelle et bonus ignorées) ; 15 pour C", pr.rA === 2.25 && pr.rB === 0 && pr.rC === 15, [pr.rA, pr.rB, pr.rC].join(" "));
  ok("11.9 prix commun : l'enfant sans rythme n'a pas de prix calculé, le commun est le plus petit", pr.p1 === '{"costs":{"A":25},"common":25}', pr.p1);
  ok("11.10 aucun enfant concerné avec un rythme : pas de prix calculé (null)", pr.p2 === null);
  ok("11.11 niveaux dans l'ordre : 25 ⭐ au niveau inférieur => 30 ⭐ au niveau supérieur ; même niveau inchangé", pr.p3 === 30 && pr.p3b === 25, pr.p3 + " / " + pr.p3b);
  ok("11.12 plafond 5 000 (365 jours à 15 ⭐/jour) ; arrondis inchangés", pr.cap === 5000 && pr.round.join() === "12,45,230,1150,1,5000", pr.cap + " / " + pr.round.join());
  ok("11.13 enfant sans prix à lui : prix de la récompense (commun)", pr.fallback === 30);
  // Enregistrer une récompense sans changer la durée : prix figés (DT06-03) ; durée changée : recalcul
  const sv11 = await page.evaluate(async () => {
    S.rewards = [{ id: "w1", title: "Cinéma", emoji: "🎬", tier: "moment", duration_days: 10, child_id: null, costs: { A: 40 }, cost: 40 }];
    S.children = [{ id: "A", name: "Enfant A" }]; S.family = { id: "f" }; S.session = { user: { id: "u" } };
    const cap = []; sb.from = () => ({ update: r => { cap.push(r); return { eq: () => Promise.resolve({ error: null }) }; }, insert: r => Promise.resolve({ error: null }), select: () => ({ eq: () => ({ eq: () => Promise.resolve({ data: [], error: null }) }) }) });
    reloadParent = async () => {}; markPriced = async () => {};
    rewardForm(S.rewards[0]); document.getElementById("w-title").value = "Cinéma 2"; await A.saveReward({ dataset: { id: "w1" } });
    rewardForm(S.rewards[0]); document.getElementById("w-days").value = "20"; await A.saveReward({ dataset: { id: "w1" } });
    return cap.map(r => JSON.stringify([r.title, r.duration_days, r.costs, r.cost])); });
  ok("11.14 modification : titre seul => prix figés (40) ; durée 10 -> 20 => recalcul (45)", sv11[0] === '["Cinéma 2",10,{"A":40},40]' && /"Cinéma",20,\{"A":45\},45/.test(sv11[1]), sv11.join(" | "));
  const nr = await page.evaluate(async () => { S.children = [{ id: "B", name: "Enfant B" }]; S.routines = []; S.rewards = []; let made = false; sb.from = () => ({ insert: () => { made = true; return Promise.resolve({}); } });
    rewardForm(null); document.getElementById("w-title").value = "Glace"; document.getElementById("w-fixed").checked = false; await A.saveReward({ dataset: { id: "" } });
    const msg = document.querySelector("#sheet h2") && document.querySelector("#sheet h2").textContent, link = !!document.querySelector('#sheet [data-act="goRoutines"]');
    rewardForm(null); document.getElementById("w-title").value = "Glace"; document.getElementById("w-fixed").checked = true; document.getElementById("w-cost").value = "12"; made = false; reloadParent = async () => {}; await A.saveReward({ dataset: { id: "" } });
    return [msg, link, made]; });
  ok("11.15 DEC-47 : sans routine obligatoire, pas de prix calculé (message + lien) ; prix fixe permis (DEC-50)", /Pas encore de routine/.test(nr[0]) && nr[1] && nr[2] === true, nr.join(" | "));
  // Avertissement de sortie hors ligne (DT03-04)
  await ctx.close();
  ({ page, ctx, errs } = await open({ ls: JSON.stringify({ "sf:childToken": '"tok"', "sf:childCache": JSON.stringify(CS11), "sf:queue": JSON.stringify([{ rid: "rb", day: CS11.today, done: true, source: "child" }]) }), cs: CS11 }));
  await page.evaluate(d => { flushQueue = async () => {}; localStorage.setItem("sf:queue", JSON.stringify([{ rid: "rb", day: d, done: true, source: "child" }])); }, CS11.today);
  await page.click("button.lock"); await page.waitForTimeout(200);
  const mathTxt = await page.locator("#sheet p").first().textContent(); const nums = (mathTxt.match(/\d+/g) || []).map(Number);
  await page.fill("#m-in", String(nums[0] * nums[1])); await page.click("#m-ok"); await page.waitForTimeout(500);
  const warn = await page.locator("#sheet").textContent();
  ok("11.16 DT03-04 : coches non envoyées => avertissement avec choix d'annuler la sortie", /Pas de connexion/.test(warn) && /Sortir quand même/.test(warn), warn.slice(0, 120));
  await page.click("#c-no"); await page.waitForTimeout(300);
  ok("11.17 sortie annulée : jeton et file conservés", (await lsGet(page, "sf:childToken")) !== null && (await lsGet(page, "sf:queue")) !== null);
  ok("11.18 aucune erreur de script", errs.length === 0, errs.join(";")); await ctx.close();
  const dsrc = fs.readFileSync(ROOT + "/js/data.js", "utf8");
  ok("11.19 DT07-02 : échanges et malus lus sur 30 jours (plus de limite 100 / 500)", /gte\("created_at", addDays\(todayISO\(\), -30\)\)/.test(dsrc) && !/limit\(100\)|limit\(500\)/.test(dsrc));

  // 12. Thème F et prix du référentiel : impression des récompenses, « en attente » dans la grille, aide du scan, prix affichés = prix enregistrés
  ({ page, ctx, errs } = await open({ ls: JSON.stringify({ "sf:childToken": '"tok"', "sf:childCache": JSON.stringify(CS11) }), cs: CS11 }));
  const pg = await page.evaluate(async () => {
    window.print = () => {};
    S.family = { id: "fam" }; S.children = [{ id: "A", name: "Enfant A", emoji: "🐻" }, { id: "B", name: "Enfant B", emoji: "🦊" }];
    S.routines = [{ id: "r1", child_id: "A", kind: "regular", is_bonus: false, stars: 3, days: [1, 2, 3, 4, 5, 6, 7], active: true, title: "Lit", emoji: "🛏️", moment: "matin", created_at: "2026-01-01T00:00:00Z" }];
    S.routinesAll = S.routines; S.completions = []; S.rewards = [{ id: "w1", title: "Cinéma", emoji: "🎬", tier: "moment", duration_days: 10, child_id: null, costs: { A: 25 }, cost: 25 }];
    await printPlanning(["A"], true); const a = [document.querySelectorAll("#print .pp").length, document.querySelectorAll("#print .pp-gifts").length, !!document.querySelector("#print .pp:not(.pp-gifts) .gifts"), document.querySelector("#print .pp-gifts").textContent.includes("Cinéma")];
    await printPlanning(["A"], false); const b = [document.querySelectorAll("#print .pp").length, document.querySelectorAll("#print .pp-gifts").length];
    A.printPlan(); const c = [!!document.getElementById("pr-gifts"), document.getElementById("pr-gifts") && document.getElementById("pr-gifts").checked];
    return { a, b, c }; });
  ok("12.1 récompenses sur une page à part (DEC-41) : 2 pages, aucune sur la page de la semaine", pg.a[0] === 2 && pg.a[1] === 1 && pg.a[2] === false && pg.a[3] === true, JSON.stringify(pg.a));
  ok("12.2 case « Imprimer les récompenses » décochée : aucune page de récompenses", pg.b[0] === 1 && pg.b[1] === 0, JSON.stringify(pg.b));
  ok("12.3 « Planning à imprimer » : case cochée par défaut (DEC-48)", pg.c[0] && pg.c[1] === true, JSON.stringify(pg.c));
  const pd = await page.evaluate(() => { const td = todayISO(); S.completions = [{ routine_id: "r1", child_id: "A", day: addDays(td, -1), validated_at: null }]; REP.child = "A"; REP.week = "cur";
    const first = repFirst("cur"); const html = repGrid(); return [/rp-c[^"]* pend/.test(html), html.includes(t("report.pending")), (html.match(/aria-label="[^"]*en attente[^"]*"/g) || []).length, addDays(td, -1) >= first]; });
  ok("12.4 DT04-09 : coche de l'enfant en attente = rond distinct « en attente », cochable", !pd[3] || (pd[0] && pd[1] && pd[2] >= 1), JSON.stringify(pd));
  ok("12.5 DT04-12 : l'aide du scan conseille de tenir le téléphone immobile", /immobile/.test(await page.evaluate(() => t("scan.help"))));
  const tp = await page.evaluate(async () => {
    S.children = [{ id: "A", name: "Enfant A" }]; S.routines = [{ id: "r1", child_id: "A", kind: "regular", is_bonus: false, stars: 1, days: [1], active: true }]; S.rewards = [];
    S.family = { id: "f" }; const cap = []; sb.from = () => ({ insert: r => { cap.push(...r); return Promise.resolve({ error: null }); }, update: () => ({ eq: () => Promise.resolve({}) }) }); reloadParent = async () => {}; markPriced = async () => {};
    S.currentChild = "A"; A.rewardTemplates();
    const inputs = [...document.querySelectorAll(".tpl input:not(:disabled)")]; const seen = {};
    const show = () => Object.fromEntries([...document.querySelectorAll(".tp")].map(e => [e.dataset.i, +/(\d+)/.exec(e.textContent.replace(/\s/g, ""))[1]]));
    const before = show();
    inputs.filter((_, k) => k % 2 === 0).forEach(i => { i.checked = true; i.dispatchEvent(new Event("change", { bubbles: true })); });
    const after = show(), checked = inputs.filter(i => i.checked).map(i => i.value);
    await A.addRewardTpl();
    const saved = Object.fromEntries(cap.map(r => [String(TPL_W.findIndex(x => x.t === r.title)), r.cost]));
    const same = checked.every(i => saved[i] === after[i]);
    const changed = checked.every(i => checked.every(j => TIER_RANK[TPL_W[+i].tier] >= TIER_RANK[TPL_W[+j].tier] || after[j] > after[i])) && Object.keys(after).some(i => after[i] !== before[i]);
    return { same, changed, n: cap.length, checked: checked.length, sample: checked.map(i => [TPL_W[+i].tier, TPL_W[+i].d, before[i], after[i]]) }; });
  ok("12.6 référentiel : les prix affichés changent à chaque case cochée et le prix enregistré est celui affiché (F06-02 CA9)", tp.same && tp.changed && tp.n === tp.checked && tp.n > 3, JSON.stringify(tp));
  // 13. F04-08 CA1 (BA, DEC-48) : un seul enfant = pas de choix, case récompenses cochée, bouton Imprimer
  const sp = await page.evaluate(() => { S.children = [{ id: "A", name: "Enfant A" }]; closeSheet(); A.printPlan();
    const hid = document.querySelector("dialog#sheet .tpl[hidden] input:checked"); const g = document.getElementById("pr-gifts");
    return { open: dlg.open, hid: !!hid, gifts: !!g && g.checked, btn: !!document.querySelector("[data-act=doPrint]"), visibleChildChoice: [...document.querySelectorAll("dialog#sheet .tpl:not([hidden]) input")].length }; });
  ok("13.1 un seul enfant : « Planning à imprimer » s'ouvre sans choix d'enfant, récompenses cochées, bouton Imprimer", sp.open && sp.hid && sp.gifts && sp.btn && sp.visibleChildChoice === 0, JSON.stringify(sp));
  // 14. Présentation (F14-04, ADR-48)
  const it = await page.evaluate(async () => {
    closeSheet(); const calls = []; sb.auth.updateUser = async a => { calls.push(a); return { error: null }; };
    S.screen = "parent"; S.offline = false; S.session = { user: { id: "u1", user_metadata: { display_name: "X" } } };
    const out = {}; introShown = false; maybeIntro();
    out.open1 = dlg.open; out.t1 = dlg.querySelector("h2").textContent; out.step1 = dlg.querySelector(".muted").textContent;
    A.introNext(); out.t2 = dlg.querySelector("h2").textContent; A.introNext(); out.t3 = dlg.querySelector("h2").textContent; out.alt = dlg.querySelector(".intro-art svg").getAttribute("aria-label");
    out.last = [...dlg.querySelectorAll("button")].map(b => b.dataset.act).join(","); A.introBack(); out.back = dlg.querySelector("h2").textContent === out.t2;
    closeSheet(); await new Promise(r => setTimeout(r, 50));
    out.calls = JSON.stringify(calls); out.seen = introSeen();
    introShown = false; maybeIntro(); out.again = dlg.open;           // déjà vue : ne se rouvre pas
    S.session.user.user_metadata = { intro_seen: true }; introShown = false; maybeIntro(); out.seenNoShow = dlg.open;
    history.pushState(null, "", location.pathname + "?intro=1"); calls.length = 0; introFromLink();   // lien du guide : s'ouvre, n'enregistre rien, retire le paramètre
    out.link = dlg.open && calls.length === 0 && !/intro=1/.test(location.search); closeSheet();
    S.session.user.user_metadata = {}; S.offline = true; introShown = false; maybeIntro(); out.offline = dlg.open; S.offline = false;   // hors ligne : pas de présentation
    return out; });
  ok("14.1 présentation : s'ouvre pour un compte qui ne l'a pas vue, trois écrans, Retour/Suivant/Fermer", it.open1 && it.t1 && it.t2 && it.t3 && it.t1 !== it.t2 && it.t2 !== it.t3 && it.back && /3/.test(it.step1) && it.last === "introBack,closeSheet", JSON.stringify(it));
  ok("14.2 image avec texte de remplacement", !!it.alt, it.alt);
  ok("14.3 « vue » enregistrée dans les métadonnées du compte (auth.updateUser) ; ne se rouvre pas ensuite", it.calls === JSON.stringify([{ data: { intro_seen: true } }]) && it.seen && !it.again && !it.seenNoShow, it.calls);
  ok("14.4 lien du guide ?intro=1 : s'ouvre, n'enregistre rien, retire le paramètre ; pas de présentation hors ligne", it.link && !it.offline, JSON.stringify([it.link, it.offline]));
  ok("12.7 aucune erreur de script", errs.length === 0, errs.join(";")); await ctx.close();
  await browser.close(); srv.close(); console.log(fails ? `\n${fails} KO` : "\nTout OK");
})();
