// Faux client Supabase pour les captures du mode d'emploi (données fictives, textes de tools/guide/data/<langue>.json via window.__L)
(() => {
  const FX = window.__FXJSON, O = window.__OVR || {}, L = window.__L;
  const now = new Date(); const iso = d => d.toISOString().slice(0, 10);
  const day = n => { const d = new Date(now); d.setDate(d.getDate() + n); return iso(d); };
  const at = (n, h) => { const d = new Date(now); d.setDate(d.getDate() + n); d.setHours(h, 0, 0, 0); return d.toISOString(); };
  const W = FX.W, X = FX.X, P = FX.P;
  const rw = (id, t, e, tier, dd, cost, extra = {}) => ({ id, family_id: "F", title: t, emoji: e, tier, duration_days: dd, costs: { C1: cost }, cost, child_id: null, active: true, ...extra });
  const rewards = [rw("W1", W.story, "📖", "coup", 1, 11), rw("W2", W.dessert, "🍽️", "petit", 2, 25), rw("W3", W.movie, "🎬", "moment", 14, 160),
    rw("W4", W.farm, "🐐", "sortie", 30, 340), rw("W5", W.toy, "🚲", "grand", 90, 1000),
    rw("W6", L.event, "🎪", "event", 10, 110, { event_date: day(12), place: L.place })];
  const routines = FX.routines.concat([{ id: "R20", family_id: "F", child_id: "C1", title: X.suitcase, emoji: "🧳", moment: "journee", stars: 2, days: [],
    is_bonus: true, kind: "oneoff", start_day: day(0), end_day: day(3), active: true, created_at: "2026-09-01T08:00:00Z", position: 20 }]);
  const flowers = [["tournesol", 3, "ete", "2025-2026", -110], ["cosmos-rose", 2, "ete", "2025-2026", -96], ["marguerite", 3, "ete", "2025-2026", -82],
    ["tournesol", 1, "ete", "2025-2026", -68], ["cosmos-orange", 3, "automne", "2026-2027", -28]]
    .map(([s, g, se, y, o], i) => ({ id: "fl" + i, period_start: day(o), period_end: day(o + 13), species: s, grade: g, good_days: 10, active_days: 14, season: se, garden_year: y }));
  const garden = { today: day(0), period_start: day(-5), period_end: day(8), period_len: 14,
    days: [-5, -4, -3, -2, -1, 0].map((n, i) => ({ day: day(n), due: 12, earned: i === 2 ? 4 : 11, paused: false, good: i !== 2 && n !== 0 })),
    flowers, pauses: [], streak: 2, best_streak: 9,
    counters: { timers: 3, bonus: 4, oneoff: 1, sortie: 0, grand: 0, last_redeem: null, matin: 6, soir: 5, full: 2, weeks: 1, weekends: 2 } };
  const F = window.__FIX = Object.assign({
    family_members: [{ family_id: "F", display_name: L.member, role: "parent", created_at: "2026-10-01T10:00:00Z", families: { name: L.family }, user_id: "U", relation: L.rel_parent, locale: L.lang },
      { family_id: "F", display_name: L.member, role: "helper", created_at: "2026-10-02T10:00:00Z", user_id: "U2", relation: L.rel_helper, locale: L.lang }],
    children: [{ id: "C1", family_id: "F", name: L.child, emoji: "🧒", color: "#2E8B57", garden_start: day(-130), price_rhythm: 11.4, position: 0 }],
    routines, rewards,
    completions: [],
    redemptions: [{ id: "Z1", child_id: "C1", title: W.story, emoji: "📖", cost: 11, created_at: at(-2, 18), created_by: "U" }],
    child_stats: [{ child_id: "C1", family_id: "F", earned: 140, done_count: 120, pending_stars: 0, pending_count: 0, spent: 11, redeemed_count: 1, broken: 1, broken_count: 1 }],
    child_devices: [{ id: "DV1", child_id: "C1", created_at: at(-9, 10), label: null }],
    families: [{ name: L.family, auto_validate: true, week_start: L.week_start, weekend_days: L.weekend, timezone: L.tz }],
    penalties: [{ id: "P1", family_id: "F", title: P.swear, emoji: "🗯️", stars: 1, active: true }, { id: "P2", family_id: "F", title: P.lie, emoji: "🤥", stars: 2, active: true }],
    penalty_events: [{ id: "PE1", child_id: "C1", title: P.swear, emoji: "🗯️", stars: 1, created_at: at(-1, 17), created_by: "U" }],
    child_badges: ["first", "r10", "r50", "s25", "s100", "st3", "st7", "f", "f1", "timer", "bonus", "matin", "soir", "we1", "week1", "big", "parterre"].map(k => ({ child_id: "C1", badge_key: k })),
    pauses: [{ id: "PZ1", child_id: "C1", start_day: day(20), end_day: day(27), reason: "trip", created_at: at(-1, 10) }],
    oneoff_templates: [{ id: "OT1", title: X.cook, emoji: "🧑‍🍳", stars: 2, moment: "soir", is_bonus: true, use_count: 3 }],
    tips: [{ text: L.tip }]
  }, O);
  const childState = () => ({ today: day(0), child: { ...F.children[0] }, routines: F.routines.filter(r => r.child_id === "C1"),
    completions: F.completions.map(c => ({ ...c, validated: !!c.validated_at, validated_label: c.validated_at ? L.rel_parent : null })),
    oneoff_done: 1, rewards: F.rewards.filter(w => !w.event_date || w.event_date >= day(0)), redemptions: F.redemptions,
    penalties: F.penalty_events.map(p => ({ id: p.id, title: p.title, emoji: p.emoji, stars: p.stars, created_at: p.created_at })),
    badges: F.child_badges.map(b => b.badge_key), badge_dates: Object.fromEntries(F.child_badges.map(b => [b.badge_key, "2026-09-20T10:00:00Z"])),
    stats: F.child_stats[0], garden, family: F.families[0] });
  const RPC = Object.assign({ family_gardens: () => ({ C1: garden }), get_vapid_public: () => "x", child_state: childState,
    create_child_code: () => "K7P2QX", create_invite: () => "H4TR9B", child_pair: () => ({ token: "tok", child_id: "C1" }), apply_penalty: () => 1 }, window.__RPC || {});
  const chain = table => { let single = false; const p = new Proxy(function () {}, { get(_, k) {
      if (k === "then") return (res, rej) => Promise.resolve({ data: single ? (F[table] || [])[0] : (F[table] || []), error: null }).then(res, rej);
      if (k === "single") return () => { single = true; return p; };
      return () => p; } }); return p; };
  const client = { auth: { getSession: async () => ({ data: { session: window.__SESSION || null } }), onAuthStateChange() {}, signOut: async () => ({}),
      signUp: async () => ({ data: { session: null }, error: null }), signInWithPassword: async () => ({ data: {}, error: null }) },
    from: chain, rpc: async (n, a) => ({ data: RPC[n] ? RPC[n](a) : null, error: null }) };
  window.supabase = { createClient: () => client };
})();
