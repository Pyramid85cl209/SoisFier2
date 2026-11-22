/* EP-01 lot 1 : appareil commun, « Qui es-tu ? », code de l'enfant, Mode enfant ici et code d'appareil pour plusieurs enfants.
   Sans navigateur visible, sans base : le client Supabase est remplacé par un double (comme ui_test.js). Usage : node ep01_appareil_commun_test.js [dossier de captures] */
const { chromium } = require("playwright");
const http = require("http"), fs = require("fs"), path = require("path");
const ROOT = path.resolve(__dirname, "../../../app"), SHOTS = process.argv[2] || null;
const MIME = { ".html": "text/html", ".js": "text/javascript", ".json": "application/json", ".css": "text/css", ".png": "image/png", ".webmanifest": "application/json" };
const srv = http.createServer((q, r) => { let p = decodeURIComponent(q.url.split("?")[0]); if (p.endsWith("/")) p += "index.html"; const f = path.join(ROOT, p);
  fs.readFile(f, (e, d) => { if (e) { r.writeHead(404); return r.end(); } r.writeHead(200, { "Content-Type": MIME[path.extname(f)] || "application/octet-stream" }); r.end(d); }); }).listen(8098);
const STUB = `window.supabase = { createClient() { const M = () => window.__mock;
  const sb = { auth: { getSession: async () => ({ data: { session: M().session } }), onAuthStateChange() {}, signInWithPassword: async () => ({ data: {}, error: null }), updateUser: async () => ({}) },
    rpc: async (n, a) => { (window.__calls = window.__calls || []).push([n, a]); return M().rpc(n, a); },
    from() { const c = { select: () => c, eq: () => c, order: () => c, limit: () => c, then: r => r({ data: [], error: null }), update: () => c, insert: () => c, delete: () => c, single: () => c }; return c; } };
  return sb; } };`;
const BASE = { today: "2026-11-11", premium: false, routines: [], holidays: [], completions: [], oneoff_done: 0, rewards: [], redemptions: [], penalties: [], badges: [], badge_dates: {},
  stats: { earned: 0, done_count: 0, pending_stars: 0, pending_count: 0, spent: 0, redeemed_count: 0, broken: 0, broken_count: 0 },
  garden: { today: "2026-11-11", period_start: "2026-11-09", period_end: "2026-11-15", period_len: 7, season: "autumn", garden_year: 1, days: [], flowers: [], pauses: [], streak: 0, best_streak: 0, counters: { timers: 0, bonus: 0, oneoff: 0, sortie: 0, grand: 0, last_redeem: null, matin: 0, soir: 0, full: 0, weeks: 0, weekends: 0 } },
  family: { week_start: 1, weekend_days: [6, 7], timezone: "Europe/Paris" } };
const KIDS = [{ id: "k1", name: "Enfant Un", emoji: "🐻", color: "#2E9E5B" }, { id: "k2", name: "Enfant Deux", emoji: "🦊", color: "#E8484F" }];
let browser, fails = 0;
const ok = (n, c, extra = "") => { if (!c) fails++; console.log((c ? "OK  " : "KO  ") + n + (extra ? "  [" + extra + "]" : "")); };
const calls = (p, n) => p.evaluate(n => (window.__calls || []).filter(c => c[0] === n).map(c => c[1]), n);
async function open(opts) {
  const ctx = await browser.newContext({ locale: opts.locale || "fr-FR", viewport: { width: 390, height: 844 }, colorScheme: opts.dark ? "dark" : "light" });
  await ctx.route("**/config.js", r => r.fulfill({ contentType: "text/javascript", body: fs.readFileSync(ROOT + "/js/config.js", "utf8").replace("__SUPABASE_URL__", "https://x.test").replace("__SUPABASE_KEY__", "k") }));
  await ctx.route("**/supabase.min.js", r => r.fulfill({ contentType: "text/javascript", body: STUB }));
  await ctx.route("**/sw.js", r => r.abort());
  await ctx.route(/fonts\.(googleapis|gstatic)\.com/, r => r.abort());
  const page = await ctx.newPage(); const errs = []; page.on("pageerror", e => errs.push(String(e)));
  await page.addInitScript(([o, base, kids]) => {
    window.__net = "on";
    window.__mock = { session: o.session ? { user: { id: "u1", email: "parent.test@example.invalid" } } : null,
      rpc: async (n, a) => {
        if (n === "child_state") {
          if (window.__net === "off") return { data: null, error: { message: "TypeError: Failed to fetch" } };
          if (window.__gone && a.p_child === window.__gone) return { data: null, error: { message: "SF:device_unknown" } };
          const list = window.__kids; const c = list.find(k => k.id === (a.p_child || list[0].id));
          return { data: { ...base, child: { id: c.id, name: c.name, emoji: c.emoji, color: c.color, garden_start: "2026-10-01" }, common: list.length > 1, device_children: list.length > 1 ? list : [] }, error: null };
        }
        if (n === "child_pair") return { data: window.__pair, error: null };
        if (n === "create_child_code") return { data: "ABC234", error: null };
        if (n === "child_pair_here") return { data: { token: "tok-here", child_id: a.p_child, child_ids: a.p_children }, error: null };
        return { data: null, error: null };
      } };
    window.__kids = JSON.parse(JSON.stringify(kids)).slice(0, o.nkids || kids.length);
    const L = o.ls || {}; for (const k in L) localStorage.setItem(k, L[k]);
  }, [opts, BASE, KIDS]);
  page.on("console", m => { if (process.env.DBG) console.log("console:", m.text()); }); await page.goto("http://localhost:8098/index.html" + (opts.q || ""));
  await page.waitForTimeout(700);
  return { page, ctx, errs };
}
const shot = async (p, name) => { if (SHOTS) await p.screenshot({ path: path.join(SHOTS, name + ".png") }); };
// Touche une suite d'images ; les empreintes sont calculées par la page elle-même (même code que celui du Parent)
async function seq(p, s) { for (const i of s) await p.click(`.kimg[data-i="${i}"]`); await p.waitForTimeout(600); }
const txt = async p => (await p.locator("#toast").textContent()) || "";
(async () => {
  browser = await chromium.launch({ executablePath: fs.existsSync("/usr/bin/google-chrome") ? "/usr/bin/google-chrome" : undefined, args: ["--no-sandbox"] });
  const mkKids = async () => { const { page, ctx } = await open({}); const v = await page.evaluate(async () => [await kidVerifier([0, 1, 2]), await kidVerifier([4, 5, 6])]); await ctx.close(); return KIDS.map((k, i) => ({ ...k, verifier: v[i] })); };
  const KV = await mkKids(); KV.forEach((k, i) => { KIDS[i].verifier = k.verifier; });   // le double du serveur renvoie les empreintes, comme child_state 
  const LS = { "sf:childToken": '"tok-commun"', "sf:childKids": JSON.stringify(KV) };

  // 1. Appareil commun : « Qui es-tu ? » d'abord, aucun appel du serveur sans enfant choisi
  let { page, ctx, errs } = await open({ ls: LS });
  ok("1.1 « Qui es-tu ? » : un bouton par enfant", await page.locator(".kpick-b").count() === 2);
  ok("1.2 prénom lu par le lecteur d'écran (nom accessible)", await page.locator(".kpick-b").first().getAttribute("aria-label") === "Enfant Un");
  ok("1.3 cible d'au moins 44 px", (await page.locator(".kpick-b").first().boundingBox()).height >= 44);
  ok("1.4 aucun appel child_state avant le choix", (await calls(page, "child_state")).length === 0);
  await shot(page, "pick-fr-clair");
  await page.click('.kpick-b[data-id="k1"]');
  ok("1.5 grille du code : 9 images, cible d'au moins 44 px", await page.locator(".kimg").count() === 9 && (await page.locator(".kimg").first().boundingBox()).height >= 44);
  ok("1.5b chaque image a un nom accessible", (await page.locator(".kimg").evaluateAll(b => b.map(x => x.getAttribute("aria-label")))).every(x => x && x.length > 2));
  await shot(page, "code-fr-clair");
  await page.click('.kimg[data-i="0"]'); await page.click('.kimg[data-i="1"]');
  ok("1.6 suite saisie annoncée", /2 sur 3/.test(await page.locator("#kc-live").textContent()), await page.locator("#kc-live").textContent());
  await page.click('.kimg[data-i="8"]'); await page.waitForTimeout(600);
  ok("1.7 mauvaise suite : message d'erreur, toujours sur la grille", /Réessaie/.test(await txt(page)) && await page.locator(".kimg").count() === 9, await txt(page));
  ok("1.8 aucun appel serveur pour vérifier le code (sur l'appareil)", (await calls(page, "child_state")).length === 0);
  for (let i = 0; i < 4; i++) await seq(page, [8, 8, 8]);
  ok("1.9 5 suites fausses : attente d'une minute, images désactivées", /une minute/.test(await page.locator("#kc-help").textContent()) && await page.locator(".kimg:disabled").count() === 9, await page.locator("#kc-help").textContent());
  await shot(page, "code-attente-fr-clair");
  ok("1.10 l'attente vaut pour cet enfant seulement", await page.evaluate(() => kidGuardLeft("k2")) === 0);
  await page.click("[data-act=kidBack]");
  await page.click('.kpick-b[data-id="k2"]');
  ok("1.11 l'autre enfant n'est pas bloqué", await page.locator(".kimg:disabled").count() === 0);
  await seq(page, [4, 5, 6]);
  ok("1.12 bon code : écran de l'enfant, child_state avec p_child", (await calls(page, "child_state")).length === 1 && (await calls(page, "child_state"))[0].p_child === "k2" && /Enfant Deux/.test(await page.locator(".hello").textContent()), JSON.stringify(await calls(page, "child_state")));
  ok("1.13 bouton « Changer d'enfant »", await page.locator("[data-act=kidSwitch]").count() === 1);
  await shot(page, "enfant-fr-clair");
  ok("1.14 copie et compteurs gardés par enfant", await page.evaluate(() => !!localStorage.getItem("sf:childCache:k2") && localStorage.getItem("sf:childCache:k1") === null && localStorage.getItem("sf:lastEarned:k2") !== null));
  await page.click("[data-act=kidSwitch]");
  ok("1.15 « Changer d'enfant » : retour au choix, sans code", await page.locator(".kpick-b").count() === 2);
  await page.evaluate(() => kidGuardReset("k1"));   // l'attente d'une minute est écoulée
  await page.click('.kpick-b[data-id="k1"]'); await seq(page, [0, 1, 2]);
  if (process.env.DBG) console.log(await page.evaluate(() => JSON.stringify([S.screen, S.childNow, S.kidPick, S.kidSeq, document.getElementById("app").innerText.slice(0, 200), document.getElementById("toast").textContent])));
  ok("1.16 l'enfant un ouvre son écran avec son code", /Enfant Un/.test(await page.locator(".hello").textContent()));
  // file d'attente : chaque coche garde son enfant
  await page.evaluate(() => { store.set("queue", [{ rid: "r1", day: "2026-11-11", done: true, source: "child", cid: "k1" }, { rid: "r2", day: "2026-11-11", done: true, source: "child", cid: "k2" }, { rid: "r3", day: "2026-11-11", done: true, source: "child" }]); return flushQueue(); });
  const tg = await calls(page, "child_toggle");
  ok("1.17 flushQueue : p_child par coche (nul pour une coche d'avant la mise à jour)", tg.length === 3 && tg[0].p_child === "k1" && tg[1].p_child === "k2" && tg[2].p_child === null, JSON.stringify(tg.map(x => x.p_child)));
  ok("1.18 aucune erreur de script", errs.length === 0, errs.join(" | "));
  await ctx.close();

  // 2. Rouvrir l'appareil commun : toujours « Qui es-tu ? » ; hors ligne : la copie de l'enfant sert, le code se vérifie sur place
  ({ page, ctx, errs } = await open({ ls: { ...LS, "sf:childCache:k1": JSON.stringify({ ...BASE, child: { ...KIDS[0], garden_start: "2026-10-01" } }) }, q: "" }));
  await page.evaluate(() => { window.__net = "off"; });
  await page.click('.kpick-b[data-id="k1"]'); await seq(page, [0, 1, 2]);
  ok("2.1 hors ligne : code vérifié sur place, copie de l'enfant affichée", /Enfant Un/.test(await page.locator(".hello").textContent()) && await page.locator(".pill").count() >= 1);
  await ctx.close();

  // 3. Un enfant relié disparaît (supprimé par le parent) : l'appareil reste pour les autres
  ({ page, ctx, errs } = await open({ ls: LS }));
  await page.evaluate(() => { window.__gone = "k1"; window.__kids = window.__kids.filter(k => k.id !== "k1"); });
  await page.click('.kpick-b[data-id="k1"]'); await seq(page, [0, 1, 2]);
  const left = await page.evaluate(() => ({ kids: localStorage.getItem("sf:childKids"), tok: localStorage.getItem("sf:childToken"), screen: S.screen }));
  ok("3.1 enfant retiré : l'appareil reste, un seul enfant restant s'ouvre directement", left.tok === '"tok-commun"' && left.kids === null && left.screen === "child" && /Enfant Deux/.test(await page.locator(".hello").textContent()), JSON.stringify(left));
  await ctx.close();

  // 4. Appareil d'un seul enfant (ou d'avant la mise à jour) : pas de « Qui es-tu ? », p_child nul au premier appel
  ({ page, ctx, errs } = await open({ ls: { "sf:childToken": '"tok-seul"' }, nkids: 1 }));
    const cs4 = await calls(page, "child_state");
  ok("4.1 un seul enfant : écran direct, p_child nul", cs4.length >= 1 && cs4[cs4.length - 1].p_child === null && /Enfant Un/.test(await page.locator(".hello").textContent()) && await page.locator("[data-act=kidSwitch]").count() === 0, JSON.stringify(cs4));
  ok("4.2 copie dans la clé d'origine", await page.evaluate(() => !!localStorage.getItem("sf:childCache")));
  ok("4.3 sortie : tout est effacé", await page.evaluate(() => { localStorage.setItem("sf:childCache:k9", "1"); localStorage.setItem("sf:kidGuard:k9", "1"); localStorage.setItem("sf:pinH", "keep"); clearChildStore(); return localStorage.length === 1 && localStorage.getItem("sf:pinH") === "keep"; }));
  await ctx.close();

  // 5. Code d'appareil (pair) pour plusieurs enfants
  ({ page, ctx, errs } = await open({ ls: {} }));
  await page.evaluate(() => { window.__pair = { token: "tok-nouveau", child_id: "k1", child_ids: ["k1", "k2"] }; });
  await page.evaluate(() => { S.screen = "pair"; render(); });
  await page.fill("#p-code", "ABC234"); await page.click("[data-act=pair]"); await page.waitForTimeout(800);
  ok("5.1 appairage de deux enfants : « Qui es-tu ? », liste lue auprès du serveur", await page.locator(".kpick-b").count() === 2 && (await calls(page, "child_state"))[0].p_child === "k1");
  ok("5.2 jeton gardé, pas de copie d'enfant", await page.evaluate(() => localStorage.getItem("sf:childToken") === '"tok-nouveau"' && localStorage.getItem("sf:childCache") === null));
  await ctx.close();

  // 6. Espace parent : code d'appareil et Mode enfant ici pour plusieurs enfants
  const PARENT = async (extra = {}) => {
    const r = await open({ session: true, ls: { "sf:pinH": '{"s":"AA==","h":"AA==","i":1}', ...extra } });
    await r.page.evaluate(([kids]) => {
      S.session = { user: { id: "u1" } }; S.screen = "parent"; S.tab = "family"; S.family = { id: "f1", name: "Famille Test" }; S.me = { user_id: "u1", role: "parent" };
      S.children = kids.map((k, i) => ({ ...k, position: i })); S.members = [{ user_id: "u1", role: "parent", display_name: "Parent Test" }]; S.plan = "founder";
      S.devices = [{ id: "d1", child_id: "k1", child_ids: ["k1", "k2"], label: "Tablette", created_at: "2026-11-01T10:00:00Z" }]; render();
    }, [KIDS]);
    return r;
  };
  ({ page, ctx, errs } = await PARENT());
  ok("6.1 l'appareil commun apparaît sous chaque enfant relié, avec les autres prénoms", await page.locator(".kid-row .dev").count() === 2 && /Enfant Deux/.test(await page.locator(".kid-row .dev").first().textContent()), await page.locator(".kid-row .dev").first().textContent());
  await shot(page, "parent-famille-fr-clair");
  await page.click('[data-act=deviceCode][data-id="k1"]'); await page.waitForTimeout(300);
  ok("6.2 « Connecter son appareil » : choix des enfants, l'enfant touché est coché", await page.locator(".ks-in").count() === 2 && await page.locator(".ks-in:checked").count() === 1);
  await shot(page, "choix-enfants-fr-clair");
  await page.click("#ks-ok"); await page.waitForTimeout(400);
  ok("6.3 un seul enfant coché : code d'appareil sans code d'enfant", (await calls(page, "create_child_code")).length === 1 && (await calls(page, "create_child_code"))[0].p_children.length === 1 && (await calls(page, "set_child_code")).length === 0, JSON.stringify(await calls(page, "create_child_code")));
  await page.click("[data-act=closeSheet]").catch(() => {});
  await page.evaluate(() => closeSheet()); await page.waitForTimeout(200);
  await page.click('[data-act=deviceCode][data-id="k1"]'); await page.check(".ks-in >> nth=1"); await page.click("#ks-ok"); await page.waitForTimeout(400);
  ok("6.4 deux enfants cochés : le Parent choisit d'abord un code pour chacun", await page.locator(".kimg").count() === 9 && /Enfant Un/.test(await page.locator("#sheet h2").textContent()));
  await shot(page, "choix-code-fr-clair");
  ok("6.4b « Valider » désactivé tant que 3 images ne sont pas choisies", await page.locator("#kd-ok").isDisabled());
  for (const i of [0, 1, 2]) await page.click(`.kimg[data-i="${i}"]`);
  ok("6.5 suite choisie affichée au Parent et annoncée", (await page.locator("#kd-slots").textContent()).includes("🐶") && /Chien/.test(await page.locator("#kd-live").textContent()));
  await page.click("#kd-ok"); await page.waitForTimeout(900);
  let sc = await calls(page, "set_child_code");
  ok("6.6 set_child_code : empreinte (sel, hash), jamais la suite", sc.length === 1 && sc[0].p_child === "k1" && sc[0].p_verifier.salt && sc[0].p_verifier.hash && !JSON.stringify(sc[0]).includes("0,1,2"), JSON.stringify(sc[0]).slice(0, 120));
  ok("6.7 puis le code du 2e enfant", /Enfant Deux/.test(await page.locator("#sheet h2").textContent()));
  for (const i of [4, 5, 6]) await page.click(`.kimg[data-i="${i}"]`);
  await page.click("#kd-ok"); await page.waitForTimeout(900);
  const cc = await calls(page, "create_child_code");
  ok("6.8 enfin create_child_code(p_child, p_children) et le code d'appareil s'affiche", cc.length === 2 && cc[1].p_children.length === 2 && /ABC234/.test(await page.locator("#sheet .code").textContent()), JSON.stringify(cc));
  ok("6.9 code d'enfant déjà choisi depuis ce téléphone : pas redemandé", await page.evaluate(() => kidCodeKnown("k1") && kidCodeKnown("k2")));
  await shot(page, "code-appareil-fr-clair");
  await page.evaluate(() => closeSheet()); await page.waitForTimeout(200);
  // Mode enfant ici, deux enfants
  await page.click('[data-act=childHere][data-id="k2"]'); await page.waitForTimeout(300);
  ok("6.10 « Mode enfant ici » : choix des enfants (ordre de la famille)", await page.locator(".ks-in").count() === 2);
  await page.check(".ks-in >> nth=0"); await page.click("#ks-ok"); await page.waitForTimeout(900);
  const ph = await calls(page, "child_pair_here");
  ok("6.11 child_pair_here(5 paramètres) avec les deux enfants et sans jeton connu", ph.length === 1 && ph[0].p_children.length === 2 && ph[0].p_token === null && "p_endpoint" in ph[0], JSON.stringify(ph));
  ok("6.12 « Qui es-tu ? » sur le téléphone du parent, sans rappels", await page.locator(".kpick-b").count() === 2 && await page.evaluate(() => store.get("childFromParent") === true));
  ok("6.13 jeton gardé pour la prochaine fois", await page.evaluate(() => { const m = store.get("sameDevice"); return m.k1 === "tok-here" && m.k2 === "tok-here"; }));
  ok("6.14 aucune erreur de script", errs.length === 0, errs.join(" | "));
  await ctx.close();
  // 6b. Fiche de l'enfant : changer son code
  ({ page, ctx, errs } = await PARENT());
  await page.click('[data-act=editChild][data-id="k1"]'); await page.click("[data-act=kidCodeSet]"); await page.waitForTimeout(300);
  ok("6.15 fiche de l'enfant : « Code de l'enfant » ouvre le choix des 3 images", await page.locator(".kimg").count() === 9);
  await ctx.close();
  // 6c. Un seul enfant dans la famille : pas de choix, comme avant
  ({ page, ctx, errs } = await PARENT());
  await page.evaluate(() => { S.children = S.children.slice(0, 1); render(); });
  await page.click('[data-act=deviceCode][data-id="k1"]'); await page.waitForTimeout(400);
  ok("6.16 un seul enfant : code d'appareil direct", await page.locator(".ks-in").count() === 0 && /ABC234/.test(await page.locator("#sheet .code").textContent()));
  await ctx.close();

  // 7. Arabe (droite à gauche) et thème sombre : captures et sens
  for (const [lang, dark] of [["ar", false], ["fr", true], ["ar", true]]) {
    ({ page, ctx, errs } = await open({ ls: LS, locale: lang, dark, q: lang === "ar" ? "?lang=ar" : "" }));
    const dir = await page.evaluate(() => document.documentElement.dir);
    ok(`7.${lang}${dark ? "s" : ""}.0 sens de lecture`, lang === "ar" ? dir === "rtl" : dir !== "rtl");
    await shot(page, `pick-${lang}-${dark ? "sombre" : "clair"}`);
    await page.click('.kpick-b[data-id="k1"]'); await shot(page, `code-${lang}-${dark ? "sombre" : "clair"}`);
    const over = await page.evaluate(() => document.documentElement.scrollWidth > document.documentElement.clientWidth);
    ok(`7.${lang}${dark ? "s" : ""}.1 pas de défilement horizontal`, !over);
    await seq(page, [0, 1, 2]); await shot(page, `enfant-${lang}-${dark ? "sombre" : "clair"}`);
    await ctx.close();
  }
  console.log(fails ? `${fails} cas en échec` : "Tous les cas sont conformes");
  await browser.close(); srv.close(); process.exit(fails ? 1 : 0);
})().catch(e => { console.error(e); process.exit(2); });
