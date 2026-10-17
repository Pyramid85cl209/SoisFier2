"use strict";
/* SoisFier : Écrans de l'enfant */
/* ---------- Enfant ---------- */
function renderChild() {
  const cs = S.cs;
  if (!cs) { app.innerHTML = `<div class="loading">${plantSVG(1)}</div>`; return; }
  const c = cs.child; const routines = cs.routines.map(r => ({ ...r, child_id: c.id }));
  const v = computeView({ child: c, routines, completions: cs.completions, stats: cs.stats, badges: cs.badges, garden: cs.garden, penalties: cs.penalties, oneoffDone: cs.oneoff_done });
  const tabs = [["today", t("ctab.today"), "☀️"], ["gifts", t("ctab.gifts"), "🎁"], ["garden", t("ctab.garden"), "🌼"], ["badges", t("ctab.badges"), "🏅"]];
  const body = { today: cToday, gifts: cGifts, garden: cGarden, badges: cBadges }[S.ctab](v, routines, cs);
  app.innerHTML = `<header class="top kid-top"><span class="hello">${t("kid.hello", { name: esc(c.name) })} ${esc(c.emoji)}</span><span class="star-count" aria-label="${t("kid.starsAria", { n: v.balance })}">⭐ ${fmtNum(v.balance)}</span>${langBtn()}<button class="lock" data-act="exitChild" aria-label="${t("kid.parentSpace")}">🔒</button></header>
    ${S.offline ? `<p class="center"><span class="pill">${t("kid.offline")}</span></p>` : ""}
    <main class="wrap">${body}</main>
    <nav class="tabbar" aria-label="${t("nav")}">${tabs.map(([k, l, e]) => `<button data-act="ctab" data-tab="${k}" class="${S.ctab === k ? "on" : ""}" aria-current="${S.ctab === k ? "page" : "false"}"><span aria-hidden="true">${e}</span>${l}</button>`).join("")}</nav>`;
}
function cToday(v, routines) {
  const td = todayISO(), due = dueOn(routines, v.child.id, td, S.cs.completions);
  const main = due.filter(r => !r.is_bonus), bonus = due.filter(r => r.is_bonus);
  const nd = main.filter(r => v.done.has(r.id + "|" + td)).length;
  const card = r => {
    const d = v.done.has(r.id + "|" + td), val = v.valid.has(r.id + "|" + td);
    return `<li><button class="kcard ${val ? "done" : d ? "pending" : ""}" data-act="cToggle" data-id="${r.id}" aria-pressed="${d}">
      <span class="k-emo" aria-hidden="true">${esc(r.emoji)}</span>
      <span class="k-txt">${isOneoff(r) ? `<small>⭐ ${oneoffNote(r)}</small>` : ""}<b>${esc(r.title)}</b>${d && !val ? `<small>⏳ ${t("kid.parentsWillValidate")}</small>` : val ? (() => { const x = (S.cs.completions || []).find(y => y.routine_id === r.id && y.day === td); return x && x.validated_label && x.validated_label !== "auto" ? `<small>✓ ${t("kid.validatedBy", { who: esc(x.validated_label) })}</small>` : `<small>✓ ${t("kid.validated")}</small>`; })() : r.place ? `<small>📍 ${esc(r.place)}</small>` : ""}</span>
      <span class="k-stars ${d && !val ? "wait" : ""}" aria-label="${t("kid.starsAria", { n: r.stars })}">${"⭐".repeat(Math.min(r.stars, 5))}</span><span class="k-pot" aria-hidden="true">${val ? "✓" : d ? "⏳" : ""}</span></button>
      ${r.timer_minutes && !d ? `<button class="k-timer" data-act="cTimer" data-id="${r.id}">⏱ ${t("kid.challenge", { n: r.timer_minutes })}</button>` : ""}</li>`;
  };
  const ones = due.filter(isOneoff);
  const groups = (ones.length ? `<h3 class="grp">⭐ ${t("kid.oneoffs")}</h3><ul class="kcards">${ones.map(card).join("")}</ul>` : "")
    + MOMENTS().map(([k, l, , e]) => { const rs = main.filter(r => r.moment === k && !isOneoff(r)); return rs.length ? `<h3 class="grp">${e} ${l}</h3><ul class="kcards">${rs.map(card).join("")}</ul>` : ""; }).join("");
  const gn = gardenNow(v.garden);
  return `<section class="hero"><div class="hero-plant ${S.bump ? "bump" : ""}" style="width:120px">${gn ? stageSVG(gn.stage, gn.species, v.child.color) : plantSVG(0, v.child.color)}</div>
      <div class="hero-txt">${gn && gn.waiting ? `<h1>${t("kid.potWaitsSeed")}</h1><p>${t("kid.firstFlowerStarts", { date: fmtLong(gn.start) })}</p>` : gn ? `<h1>${STAGE_NAME[gn.stage]}</h1>${dots14(v.garden)}
      <p>${gn.pausedToday ? t("kid.paused") : t("kid.dayOfOpens", { d: gn.dayIdx, len: gn.len, date: fmtLong(gn.end) })}</p>` : `<h1>${t("kid.potWaits")}</h1>`}
      ${v.pendingStars ? `<p class="wait-note">⏳ ${t("kid.pendingStars", { n: v.pendingStars })}</p>` : ""}</div></section>
    ${periodOn(v.child.id, td) ? `<p class="center"><span class="pill hol-pill">🏖️ ${esc(periodOn(v.child.id, td).name)}</span></p>` : ""}
    <p class="today-count">${main.length ? (nd === main.length ? t("kid.allDone") : t("kid.doneOf", { n: nd, total: main.length })) : t("kid.noRoutine")}</p>
    ${groups}${bonus.filter(r => !isOneoff(r)).length ? `<h3 class="grp">💪 ${t("kid.bonus")}</h3><ul class="kcards">${bonus.filter(r => !isOneoff(r)).map(card).join("")}</ul>` : ""}`;
}
function cGifts(v, routines, cs) {
  const hist = [
    ...cs.redemptions.map(z => ({ ...z, kind: "gift" })),
    ...(cs.penalties || []).map(z => ({ ...z, kind: "broken" }))
  ].sort((a, b) => a.created_at < b.created_at ? 1 : -1).slice(0, 12);
  const mini = miniHero(v);
  return mini + `<div class="balance"><span class="big">⭐ ${fmtNum(v.balance)}</span><span>${t("kid.toSpend", { n: v.balance })}</span>${v.pendingStars ? `<span class="muted">${t("kid.pendingShort", { n: v.pendingStars })}</span>` : ""}</div>
    ${cs.rewards.length ? `<ul class="glist">${cs.rewards.map(w => `<li class="kgift"><span class="g-emo" aria-hidden="true">${esc(w.emoji)}</span><span class="grow"><b>${esc(w.title)}</b><span>${fmtNum(w.cost)} ⭐</span></span>
      ${v.balance >= w.cost ? `<button class="btn" data-act="cRedeem" data-id="${w.id}">${t("kid.choose")}</button>` : `<span class="muted">${t("kid.stillNeed", { n: w.cost - v.balance })}</span>`}</li>`).join("")}</ul>`
      : `<p class="empty">${t("kid.askRewards")}</p>`}
    ${hist.length ? `<h3 class="grp">${t("kid.history")}</h3><ul class="hist">${hist.map(z => z.kind === "gift"
      ? `<li><span>${esc(z.emoji)} ${esc(z.title)}</span><span class="muted">${fmtDate(z.created_at)}</span></li>`
      : `<li>${brokenStar(20)}<span>${t("kid.broken", { title: esc(z.title) })}</span><span class="muted">${fmtDate(z.created_at)}</span><span class="num">−${fmtNum(z.stars)}</span></li>`).join("")}</ul>` : ""}`;
}
function miniHero(v) {
  const gn = gardenNow(v.garden);
  return gn ? `<section class="hero mini"><div class="hero-plant">${stageSVG(gn.waiting ? 0 : gn.stage, gn.species, v.child.color)}</div><div class="hero-txt"><h2>${gn.waiting ? t("kid.potWaitsSeed") : STAGE_NAME[gn.stage]}</h2>${gn.waiting ? "" : dots14(v.garden)}<p class="small">${gn.waiting ? "" : t("kid.opens", { date: fmtLong(gn.end) })}</p></div></section>` : "";
}
function cGarden(v, routines) {
  const gd = v.garden, pushOn = store.get("cpushOn", false), ct = store.get("cpushTimes", ["07:30", "18:00"]);
  let scenes = "";
  if (gd) {
    const se = seasonOfISO(gd.today), yr = gardenYearOfISO(gd.today), fl = gd.flowers || [];
    const cur = fl.filter(f => f.season === se && f.garden_year === yr);
    scenes = `<h2 class="grp">${t("kid.myBed", { season: SEASON_NAME[se] })}</h2><div class="scene">${parterreSVG(se, cur, true)}<p>${t("kid.bedCount", { n: cur.length })}</p></div>`;
    if (isPremium()) scenes += `<h2 class="grp">${t("kid.myGarden", { year: yr })}</h2><div class="scene">${gardenSVG(v.child.name, yr, fl.filter(f => f.garden_year === yr), { season: se })}</div>`;
    const past = [...new Set(fl.map(f => f.garden_year))].filter(y => y !== yr);
    if (past.length && isPremium()) scenes += `<h2 class="grp">${t("kid.oldGardens")}</h2><div class="yr">${past.map(y => `<button class="btn ghost sm" data-act="showYear" data-y="${y}">${y}</button>`).join("")}</div>`;
  }
  return miniHero(v) + scenes + `<p class="streak">${v.current > 0 ? `🔥 ${t("kid.streak", { n: v.current })}` : t("kid.startStreak")}</p>
    <p class="center"><button class="btn ghost" data-act="ctab" data-tab="badges">🏅 ${t("kid.seeBadges")}</button></p>
    <section class="sec" style="margin-top:18px"><h2>${t("kid.settings")}</h2>
      <label class="check"><input type="checkbox" id="snd" data-act="sound" ${store.get("sound", true) ? "checked" : ""}> ${t("kid.sound")}</label>
      <div class="f two"><label>${t("kid.remindMorning")}<input type="time" id="t1" value="${esc(ct[0] || "")}"></label><label>${t("kid.remindEvening")}<input type="time" id="t2" value="${esc(ct[1] || "")}"></label></div>
      <div class="actions"><button class="btn ghost" data-act="pushChild">${pushOn ? t("push.update") : t("push.enable")}</button>${pushOn ? `<button class="btn ghost" data-act="pushOff">${t("btn.disable")}</button>` : ""}</div></section>`;
}

function cBadges(v, routines, cs) {
  const BS = visibleBadges(), bs = badgeStats(v), dates = cs.badge_dates || {}, got = BS.filter(b => hasBadge(v, b)).length;
  const card = b => { const on = hasBadge(v, b), pr = !on && b.p ? b.p(bs) : null;
    return `<div class="badge ${on ? "" : "off"}"><span class="be" aria-hidden="true">${b.e}</span>${b.n}${on && dates[b.k] ? `<small class="bdate">${fmtDate(dates[b.k])}</small>` : ""}${pr ? `<span class="bprog"><i style="width:${Math.round(pr[0] / pr[1] * 100)}%"></i></span><small class="bdate">${fmtNum(pr[0])} / ${fmtNum(pr[1])}</small>` : ""}</div>`; };
  return `<div class="balance"><span class="big">🏅 ${fmtNum(got)}</span><span>${t("kid.badgesOf", { n: got, total: BS.length })}</span></div>
    ${BADGE_CATS.map(c => { const list = BS.filter(b => b.c === c); if (!list.length) return ""; const n = list.filter(b => hasBadge(v, b)).length;
      return `<h2 class="tier-h">${t("badge.cat." + c)}<small>${t("kid.nOf", { n, total: list.length })}</small></h2><div class="badges">${list.map(card).join("")}</div>`; }).join("")}`;
}
