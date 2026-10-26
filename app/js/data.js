"use strict";
/* SoisFier : Données parent et enfant, rechargements, notifications */
/* ================= Données parent ================= */
async function loadParent() {
  const uid = S.session.user.id;
  const { data: mem, error } = await sb.from("family_members").select("family_id,display_name,role,created_at,families(name)").eq("user_id", uid).order("created_at").limit(1);
  if (error) throw error;
  if (!mem.length) { S.screen = "onboard"; return; }
  S.family = { id: mem[0].family_id, name: mem[0].families?.name || t("onboard.defaultName") }; S.me = mem[0];
  await refreshParent();
}
/* Requêtes du parent, par partie : refreshParent recharge tout, refreshParts seulement ce qu'une action a changé */
const PQ = {
  c: f => sb.from("children").select("*").eq("family_id", f).order("position").order("created_at"),
  r: f => sb.from("routines").select("*").eq("family_id", f).eq("active", true).order("position").order("created_at"),
  w: f => sb.from("rewards").select("*").eq("family_id", f).eq("active", true).order("cost"),
  x: f => sb.from("completions").select("child_id,routine_id,day,stars,source,validated_at,validated_by,created_by").eq("family_id", f).gte("day", addDays(todayISO(), -62)),
  z: f => sb.from("redemptions").select("*").eq("family_id", f).order("created_at", { ascending: false }).limit(100),
  s: f => sb.from("child_stats").select("*").eq("family_id", f),
  m: f => sb.from("family_members").select("user_id,display_name,relation,role").eq("family_id", f),
  d: f => sb.from("child_devices").select("id,child_id,created_at,last_seen,label").eq("family_id", f).order("created_at"),
  f: f => sb.from("families").select("name,auto_validate,week_start,weekend_days,timezone,plan").eq("id", f),
  pe: f => sb.from("penalties").select("*").eq("family_id", f).eq("active", true).order("stars").order("created_at"),
  pv: f => sb.from("penalty_events").select("*").eq("family_id", f).order("created_at", { ascending: false }).limit(500),
  b: f => sb.from("child_badges").select("child_id,badge_key").eq("family_id", f),
  pz: f => sb.from("pauses").select("*").eq("family_id", f).gte("end_day", todayISO()).order("start_day"),
  g: f => sb.rpc("family_gardens", { p_family: f }),
  ot: f => sb.from("oneoff_templates").select("*").eq("family_id", f).order("use_count", { ascending: false }).order("last_used", { ascending: false }),
  hp: f => sb.from("holiday_periods").select("*").eq("family_id", f).eq("active", true).order("start_day"),
  ho: f => sb.from("holiday_overrides").select("*").eq("family_id", f)
};
const OPTIONAL = ["hp", "ho"];   // Mode vacances : facultatif si la base n'est pas encore à jour
async function fetchParts(keys) {
  const fid = S.family.id, qs = await Promise.all(keys.map(k => PQ[k](fid))), o = {};
  keys.forEach((k, i) => { const q = qs[i]; if (q.error && !OPTIONAL.includes(k)) throw q.error; o[k] = q.error ? null : q.data; });
  return o;
}
function applyParts(o) {
  const has = k => k in o;
  if (has("c")) S.children = o.c;
  if (has("r")) S.routines = o.r;
  if (has("w")) S.rewards = o.w;
  if (has("x")) S.completions = o.x;
  if (has("z")) S.redemptions = o.z;
  if (has("s")) S.stats = Object.fromEntries(o.s.map(v => [v.child_id, v]));
  if (has("m")) { S.members = o.m; const me = o.m.find(v => v.user_id === S.session?.user.id); if (me) S.me = { ...S.me, ...me }; }
  if (has("d")) S.devices = o.d;
  if (has("f") && o.f[0]) { const f = o.f[0]; S.autoValidate = f.auto_validate; S.family.name = f.name; S.plan = f.plan || "founder"; setWeek(f); S.family.week = { ...WEEK }; }
  if (has("pe")) S.penalties = o.pe;
  if (has("pv")) S.pevents = o.pv;
  if (has("b")) { const badges = {}; o.b.forEach(v => (badges[v.child_id] = badges[v.child_id] || []).push(v.badge_key)); S.badges = badges; }
  if (has("pz")) S.pauses = o.pz;
  if (has("g")) S.gardens = o.g || {};
  if (has("ot")) S.oneoffTpl = o.ot || [];
  if (has("hp")) S.hp = o.hp || [];
  if (has("ho")) S.ho = o.ho || [];
  if (has("hp") || has("ho")) S.holidays = (S.hp || []).map(p => ({ ...p, ov: Object.fromEntries((S.ho || []).filter(v => v.period_id === p.id).map(v => [v.routine_id, v])) }));
  S.offline = false;
  if (!isParent() && S.tab === "routines") S.tab = "today";
  if (!S.children.find(k => k.id === S.currentChild)) S.currentChild = S.children[0]?.id || null;
}
// Cache du parent, rattaché au compte : affiché dès l'ouverture, puis remplacé par les données fraîches
function saveParentCache() {
  store.set("parentCache", { uid: S.session?.user.id, family: S.family, me: S.me, children: S.children, routines: S.routines, rewards: S.rewards, completions: S.completions, redemptions: S.redemptions, stats: S.stats, members: S.members, devices: S.devices,
    autoValidate: S.autoValidate, penalties: S.penalties, pevents: S.pevents, badges: S.badges, pauses: S.pauses, gardens: S.gardens, week: { ...WEEK }, plan: S.plan, holidays: S.holidays, hp: S.hp, ho: S.ho, oneoffTpl: S.oneoffTpl });
}
function parentCache() {
  const c = store.get("parentCache"), uid = S.session?.user.id;
  return c && c.family && uid && (c.uid || c.me?.user_id) === uid ? c : null;   // jamais le cache d'un autre compte
}
function useParentCache(c) { const { uid, ...rest } = c; Object.assign(S, rest); if (c.week) Object.assign(WEEK, c.week); }
// Écritures en cours : une lecture partie avant la fin d'une écriture est ignorée, puis relancée (pas de retour en arrière visible)
let WRITES = 0, PENDING = 0;
async function mutate(fn) {
  WRITES++; PENDING++;
  try { const res = await fn(); if (res && res.error) throw res.error; return res ? res.data : undefined; }
  finally { PENDING--; WRITES++; }
}
async function fresh(keys) {
  for (let i = 0; i < 4; i++) {
    const w = WRITES, o = await fetchParts(keys);
    if (w === WRITES && !PENDING) { applyParts(o); return true; }
    await new Promise(r => setTimeout(r, 300));
  }
  return false;
}
// Badges obtenus : enregistrés une fois pour toutes
function awardBadges() {
  const rows = [], fid = S.family.id;
  S.children.forEach(k => newBadges(viewFor(k)).forEach(key => { rows.push({ child_id: k.id, family_id: fid, badge_key: key }); (S.badges[k.id] = S.badges[k.id] || []).push(key); }));
  if (rows.length) sb.from("child_badges").upsert(rows, { onConflict: "child_id,badge_key", ignoreDuplicates: true }).then(() => {}, () => {});
}
async function refreshParent() {
  if (!await fresh(Object.keys(PQ))) return;
  awardBadges(); saveParentCache();
}
// Rechargement ciblé : seulement les parties qu'une action a changées ; compteurs, badges et jardins suivent en arrière-plan
async function refreshParts(keys) { if (await fresh(keys)) saveParentCache(); bgRefresh(keys); }
const BG = ["s", "b", "g"];
let bgTimer = null; const bgKeys = new Set();
function bgRefresh(done = []) {
  BG.filter(k => !done.includes(k)).forEach(k => bgKeys.add(k));
  if (!bgKeys.size) return;
  clearTimeout(bgTimer);
  bgTimer = setTimeout(async () => {
    const keys = [...bgKeys]; bgKeys.clear();
    try { if (await fresh(keys)) { awardBadges(); saveParentCache(); if (S.screen === "parent") render(); } } catch {}
  }, 700);
}
// Action à affichage immédiat : l'écran change tout de suite ; si le serveur refuse, il revient en arrière avec un message
async function instant(apply, write, parts, msg) {
  const snap = { completions: S.completions, redemptions: S.redemptions, pevents: S.pevents, stats: structuredClone(S.stats) };
  apply(); render(); if (msg) toast(msg);
  let data;
  try { data = await mutate(write); }
  catch (e) {
    console.error(e); Object.assign(S, snap); render();
    toast(/SF:\w+/.test((e && e.message) || "") ? errMsg(e) : t("common.undone"), true);
    refreshParts(parts).then(render).catch(() => {});
    return { ok: false };
  }
  saveParentCache();
  refreshParts(parts).then(render).catch(() => {});
  return { ok: true, data };
}
// Compteurs de l'enfant ajustés localement en attendant ceux du serveur
function bumpStats(childId, d) {
  const s = S.stats[childId] = { ...(S.stats[childId] || {}) };
  Object.entries(d).forEach(([k, v]) => { s[k] = Math.max(0, (s[k] || 0) + v); });
}
const newId = () => (window.crypto && crypto.randomUUID) ? crypto.randomUUID() : null;
async function loadTip() {
  try {
    let { data } = await sb.from("tips").select("text").eq("locale", curLang()).order("id");
    if (!data || !data.length) ({ data } = await sb.from("tips").select("text").eq("locale", "fr").order("id"));
    if (data && data.length) { const n = Math.floor((Date.now() - new Date(new Date().getFullYear(), 0, 0)) / 864e5); S.tip = data[n % data.length].text; if (S.screen === "parent") render(); }
  } catch {}
}
// Ouverture : la dernière visite s'affiche tout de suite (même compte), les données fraîches suivent en arrière-plan
async function enterParent() {
  const cache = parentCache();
  if (cache) { useParentCache(cache); S.screen = "parent"; loadTip(); } else S.screen = "loading";
  render();
  try { await loadParent(); if (S.screen !== "onboard") { if (!cache) loadTip(); S.screen = "parent"; } }
  catch (e) {
    if (cache && isNetErr(e)) S.offline = true;
    else { S.screen = "error"; S.err = errMsg(e); }
  }
  render();
}
async function reloadParent(msg, parts) { if (parts) await refreshParts(parts); else await refreshParent(); render(); if (msg) toast(msg); }

/* ================= Données enfant ================= */
async function loadChild() {
  const tok = store.get("childToken");
  try {
    const { data, error } = await sb.rpc("child_state", { p_token: tok });
    if (error) throw error;
    S.cs = data; S.offline = false; setWeek(data.family);
    S.cs.badges = S.cs.badges || []; S.cs.penalties = S.cs.penalties || [];
    S.cs.holidays = (S.cs.holidays || []).map(p => ({ ...p, child_id: S.cs.child.id, ov: Object.fromEntries((p.overrides || []).map(o => [o.routine_id, o])) }));
    applyQueueToState();
    const last = store.get("lastEarned"), e = S.cs.stats.earned || 0;
    let gain = null;
    if (last != null && e > last) gain = { diff: e - last };
    store.set("lastEarned", e);
    const fls = (S.cs.garden && S.cs.garden.flowers) || [], seen = store.get("seenFlowers");
    const fresh = seen == null ? [] : fls.slice(seen);
    store.set("seenFlowers", fls.length);
    if (fresh.length) setTimeout(() => bloomCeremony(fresh[fresh.length - 1]), 900);
    const routines = S.cs.routines.map(r => ({ ...r, child_id: S.cs.child.id }));
    const nb = newBadges(computeView({ child: S.cs.child, routines, completions: S.cs.completions, stats: S.cs.stats, badges: S.cs.badges, garden: S.cs.garden, penalties: S.cs.penalties, oneoffDone: S.cs.oneoff_done }));
    if (nb.length) { sb.rpc("child_award_badges", { p_token: tok, p_keys: nb }).then(() => {}, () => {}); S.cs.badges.push(...nb); }
    store.set("childCache", S.cs);
    const shown = nb.map(k => visibleBadges().find(b => b.k === k)).filter(Boolean);
    if (gain || shown.length) setTimeout(() => {
      celebrate(true);
      const names = shown.map(b => b.e + " " + b.n).join(t("sep"));
      toast(gain ? t("kid.gain", { n: gain.diff }) : t("kid.newBadge", { names }));
      if (gain && shown.length) setTimeout(() => toast(t("kid.newBadge", { names })), 3000);
    }, 400);
  } catch (e) {
    if (/Appareil non reconnu|SF:device_unknown/.test(e.message || "")) {
      store.del("childToken"); store.del("childCache"); store.del("queue");
      S.screen = "auth"; render(); toast(t("kid.disconnected"), true); return;
    }
    S.cs = store.get("childCache"); S.offline = true; if (S.cs) setWeek(S.cs.family);
    if (!S.cs) { S.screen = "error"; S.err = errMsg(e); }
  }
  render();
}
function applyQueueToState() {
  const q = store.get("queue", []), st = S.cs.stats;
  for (const op of q) {
    const i = S.cs.completions.findIndex(c => c.routine_id === op.rid && c.day === op.day);
    const r = S.cs.routines.find(x => x.id === op.rid); if (!r) continue;
    if (op.done && i < 0) { S.cs.completions.push({ routine_id: op.rid, day: op.day, stars: r.stars, source: op.source, validated: false }); st.pending_stars = (st.pending_stars || 0) + r.stars; st.pending_count = (st.pending_count || 0) + 1; }
    if (!op.done && i >= 0 && !S.cs.completions[i].validated) { st.pending_stars -= S.cs.completions[i].stars; st.pending_count--; S.cs.completions.splice(i, 1); }
  }
}
let flushing = false;
async function flushQueue() {
  if (flushing || !store.get("childToken")) return; flushing = true;
  try {
    let q = store.get("queue", []);
    while (q.length) {
      const op = q[0];
      let res;
      try { res = await sb.rpc("child_toggle", { p_token: store.get("childToken"), p_routine: op.rid, p_day: op.day, p_done: op.done, p_source: op.source }); }
      catch (e) { res = { error: e }; }
      if (res.error && isNetErr(res.error)) { S.offline = true; break; }
      q.shift(); store.set("queue", q);
    }
    if (!q.length && S.offline) { S.offline = false; if (S.screen === "child") await loadChild(); }
  } finally { flushing = false; }
}
function childToggle(rid, makeDone, source = "child") {
  const cs = S.cs, st = cs.stats, day = todayISO(), r = cs.routines.find(x => x.id === rid); if (!r) return;
  const i = cs.completions.findIndex(c => c.routine_id === rid && c.day === day);
  if (makeDone && i < 0) { cs.completions.push({ routine_id: rid, day, stars: r.stars, source, validated: false }); st.pending_stars = (st.pending_stars || 0) + r.stars; st.pending_count = (st.pending_count || 0) + 1; }
  else if (!makeDone && i >= 0) {
    if (cs.completions[i].validated) return toast(t("kid.alreadyValidated"));
    st.pending_stars -= cs.completions[i].stars; st.pending_count--; cs.completions.splice(i, 1);
  }
  else return;
  store.set("childCache", cs);
  const q = store.get("queue", []); q.push({ rid, day, done: makeDone, source }); store.set("queue", q);
  if (makeDone) {
    S.bump = true; render(); S.bump = false;
    const routines = cs.routines.map(x => ({ ...x, child_id: cs.child.id }));
    const main = dueOn(routines, cs.child.id, day, cs.completions).filter(x => !x.is_bonus);
    const all = main.length && main.every(x => cs.completions.some(c => c.routine_id === x.id && c.day === day));
    celebrate(all);
    toast(all ? t("kid.allDoneToast") : t("kid.bravoToast"));
  } else render();
  flushQueue();
}

/* ================= Notifications ================= */
function urlB64(base64) {
  const p = "=".repeat((4 - base64.length % 4) % 4), b = (base64 + p).replace(/-/g, "+").replace(/_/g, "/");
  const raw = atob(b); return Uint8Array.from([...raw].map(ch => ch.charCodeAt(0)));
}
async function getPushSub() {
  if (!("serviceWorker" in navigator) || !("PushManager" in window)) throw new Error(t("push.unsupported"));
  const perm = await Notification.requestPermission();
  if (perm !== "granted") throw new Error(t("push.blocked"));
  const reg = await navigator.serviceWorker.ready;
  let sub = await reg.pushManager.getSubscription();
  if (!sub) {
    const { data: vk, error } = await sb.rpc("get_vapid_public"); if (error) throw error;
    sub = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: urlB64(vk) });
  }
  return sub.toJSON();
}
const readTimes = () => [$("#t1")?.value, $("#t2")?.value].filter(v => /^\d{2}:\d{2}$/.test(v || ""));
