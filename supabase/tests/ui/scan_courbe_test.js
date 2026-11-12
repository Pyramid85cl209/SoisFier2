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
const OLD = process.env.OLD_SCAN ? fs.readFileSync(process.env.OLD_SCAN, "utf8") : null;
(async () => {
  browser = await chromium.launch({ executablePath: "/usr/bin/google-chrome", args: ["--no-sandbox"] });
  async function sheet(opts, amp, nLines, noise) {
    const ctx = await browser.newContext({ locale: opts.locale || "fr-FR", viewport: { width: 794, height: 1123 }, deviceScaleFactor: 2 });
    await ctx.route("**/config.js", r => r.fulfill({ contentType: "text/javascript", body: fs.readFileSync(ROOT + "/js/config.js", "utf8").replace("__SUPABASE_URL__", "https://x.test").replace("__SUPABASE_KEY__", "k") }));
    await ctx.route("**/supabase.min.js", r => r.fulfill({ contentType: "text/javascript", body: STUB }));
    await ctx.route("**/sw.js", r => r.abort());
    if (OLD) await ctx.route("**/js/scan.js", r => r.fulfill({ contentType: "text/javascript", body: OLD }));
    const page = await ctx.newPage(); const errs = []; page.on("pageerror", e => errs.push(String(e)));
    await page.addInitScript(() => { window.__mock = { session: null, rpc: async () => ({ data: null, error: null }) }; });
    await page.goto("http://localhost:8099/index.html"); await page.waitForTimeout(600);
    const exp = await page.evaluate(async n => {
      window.print = () => {};
      S.family = { id: "fam-test" }; S.children = [{ id: "kid-test", name: "Enfant Test", emoji: "🐻" }];
      const m = ["matin", "journee", "soir"]; S.routines = Array.from({ length: n }, (_, i) => ({ id: "r" + i, child_id: "kid-test", kind: "regular", is_bonus: false, stars: 1, days: [1, 2, 3, 4, 5, 6, 7], active: true, title: "Routine numéro " + (i + 1), emoji: "⭐", moment: m[i % 3], created_at: "2026-01-01T00:00:00Z" }));
      S.routines.sort((a, b) => m.indexOf(a.moment) - m.indexOf(b.moment));
      S.rewards = []; S.completions = []; S.routinesAll = S.routines;
      await printPlanning(["kid-test"], false);
      const tbl = document.querySelector("#print table"); const rows = [...tbl.querySelectorAll("tbody tr")].filter(tr => !tr.classList.contains("grp-row"));
      return rows.map((tr, i) => ({ id: S.routines.find(r => tr.textContent.includes(r.title + " ("))?.id, cells: [...tr.querySelectorAll("td")].slice(1).map(td => td.querySelector(".circ") ? 1 : 0) }));
    }, nLines);
    await page.emulateMedia({ media: "print" }); await page.waitForTimeout(300);
    // positions des ronds (px CSS) avant capture
    const pos = await page.evaluate(() => [...document.querySelectorAll("#print tbody tr:not(.grp-row)")].map(tr => [...tr.querySelectorAll("td")].slice(1).map(td => { const r = td.getBoundingClientRect(); return [r.x + r.width / 2, r.y + r.height / 2, Math.min(r.width, r.height)]; })));
    const png = await page.screenshot({ fullPage: false });
    await page.emulateMedia({ media: "screen" });
    const b64 = png.toString("base64");
    const out = await page.evaluate(async ([b64, pos, amp, noise]) => {
      const img = new Image(); img.src = "data:image/png;base64," + b64; await img.decode();
      const w = img.width, h = img.height, k = w / 794;
      const c0 = document.createElement("canvas"); c0.width = w; c0.height = h; const x0 = c0.getContext("2d"); x0.drawImage(img, 0, 0);
      const expected = new Set();
      pos.forEach((row, ri) => row.forEach(([cx, cy, sz], di) => { if ((ri * 3 + di) % 3 === 0 && (di !== 0 || ri % 2)) { expected.add(ri + "|" + di);
        x0.strokeStyle = "#1a2a8a"; x0.lineWidth = 3.5 * k; x0.lineCap = "round"; x0.beginPath(); x0.moveTo((cx - sz * .28) * k, (cy + sz * .02) * k); x0.lineTo((cx - sz * .06) * k, (cy + sz * .26) * k); x0.lineTo((cx + sz * .3) * k, (cy - sz * .28) * k); x0.stroke(); } }));
      // courbure : décalage horizontal de chaque ligne de pixels (les traits verticaux deviennent des arcs), 0 aux bords haut et bas
      const c1 = document.createElement("canvas"); c1.width = w; c1.height = h; const x1 = c1.getContext("2d"); x1.fillStyle = "#fff"; x1.fillRect(0, 0, w, h);
      const A = amp * w; for (let y = 0; y < h; y++) x1.drawImage(c0, 0, y, w, 1, A * Math.sin(Math.PI * y / h), y, w, 1);
      if (noise) { const id = x1.getImageData(0, 0, w, h), d = id.data; let s = 12345; for (let i = 0; i < d.length; i += 4) { s = (s * 1103515245 + 12345) & 0x7fffffff; const n = ((s % 1000) / 1000 - .5) * noise; d[i] += n; d[i + 1] += n; d[i + 2] += n; } x1.putImageData(id, 0, 0); }
      let res = null, err = null; try { res = await scanRead(c1, w, h); } catch (e) { err = String(e); }
      if (!res) return { read: false, err };
      const got = new Set(); S.routines.forEach(r => { const rows = [...res.marks.keys()]; });
      const order = Array.from({ length: 7 }, (_, i) => ((WEEK.start - 1 + i) % 7) + 1);
      const rowIds = [...document.querySelectorAll("#print tbody tr:not(.grp-row)")].map(tr => S.routines.find(r => tr.textContent.includes(r.title + " (")).id);
      rowIds.forEach((id, ri) => order.forEach((dow, di) => { if (res.marks.get(id)?.has(dow)) got.add(ri + "|" + di); }));
      const miss = [...expected].filter(x => !got.has(x)), extra = [...got].filter(x => !expected.has(x));
      return { read: true, expected: expected.size, miss, extra, unsure: res.unsure.size };
    }, [b64, pos, amp, noise]);
    await ctx.close(); return { out, errs };
  }
  for (const [name, amp, n, noise] of [["plane, 12 lignes", 0, 12, 0], ["plane, 19 lignes", 0, 19, 0], ["courbée 0,8 %, 19 lignes", 0.008, 19, 0], ["courbée 1,2 %, 19 lignes", 0.012, 19, 0], ["courbée 1,2 %, 19 lignes, bruit", 0.012, 19, 24], ["courbée 2 %, 19 lignes", 0.02, 19, 0]]) {
    const { out, errs } = await sheet({}, amp, n, noise);
    ok("scan " + name, out.read && out.miss.length === 0 && out.extra.length === 0 && errs.length === 0, JSON.stringify(out) + errs.join(";"));
  }
  await browser.close(); srv.close(); console.log(fails ? `\n${fails} KO` : "\nTout OK");
})();
