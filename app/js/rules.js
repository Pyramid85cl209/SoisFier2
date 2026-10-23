"use strict";
/* SoisFier : Calculs : routines dues, Mode vacances, badges, prix, modèles */
/* ================= Calculs ================= */
/* Mode vacances : périodes actives de l'enfant (parent : S.holidays ; enfant : S.cs.holidays), réglages par routine dans « ov » */
const holidaysOf = childId => S.screen === "child" ? ((S.cs && S.cs.holidays) || []) : (S.holidays || []).filter(p => p.child_id === childId);
const periodOn = (childId, day) => holidaysOf(childId).find(p => p.start_day <= day && day <= p.end_day) || null;
const isHolidayR = r => !!r.holiday_period_id;
// Routine telle qu'elle s'applique ce jour-là (null si elle n'est pas due du tout : en pause, ou routine de vacances hors période)
function effective(r, day) {
  if (r.kind === "oneoff") return r;
  const p = periodOn(r.child_id, day);
  if (isHolidayR(r)) return p && p.id === r.holiday_period_id ? r : null;
  const o = p && p.ov && p.ov[r.id]; if (!o) return r;
  if (o.status === "off") return null;
  return { ...r, is_bonus: o.status ? o.status === "bonus" : r.is_bonus, days: o.days || r.days, stars: o.stars || r.stars, adjusted: true };
}
function dueOn(routines, childId, day, comps) {
  const dw = dowOf(day);
  return routines.filter(r => r.child_id === childId && r.active !== false).map(r => {
    if (r.kind === "oneoff") {
      if (!(r.start_day <= day && day <= r.end_day)) return null;
      return (comps || []).some(c => c.routine_id === r.id && c.day !== day) ? null : r;   // déjà faite un autre jour
    }
    const e = effective(r, day);
    return e && (e.days || []).includes(dw) && String(r.created_at || "").slice(0, 10) <= day ? e : null;
  }).filter(Boolean);
}
const isOneoff = r => r.kind === "oneoff";
const oneoffNote = r => r.start_day === r.end_day ? t("oneoff.note") : t("oneoff.noteBefore", { date: fmtLong(r.end_day) });
// Modèles : le titre est lu dans la langue courante (propriété « t »)
const L = (key, o) => Object.defineProperty(o, "t", { get: () => t(key), enumerable: true });
const TPL_X = [
  L("tpl.x.suitcase", { e: "🧳", s: 2, m: "journee" }), L("tpl.x.deepClean", { e: "🧹", s: 3, m: "journee" }),
  L("tpl.x.poolBag", { e: "🏊", s: 1, m: "matin" }), L("tpl.x.tableGuests", { e: "🍽️", s: 2, m: "soir" }),
  L("tpl.x.groceries", { e: "🛒", s: 1, m: "journee" }), L("tpl.x.cook", { e: "🧑‍🍳", s: 2, m: "soir" }),
  L("tpl.x.sortToys", { e: "🧸", s: 3, m: "journee" }), L("tpl.x.birthdayCard", { e: "🎂", s: 2, m: "journee" }),
  L("tpl.x.waterGarden", { e: "🪴", s: 1, m: "soir" }), L("tpl.x.carBoot", { e: "🚗", s: 1, m: "journee" })
];
const B = (k, e, n, c, field, target) => ({ k, e, n, c, ok: s => (typeof target === "number" ? (s[field] || 0) >= target : !!s[field]), p: typeof target === "number" ? s => [Math.min(s[field] || 0, target), target] : null });
const SERIES = (c, field, key, name, list) => list.map(([n, e], i) => B(i === 0 && key.first ? key.first : key.p + n, e, name(n), c, field, n));
// Badges : 1 ou n (le premier palier a souvent un nom à part)
const bn = (k, n) => n === 1 && lget(I18N.fr, `badge.${k}.first`) != null ? t(`badge.${k}.first`) : t(`badge.${k}.n`, { n });
let BADGES = [];
const buildBadges = () => [
  ...SERIES("routines", "done", { p: "r", first: "first" }, n => bn("routines", n),
    [[1, "🌱"], [10, "🌿"], [50, "🪴"], [100, "🌳"], [250, "🌲"], [500, "🏔️"], [1000, "🚀"], [2500, "🛰️"], [5000, "🌍"], [10000, "🌌"], [15000, "👑"]]),
  ...SERIES("stars", "earned", { p: "s" }, n => bn("stars", n),
    [[25, "⭐"], [100, "🌟"], [250, "✨"], [500, "💫"], [1000, "🌠"], [2500, "☄️"], [5000, "🌙"], [10000, "🪐"], [15000, "🏅"]]),
  ...SERIES("regularity", "best", { p: "st" }, n => bn("streak", n),
    [[3, "🔥"], [7, "☀️"], [14, "🌈"], [30, "🏆"], [60, "🥇"], [100, "💯"], [200, "🎖️"], [365, "📅"], [500, "🏛️"]]),
  ...SERIES("garden", "flowers", { p: "f" }, n => bn("flowers", n), [[1, "🌼"], [5, "💐"], [10, "🌺"], [25, "🌸"], [50, "🏵️"], [75, "🌷"]]),
  ...SERIES("garden", "bigCount", { p: "big", first: "big" }, n => bn("bigFlowers", n), [[1, "🌻"], [5, "🌻"], [10, "🌻"], [25, "🌻"], [50, "🌻"]]),
  ...SERIES("garden", "parterres", { p: "parterre", first: "parterre" }, n => bn("beds", n), [[1, "🏡"], [5, "🏘️"], [10, "🌳"], [15, "🏞️"]]),
  B("p_printemps", "🦋", t("badge.bedSeason", { season: SEASON_NAME.printemps }), "garden", "p_printemps"), B("p_ete", "🐝", t("badge.bedSeason", { season: SEASON_NAME.ete }), "garden", "p_ete"),
  B("p_automne", "🍂", t("badge.bedSeason", { season: SEASON_NAME.automne }), "garden", "p_automne"), B("p_hiver", "❄️", t("badge.bedSeason", { season: SEASON_NAME.hiver }), "garden", "p_hiver"),
  ...SERIES("garden", "jardins", { p: "jardin", first: "jardin" }, n => bn("gardens", n), [[1, "🏞️"], [2, "🗺️"], [5, "🏰"]]),
  B("parfait", "💎", t("badge.perfectBed"), "garden", "parfait", 1), B("jcomplet", "🌍", t("badge.fullGarden"), "garden", "jcomplet", 1),
  ...SERIES("challenges", "timers", { p: "timer", first: "timer" }, n => bn("timers", n), [[1, "⚡"], [10, "⏱️"], [50, "🏎️"]]),
  ...SERIES("challenges", "bonus", { p: "bonus", first: "bonus" }, n => bn("bonus", n), [[1, "💪"], [10, "🦾"], [50, "🦸"]]),
  ...SERIES("challenges", "oneoff", { p: "oneoff" }, n => bn("oneoff", n), [[1, "🎯"], [10, "🏹"], [25, "🧭"]]),
  ...SERIES("challenges", "matin", { p: "matin", first: "matin" }, n => bn("mornings", n), [[1, "🌅"], [10, "🐓"], [50, "🌄"]]),
  ...SERIES("challenges", "soir", { p: "soir", first: "soir" }, n => bn("evenings", n), [[1, "🌙"], [10, "🦉"], [50, "🌜"]]),
  ...SERIES("challenges", "full", { p: "full" }, n => bn("fullDays", n), [[1, "✅"], [10, "🎆"]]),
  ...SERIES("challenges", "weekends", { p: "we" }, n => bn("weekends", n), [[1, "🎈"], [10, "🎉"]]),
  B("week1", "🗓️", t("badge.perfectWeek"), "challenges", "weeks", 1),
  ...SERIES("savings", "balance", { p: "save" }, n => bn("saved", n), [[50, "🐷"], [100, "🪙"], [250, "💰"], [500, "🏦"], [1000, "🗝️"]]),
  ...SERIES("savings", "sortie", { p: "sortie" }, n => bn("outings", n), [[1, "🎟️"], [5, "🎪"]]),
  ...SERIES("savings", "grand", { p: "grand" }, n => bn("bigProjects", n), [[1, "🎁"], [3, "🏰"]]),
  ...SERIES("savings", "patience", { p: "patience" }, n => bn("patience", n), [[30, "⏳"], [90, "🐢"]]),
  ...SERIES("serenity", "calm", { p: "calme" }, n => bn("calm", n), [[7, "🕊️"], [14, "🍃"], [30, "🧘"], [60, "🌊"], [100, "⛰️"], [200, "🌤️"], [365, "🌞"], [500, "🏝️"]])
];
const BADGE_CATS = ["routines", "stars", "regularity", "garden", "challenges", "savings", "serenity"];
function computeView({ child, routines, completions, stats, badges, garden, penalties, oneoffDone }) {
  const t = todayISO();
  const mine = routines.filter(r => r.child_id === child.id);
  const isVal = c => c.validated === true || !!c.validated_at;
  const done = new Set(completions.map(c => c.routine_id + "|" + c.day));
  const valid = new Set(completions.filter(isVal).map(c => c.routine_id + "|" + c.day));
  const run = garden ? garden.streak || 0 : 0, best = garden ? garden.best_streak || 0 : 0;
  const fl = garden ? garden.flowers || [] : [];
  const curSeason = garden ? seasonOfISO(garden.today) : "", curYear = garden ? gardenYearOfISO(garden.today) : "";
  const bonusIds = new Set(mine.filter(r => r.is_bonus).map(r => r.id));
  const st = stats || {};
  const earned = st.earned || 0;
  return {
    child, done, valid, earned, balance: Math.max(0, earned - (st.spent || 0) - (st.broken || 0)), current: run, best,
    timers: completions.filter(c => isVal(c) && c.source === "timer").length,
    bonus: completions.filter(c => isVal(c) && bonusIds.has(c.routine_id)).length,
    doneCount: st.done_count || 0, redeemed: st.redeemed_count || 0, flowers: fl.length, big: fl.some(f => f.grade === 3),
    parterre: fl.some(f => f.season !== curSeason || f.garden_year !== curYear), jardin: fl.some(f => f.garden_year !== curYear), garden,
    pendingStars: st.pending_stars || 0, pendingCount: st.pending_count || 0, stored: new Set(badges || []),
    bigCount: fl.filter(f => f.grade === 3).length, cn: (garden && garden.counters) || {},
    groups: (() => { const g = {}; fl.filter(f => f.season !== curSeason || f.garden_year !== curYear).forEach(f => { const k = f.garden_year + "|" + f.season; (g[k] = g[k] || []).push(f); }); return g; })(),
    pastYears: [...new Set(fl.map(f => f.garden_year))].filter(y => y !== curYear),
    todayPerfect: m => { const due = dueOn(mine, child.id, t).filter(r => (m ? r.moment === m && !r.is_bonus : true) && !isOneoff(r)); return due.length > 0 && due.every(r => valid.has(r.id + "|" + t)); },
    seasonsDone: new Set(fl.filter(f => f.season !== curSeason || f.garden_year !== curYear).map(f => f.season)),
    oneoff: oneoffDone != null ? oneoffDone : completions.filter(c => isVal(c) && mine.some(r => r.id === c.routine_id && isOneoff(r))).length,
    matin: perfect(mine, child, completions, valid, "matin"), soir: perfect(mine, child, completions, valid, "soir"),
    calm: (() => { const last = (penalties || []).map(p => p.created_at).sort().pop(); const start = child.garden_start || t;
      const from = last && last.slice(0, 10) > start ? last.slice(0, 10) : start; return Math.max(0, Math.round((parseISO(t) - parseISO(from)) / 864e5)); })()
  };
}
function perfect(mine, child, completions, valid, moment) {
  const days = [...new Set(completions.map(c => c.day))];
  return days.some(day => { const due = dueOn(mine, child.id, day).filter(r => r.moment === moment && !r.is_bonus && !isOneoff(r)); return due.length > 0 && due.every(r => valid.has(r.id + "|" + day)); });
}
const badgeStats = v => {
  const cn = v.cn, groups = Object.values(v.groups), t = todayISO();
  const lastR = cn.last_redeem ? cn.last_redeem.slice(0, 10) : null, start = v.child.garden_start || t;
  const from = lastR && lastR > start ? lastR : start;
  return { done: v.doneCount, earned: v.earned, best: v.best, flowers: v.flowers, bigCount: v.bigCount,
    parterres: groups.length, jardins: v.pastYears.length,
    parfait: groups.filter(g => g.length >= 6 && g.every(f => f.grade === 3)).length,
    jcomplet: v.pastYears.filter(y => ["printemps", "ete", "automne", "hiver"].every(se => v.groups[y + "|" + se])).length,
    p_printemps: v.seasonsDone.has("printemps"), p_ete: v.seasonsDone.has("ete"), p_automne: v.seasonsDone.has("automne"), p_hiver: v.seasonsDone.has("hiver"),
    timers: cn.timers != null ? cn.timers : v.timers, bonus: cn.bonus != null ? cn.bonus : v.bonus, oneoff: cn.oneoff != null ? cn.oneoff : v.oneoff,
    matin: (cn.matin || 0) + (v.todayPerfect("matin") ? 1 : 0), soir: (cn.soir || 0) + (v.todayPerfect("soir") ? 1 : 0), full: (cn.full || 0) + (v.todayPerfect(null) ? 1 : 0),
    weekends: cn.weekends || 0, weeks: cn.weeks || 0,
    balance: v.balance, sortie: cn.sortie || 0, grand: cn.grand || 0,
    patience: Math.max(0, Math.round((parseISO(t) - parseISO(from)) / 864e5)), calm: v.calm };
};
const hasBadge = (v, b) => v.stored.has(b.k) || b.ok(badgeStats(v));
const newBadges = v => BADGES.filter(b => !v.stored.has(b.k) && b.ok(badgeStats(v))).map(b => b.k);
function brokenStar(s = 20) {
  return `<svg class="bstar" width="${s}" height="${s}" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2l2.9 6.3 6.9.7-5.2 4.6 1.5 6.8L12 17l-6.1 3.4 1.5-6.8L2.2 9l6.9-.7z" fill="#B9A89B"/><path d="M12.6 2.5 L10.8 7.6 L13.4 10.6 L10.6 13.8 L12 17" fill="none" stroke="var(--paper)" stroke-width="2.4" stroke-linejoin="round" stroke-linecap="round"/></svg>`;
}

/* ================= Modèles ================= */
const TPL_R = [
  L("tpl.r.bed", { e: "🛏️", m: "matin", p: 0 }),
  L("tpl.r.dress", { e: "👕", m: "matin", p: 0 }),
  L("tpl.r.breakfast", { e: "🥣", m: "matin", p: 2 }),
  L("tpl.r.teethMorning", { e: "🪥", m: "matin", p: 1, tm: 2 }),
  L("tpl.r.face", { e: "🧼", m: "matin", p: 1 }),
  L("tpl.r.hair", { e: "💇", m: "matin", p: 1 }),
  L("tpl.r.shoes", { e: "👟", m: "matin", p: 4, tm: 3 }),
  L("tpl.r.schoolbag", { e: "🎒", m: "matin", p: 4, d: "work" }),
  L("tpl.r.hands", { e: "🧼", m: "midi", p: 1 }),
  L("tpl.r.setTable", { e: "🍽️", m: "midi", p: 2, s: 2 }),
  L("tpl.r.clearPlate", { e: "🍽️", m: "midi", p: 2 }),
  L("tpl.r.toys", { e: "🧸", m: "journee", p: 0, s: 2, tm: 10 }),
  L("tpl.r.homework", { e: "✏️", m: "journee", p: 0, d: "homework", s: 2 }),
  L("tpl.r.read", { e: "📚", m: "journee", p: 3, b: true }),
  L("tpl.r.plants", { e: "🪴", m: "journee", p: 3, b: true }),
  L("tpl.r.pet", { e: "🐟", m: "journee", p: 2 }),
  L("tpl.r.bath", { e: "🛁", m: "soir", p: 1 }),
  L("tpl.r.pyjamas", { e: "🌙", m: "soir", p: 0, tm: 5 }),
  L("tpl.r.teethEvening", { e: "🪥", m: "soir", p: 1, tm: 2 }),
  L("tpl.r.laundry", { e: "🧺", m: "soir", p: 1 }),
  L("tpl.r.clothesTomorrow", { e: "👕", m: "soir", p: 0 }),
  L("tpl.r.toilet", { e: "🚽", m: "soir", p: 1 })
];
// Jours d'un modèle : « work » = jours d'école de la famille ; « homework » = idem sans le jour d'école court (mercredi en France)
const tplDays = d => !d ? [1, 2, 3, 4, 5, 6, 7] : d === "work" ? workDays() : workDays().filter(x => !(WEEK.start === 1 && WEEK.weekend.join() === "6,7" && x === 3));
const TIER_K = ["coup", "petit", "moment", "sortie", "grand", "event"];
const TIERS = () => TIER_K.map(k => [k, t(`tier.${k}.name`), t(`tier.${k}.hint`)]);
const TIER_DAYS = { coup: 1, petit: 3, moment: 10, sortie: 30, grand: 90, event: 30 };
const TPL_W = [
  L("tpl.w.story", { e: "📖", tier: "coup", d: 1 }), L("tpl.w.music", { e: "🎵", tier: "coup", d: 1 }), L("tpl.w.sticker", { e: "⭐", tier: "coup", d: 1 }),
  L("tpl.w.game", { e: "🎲", tier: "petit", d: 2 }), L("tpl.w.dessert", { e: "🍽️", tier: "petit", d: 2 }),
  L("tpl.w.bubbleBath", { e: "🛁", tier: "petit", d: 3 }), L("tpl.w.lateBed", { e: "⏰", tier: "petit", d: 3 }), L("tpl.w.cartoon", { e: "📺", tier: "petit", d: 4 }),
  L("tpl.w.art", { e: "🎨", tier: "moment", d: 7 }), L("tpl.w.cake", { e: "🧁", tier: "moment", d: 7 }),
  L("tpl.w.dinner", { e: "🍕", tier: "moment", d: 10 }), L("tpl.w.hut", { e: "🏕️", tier: "moment", d: 10 }), L("tpl.w.movie", { e: "🎬", tier: "moment", d: 14 }),
  L("tpl.w.picnic", { e: "🧺", tier: "sortie", d: 21 }), L("tpl.w.library", { e: "📚", tier: "sortie", d: 21 }),
  L("tpl.w.pool", { e: "🏊", tier: "sortie", d: 30 }), L("tpl.w.farm", { e: "🐐", tier: "sortie", d: 30 }),
  L("tpl.w.toy", { e: "🚲", tier: "grand", d: 90 }), L("tpl.w.themePark", { e: "🎢", tier: "grand", d: 90 }), L("tpl.w.myDay", { e: "👑", tier: "grand", d: 90 })
];
const TIER_RANK = { coup: 0, petit: 1, moment: 2, sortie: 3, grand: 4, event: 3 };
function rhythmOf(childId) {
  const rs = S.routines.filter(r => r.child_id === childId && !r.is_bonus && !isHolidayR(r)); let tot = 0;
  for (let d = 1; d <= 7; d++) tot += rs.filter(r => (r.days || []).includes(d)).reduce((a, r) => a + r.stars, 0);
  const v = tot / 7 * .75; return v > 0 ? v : 5;
}
function roundPrice(x) { if (x < 20) return Math.max(1, Math.round(x)); if (x < 100) return Math.round(x / 5) * 5; if (x < 500) return Math.round(x / 10) * 10; return Math.round(x / 50) * 50; }
const stepOf = p => p < 20 ? 1 : p < 100 ? 5 : p < 500 ? 10 : 50;
const costFor = (w, childId) => (w.costs && w.costs[childId] != null) ? +w.costs[childId] : w.cost;
const daysLabelFor = (cost, childId) => { const d = Math.max(1, Math.round(cost / rhythmOf(childId))); return d < 14 ? t("effort.days", { n: d }) : d < 60 ? t("effort.weeks", { n: Math.round(d / 7) }) : t("effort.months", { n: Math.round(d / 30) }); };
function pricesFor(days, childIds) { const o = {}; childIds.forEach(id => o[id] = roundPrice(days * rhythmOf(id))); return o; }

const TPL_P = [
  L("tpl.p.tidyRefusal", { e: "😤", s: 1 }),
  L("tpl.p.swear", { e: "🗯️", s: 1 }),
  L("tpl.p.sibling", { e: "😠", s: 1 }),
  L("tpl.p.notListening", { e: "🙉", s: 1 }),
  L("tpl.p.rough", { e: "✋", s: 2 }),
  L("tpl.p.lie", { e: "🤥", s: 2 })
];
