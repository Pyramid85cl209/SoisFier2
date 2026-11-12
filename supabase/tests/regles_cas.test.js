"use strict";
// Jeu de cas partagé (EP-09, DT10-01) joué contre app/js/rules.js : node supabase/tests/regles_cas.test.js
// Le même fichier regles_cas.json est joué en SQL (supabase/tests/ep09c_regles_test.sql) contre private.routine_rules et private.garden_days.
const fs = require("fs"), path = require("path"), vm = require("vm");
const root = path.join(__dirname, "..", "..");
const cas = JSON.parse(fs.readFileSync(path.join(__dirname, "regles_cas.json"), "utf8"));
const src = fs.readFileSync(path.join(root, "app", "js", "rules.js"), "utf8");
const dowOf = d => { const w = new Date(d + "T12:00:00Z").getUTCDay(); return w === 0 ? 7 : w; };
const S = { screen: "parent", family: { timezone: cas.timezone }, holidays: [], pauses: [], gardens: {} };
const ctx = vm.createContext({ S, dowOf, t: k => k, lget: () => null, I18N: { fr: {} }, SEASON_NAME: {}, Intl, Date, console });
vm.runInContext(src + "\nthis.dueOn = dueOn; this.ringOf = ringOf;", ctx);
let fails = 0, n = 0;
const ok = (id, label, got, want) => { n++; if (JSON.stringify(got) !== JSON.stringify(want)) { fails++; console.log(`KO ${id} ${label} : obtenu ${JSON.stringify(got)}, attendu ${JSON.stringify(want)}`); } };
for (const c of cas.cases) {
  S.family.timezone = c.timezone || cas.timezone; S.holidays = [];
  const child = "c1";
  if (c.kind === "regular") {
    const r = c.routine, id = "r1";
    const routine = { id, child_id: child, kind: "regular", created_at: r.created, ended_at: r.ended, active: !r.ended, days: r.days, stars: r.stars, is_bonus: r.bonus, moment: r.moment,
      holiday_period_id: c.holiday_routine ? "p1" : null };
    if (c.settings !== undefined) routine.settings = c.settings.map(s => ({ valid_from: s.from, days: s.days, is_bonus: s.bonus, stars: s.stars }));
    else routine.settings = [{ valid_from: r.created.slice(0, 10), days: r.days, is_bonus: r.bonus, stars: r.stars }];
    if (c.period && c.period.active !== false) S.holidays = [{ id: "p1", child_id: child, start_day: c.period.start, end_day: c.period.end, ov: c.override ? { [id]: { routine_id: id, ...c.override } } : {} }];
    for (const k of c.checks) {
      const due = ctx.dueOn([routine], child, k.day, []);
      ok(c.id, `${k.day} due`, due.length === 1, k.due);
      if (k.due && due.length === 1) { if (k.stars !== undefined) ok(c.id, `${k.day} étoiles`, due[0].stars, k.stars); if (k.bonus !== undefined) ok(c.id, `${k.day} bonus`, !!due[0].is_bonus, k.bonus); }
    }
  } else {
    const o = c.oneoff, routine = { id: "o1", child_id: child, kind: "oneoff", start_day: o.start, end_day: o.end, stars: o.stars, is_bonus: o.bonus, ended_at: o.ended, active: !o.ended, created_at: o.start + "T08:00:00Z" };
    const comps = c.completions.map(d => ({ routine_id: "o1", day: d }));
    for (const k of c.checks) {
      const main = ctx.dueOn([routine], child, k.day, comps).filter(x => !x.is_bonus);
      ok(c.id, `${k.day} compté`, ctx.ringOf(main, k.day, comps).length === 1, k.counted);
    }
  }
}
console.log(fails ? `${fails} échec(s) sur ${n} vérifications` : `Tout OK (${cas.cases.length} cas, ${n} vérifications)`);
process.exit(fails ? 1 : 0);
