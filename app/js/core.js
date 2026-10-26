"use strict";
/* SoisFier : Outils, langues, dates et fuseau de la famille, état */
/* ================= Outils ================= */
const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];
const app = $("#app");
const store = {
  get(k, d) { try { const v = localStorage.getItem("sf:" + k); return v == null ? d : JSON.parse(v); } catch { return d; } },
  set(k, v) { try { localStorage.setItem("sf:" + k, JSON.stringify(v)); } catch {} },
  del(k) { try { localStorage.removeItem("sf:" + k); } catch {} }
};
const esc = s => String(s ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const pad = n => String(n).padStart(2, "0");
/* ================= Langues ================= */
// Textes dans i18n/<langue>.json ; « ?lang=qps » active une pseudo-langue de contrôle (textes déformés : tout texte resté en clair est un oubli).
const LANGS = ["fr", "ar", "en"];        // langues proposées (fichier i18n/<code>.json + ligne dans public.languages)
const RTL = ["ar"];                // écriture de droite à gauche
const REVIEW = ["ar", "en"];             // traduction encore à relire (mention dans le choix de la langue)
const I18N = { lang: "fr", d: {}, fr: {} };
I18N.ready = new Promise(r => { I18N.done = r; });
const lget = (o, k) => k.split(".").reduce((a, p) => (a == null ? a : a[p]), o);
const REGION = { en: "en-GB" };   // variante régionale pour les dates et nombres (anglais britannique)
const loc = () => (I18N.lang === "qps" ? "fr" : REGION[I18N.lang] || I18N.lang) + "-u-ca-gregory-nu-latn";   // calendrier grégorien et chiffres 0123 imposés
const fmtNum = n => Number(n).toLocaleString(loc());
function t(k, p = {}) {
  let v = lget(I18N.d, k); if (v == null) v = lget(I18N.fr, k); if (v == null) return k;
  if (v && typeof v === "object" && !Array.isArray(v) && "other" in v) v = v[new Intl.PluralRules(loc()).select(+p.n || 0)] ?? v.other;
  return typeof v === "string" ? v.replace(/\{(\w+)\}/g, (m, x) => p[x] == null ? m : typeof p[x] === "number" ? fmtNum(p[x]) : p[x]) : v;
}
const PSEUDO = { a: "å", e: "é", i: "î", o: "ô", u: "û", c: "ç", n: "ñ", y: "ý", A: "Å", E: "É", I: "Î", O: "Ô", U: "Û", C: "Ç", N: "Ñ" };
function pseudo(o) {
  if (typeof o === "string") return "[" + o.replace(/\{\w+\}|<[^>]*>|./gs, m => m.length > 1 ? m : (PSEUDO[m] || m)) + "]";
  if (Array.isArray(o)) return o.map(pseudo);
  if (o && typeof o === "object") return Object.fromEntries(Object.entries(o).map(([k, v]) => [k, pseudo(v)]));
  return o;
}
async function loadI18n() {
  const want = new URLSearchParams(location.search).get("lang"); if (want) store.set("lang", want);
  const nav = (navigator.language || "fr").slice(0, 2).toLowerCase();
  const lang = store.get("lang", LANGS.includes(nav) ? nav : "fr");
  const get = async l => { const r = await fetch(`i18n/${l}.json`); if (!r.ok) throw new Error(l); return r.json(); };
  try { I18N.fr = await get("fr"); } catch { I18N.fr = {}; }
  I18N.lang = lang === "qps" ? "qps" : LANGS.includes(lang) ? lang : "fr";
  I18N.d = I18N.lang === "qps" ? pseudo(I18N.fr) : I18N.lang === "fr" ? I18N.fr : await get(I18N.lang).catch(() => I18N.fr);
  document.documentElement.lang = I18N.lang === "qps" ? "fr" : I18N.lang;
  document.documentElement.dir = RTL.includes(I18N.lang) ? "rtl" : "ltr";
  document.querySelector('meta[name="description"]').setAttribute("content", t("meta.description"));
  $("#sheet").setAttribute("aria-label", t("dialog"));
  BADGES = buildBadges();
  I18N.done();
}

/* ================= Dates, semaine et fuseau de la famille ================= */
const WEEK = { start: 1, weekend: [6, 7], tz: "Europe/Paris" };   // remplacé par les réglages de la famille au chargement
function setWeek(f) { if (!f) return; WEEK.start = f.week_start || 1; WEEK.weekend = f.weekend_days || []; WEEK.tz = f.timezone || "Europe/Paris"; }
const iso = d => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
// Jour (AAAA-MM-JJ) d'un instant, dans le fuseau de la famille
// Formateurs de dates gardés en mémoire (en créer un par appel est lent sur une longue liste)
const FMT = new Map();
const fmtr = (locale, opts) => { const k = locale + JSON.stringify(opts); let f = FMT.get(k); if (!f) { f = new Intl.DateTimeFormat(locale, opts); FMT.set(k, f); } return f; };
function isoInTz(d) { try { return fmtr("en-CA", { timeZone: WEEK.tz, year: "numeric", month: "2-digit", day: "2-digit" }).format(d); } catch { return iso(d); } }
const todayISO = () => isoInTz(new Date());
const parseISO = s => { const [y, m, d] = s.split("-").map(Number); return new Date(y, m - 1, d); };
const addDays = (s, n) => { const d = parseISO(s); d.setDate(d.getDate() + n); return iso(d); };
const dowOf = s => { const g = parseISO(s).getDay(); return g === 0 ? 7 : g; };
const DAYS = () => t("days.short");           // 1 = lundi … 7 = dimanche
const DAYS_LONG = () => t("days.long");
const weekOrder = () => Array.from({ length: 7 }, (_, i) => ((WEEK.start - 1 + i) % 7) + 1);
const workDays = () => weekOrder().filter(d => !WEEK.weekend.includes(d));
const weekendDays = () => weekOrder().filter(d => WEEK.weekend.includes(d));
const dayName = d => DAYS_LONG()[d - 1];
// Réglages proposés à la création : déduits de la région du téléphone
function detectWeek() {
  const out = { start: 1, weekend: [6, 7], tz: "Europe/Paris" };
  try { const l = new Intl.Locale(navigator.language || "fr-FR"); const w = (l.getWeekInfo && l.getWeekInfo()) || l.weekInfo;
    if (w && w.firstDay) { out.start = w.firstDay; out.weekend = [...(w.weekend || [])].sort((a, b) => a - b); } } catch {}
  try { out.tz = Intl.DateTimeFormat().resolvedOptions().timeZone || out.tz; } catch {}
  return out;
}
const tzList = () => { try { return Intl.supportedValuesOf("timeZone"); } catch { return ["Europe/Paris"]; } };
const tzLabel = z => z.replace(/_/g, " ");
const listFmt = a => { try { return new Intl.ListFormat(loc(), { type: "conjunction" }).format(a); } catch { return a.join(", "); } };
const CAP_DAYS = ["en"];   // langues où les noms de jours gardent leur majuscule en milieu de phrase
const lower = s => CAP_DAYS.includes(I18N.lang) ? s : s.toLocaleLowerCase(loc());
function weekSummary(w) {
  const first = w.weekend.find(d => !w.weekend.includes(((d + 5) % 7) + 1)) || w.weekend[0];   // début du bloc de week-end
  const we = w.weekend.length ? listFmt(w.weekend.slice().sort((a, b) => ((a - first + 7) % 7) - ((b - first + 7) % 7)).map(d => lower(dayName(d)))) : t("week.noWeekend");
  return t("week.summary", { first: lower(dayName(w.start)), weekend: we, tz: tzLabel(w.tz) });
}

const MOMENTS_K = [["matin", "🌅"], ["midi", "🌞"], ["journee", "🌤️"], ["soir", "🌙"]];
// [clé, libellé de groupe, libellé court, emoji]
const MOMENTS = () => MOMENTS_K.map(([k, e]) => [k, t(`moment.${k}.group`), t(`moment.${k}.short`), e]);
const momentLabel = k => t(`moment.${(MOMENTS_K.find(m => m[0] === k) || MOMENTS_K[0])[0]}.short`);
const PLACES = () => t("places");
const COLORS = ["#2E8B57", "#E8484F", "#3D7BD9", "#F29E1F", "#8E5BD0", "#1FA5A0"];
const EMO_R = [
  ["hygiene", ["🪥", "🧼", "🛁", "🚿", "🧴", "💇", "🚽", "🧻", "🤧", "✂️", "💅", "🦷"]],
  ["dressing", ["👕", "👖", "🧦", "👟", "🧥", "🧢", "🧤", "🩳", "👗", "🩴", "🥾", "🎽"]],
  ["meals", ["🥣", "🍽️", "🥛", "💧", "🍎", "🍌", "🥕", "🥦", "🥪", "🍳", "🥄", "🧃"]],
  ["tidying", ["🛏️", "🧸", "🧺", "🧹", "🧽", "🗑️", "📦", "🪣", "🧦", "👞", "🪑", "🚪"]],
  ["school", ["🎒", "✏️", "📚", "📖", "🖍️", "📝", "🧮", "🔤", "🔢", "📏", "🎹", "🎻"]],
  ["home", ["🪴", "🌱", "🐟", "🐶", "🐱", "🐹", "🐰", "🐦", "🔑", "📬", "🧑‍🍳", "🛒"]],
  ["activities", ["⚽", "🚲", "🏃", "🤸", "🧘", "🏊", "🎨", "🧩", "🎵", "🥁", "🏀", "🛴"]],
  ["night", ["🌙", "😴", "🛌", "⏰", "🦉", "⭐", "📖", "🧸", "💤", "🕯️", "🌜", "🛋️"]],
  ["kindness", ["😊", "🤗", "💛", "🙋", "🤝", "👋", "💬", "🙌", "🫶", "👂", "🎁", "🌈"]]
];
const EMO_W = [
  ["treats", ["🍦", "🍫", "🍭", "🍬", "🧁", "🍰", "🍪", "🍩", "🍿", "🥞", "🍕", "🍔"]],
  ["shared", ["🎲", "🧩", "🎨", "🖍️", "📖", "🎬", "📺", "🎮", "🎤", "🎵", "🏕️", "🛁"]],
  ["outside", ["🌳", "🧺", "🛝", "🏞️", "🏖️", "🚲", "🛴", "⚽", "🏀", "🪁", "🦆", "🌻"]],
  ["outings", ["🏊", "🎢", "🎡", "🎠", "🐐", "🐠", "🦁", "🦒", "🏛️", "📚", "🎪", "🎟️"]],
  ["big", ["🎁", "🧸", "🚲", "👑", "🎉", "🎈", "🚂", "✈️", "🚗", "🏰", "🎂", "🌟"]],
  ["perks", ["⏰", "🌙", "🍽️", "🎧", "🎵", "📱", "🛋️", "👕", "🥤", "⭐", "🏆", "💌"]]
];
function emoPicker(target, groups) {
  return `<div class="emo-box">${groups.map(([lbl, list]) => `<div class="emo-grp"><small>${t("emoGroup." + lbl)}</small><div class="emo-row">${[...new Set(list)].map(e => `<button type="button" class="emo" data-act="pickEmoji" data-target="${target}" data-e="${e}" aria-label="${e}">${e}</button>`).join("")}</div></div>`).join("")}</div>`;
}
const EMO_K = ["🧒", "👧", "👦", "👶", "🐻", "🦊", "🐰", "🦁", "🐼", "🦄", "🐸", "🐯", "🐱", "🐶"];
function fmtDay(s) { const td = todayISO(); if (s === td) return t("day.today"); if (s === addDays(td, -1)) return t("day.yesterday"); return t("day.nameNum", { day: dayName(dowOf(s)), num: parseISO(s).getDate() }); }
// Une date seule (AAAA-MM-JJ) reste ce jour-là ; un instant est affiché dans le fuseau de la famille
function fmtDate(ts) {
  const s = String(ts);
  if (/^\d{4}-\d{2}-\d{2}$/.test(s)) return parseISO(s).toLocaleDateString(loc(), { day: "numeric", month: "short" });
  try { return new Date(ts).toLocaleDateString(loc(), { day: "numeric", month: "short", timeZone: WEEK.tz }); } catch { return new Date(ts).toLocaleDateString(loc(), { day: "numeric", month: "short" }); }
}
const fmtTime = ts => { try { return fmtr(loc(), { hour: "2-digit", minute: "2-digit", timeZone: WEEK.tz }).format(new Date(ts)); } catch { return new Date(ts).toLocaleTimeString(loc(), { hour: "2-digit", minute: "2-digit" }); } };
function daysLabel(days) {
  const set = [...new Set(days || [])], same = (a, b) => a.length === b.length && a.every(x => b.includes(x));
  if (set.length === 7) return t("days.all");
  if (WEEK.weekend.length && same(set, workDays())) return t("days.week");
  if (WEEK.weekend.length && same(set, weekendDays())) return t("days.weekend");
  return weekOrder().filter(d => set.includes(d)).map(d => t("days.abbr")[d - 1]).join(" ");
}
function toast(msg, err = false) {
  const el = $("#toast"); el.textContent = msg; el.className = "show" + (err ? " err" : "");
  clearTimeout(toast._t); toast._t = setTimeout(() => el.className = "", 2800);
}
const curLang = () => (I18N.lang === "qps" ? "fr" : I18N.lang);
function errMsg(e) {
  const m = (e && (e.message || e.error_description || e.msg)) || String(e);
  const code = /SF:(\w+)/.exec(m); if (code) return lget(I18N.fr, "srv." + code[1]) != null ? t("srv." + code[1]) : t("srv.unknown");
  if (/Failed to fetch|NetworkError|Load failed|fetch/i.test(m)) return t("err.network");
  if (/Invalid login credentials/i.test(m)) return t("err.badLogin");
  if (/Email not confirmed/i.test(m)) return t("err.notConfirmed");
  if (/already registered/i.test(m)) return t("err.alreadyRegistered");
  if (/Password should be at least/i.test(m)) return t("err.passwordShort");
  if (/rate limit/i.test(m)) return t("err.rateLimit");
  return m;
}
const isNetErr = e => /Failed to fetch|NetworkError|Load failed|fetch/i.test((e && e.message) || String(e)) || !navigator.onLine;

/* ================= État ================= */
const S = {
  screen: "loading", tab: "today", day: todayISO(), authMode: "login",
  session: null, family: null, me: null, children: [], routines: [], rewards: [], completions: [], redemptions: [],
  stats: {}, members: [], devices: [], currentChild: null, tip: null, offline: false,
  penalties: [], pevents: [], badges: {}, autoValidate: true, pauses: [], gardens: {}, oneoffTpl: [],
  cs: null, ctab: "today", form: {}
};
