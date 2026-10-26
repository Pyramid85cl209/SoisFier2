"use strict";
/* SoisFier : Écrans du parent */
/* ---------- Parent ---------- */
const curChild = () => S.children.find(c => c.id === S.currentChild) || S.children[0];
function viewFor(c) {
  return computeView({ child: c, routines: S.routines, completions: S.completions.filter(x => x.child_id === c.id), stats: S.stats[c.id], badges: S.badges[c.id], garden: S.gardens[c.id], penalties: S.pevents.filter(e => e.child_id === c.id) });
}
function chips() {
  return `<div class="chips" role="tablist">${S.children.map(c => `<button role="tab" aria-selected="${c.id === S.currentChild}" class="chip ${c.id === S.currentChild ? "on" : ""}" style="--c:${esc(c.color)}" data-act="pickChild" data-id="${c.id}">${esc(c.emoji)} ${esc(c.name)}</button>`).join("")}</div>`;
}
function renderParent() {
  const tabs = [["today", t("tab.today"), "☀️"], ["routines", t("tab.routines"), "📋"], ["rewards", t("tab.rewards"), "🎁"], ["malus", t("tab.malus"), "💔"], ["family", t("tab.family"), "🏡"]].filter(x => isParent() || x[0] !== "routines");
  let body;
  if (!S.children.length && S.tab !== "family") body = `<section class="card center">${plantSVG(0)}<h1>${t("parent.startTitle")}</h1><p>${t("parent.startText")}</p><button class="btn" data-act="newChild">${t("child.add")}</button></section>`;
  else body = { today: pToday, routines: pRoutines, rewards: pRewards, malus: pMalus, family: pFamily }[S.tab]();
  app.innerHTML = `<header class="top"><div class="brand">${miniLogo()}<span>${esc(S.family?.name || "SoisFier")}</span></div><div class="top-r">${S.offline ? `<span class="pill">${t("offline")}</span>` : ""}${langBtn()}<a class="help" href="${guideHref()}" aria-label="${t("help")}">?</a></div></header>
    <main class="wrap">${body}</main>
    <nav class="tabbar" aria-label="${t("nav")}">${tabs.map(([k, l, e]) => `<button data-act="tab" data-tab="${k}" class="${S.tab === k ? "on" : ""}" aria-current="${S.tab === k ? "page" : "false"}"><span aria-hidden="true">${e}</span>${l}</button>`).join("")}</nav>`;
}
function rowP(c, r, day, v) {
  const k = r.id + "|" + day, d = v.done.has(k), val = v.valid.has(k);
  const parts = [];
  if (isOneoff(r)) parts.push("⭐ " + oneoffNote(r));
  parts.push(momentLabel(r.moment));
  if (r.is_bonus) parts.push(t("routine.bonus"));
  if (d && !val) parts.push(t("routine.pending"));
  if (val) { const x = S.completions.find(y => y.routine_id === r.id && y.day === day); if (x) parts.push("✓ " + esc(whoValidated(x))); }
  return `<li><button class="rt ${val ? "done" : d ? "pending" : ""}" data-act="pToggle" data-child="${c.id}" data-id="${r.id}" aria-pressed="${d}">
    <span class="rt-emo" aria-hidden="true">${esc(r.emoji)}</span>
    <span class="rt-txt"><b>${esc(r.title)}</b><small>${parts.join(t("sep"))}</small></span>
    <span class="rt-stars">+${fmtNum(r.stars)} ⭐</span><span class="pot" aria-hidden="true">${val ? "🌱" : d ? "⏳" : ""}</span></button></li>`;
}
function pendingBlock() {
  const pend = S.completions.filter(x => !x.validated_at).sort((a, b) => a.day < b.day ? -1 : 1);
  if (!pend.length) return "";
  return `<section class="validate"><div class="v-head"><h2>${t("validate.title")}</h2><button class="btn sm" data-act="validateAll">${t("validate.all", { n: pend.length })}</button></div>
    <ul class="vlist">${pend.map(x => {
      const r = S.routines.find(y => y.id === x.routine_id) || { title: t("routine.deleted"), emoji: "⭐", stars: x.stars };
      const c = S.children.find(y => y.id === x.child_id) || { name: "" };
      const parts = [esc(c.name), lower(fmtDay(x.day)), `+${fmtNum(x.stars)} ⭐`];
      if (x.source === "timer") parts.push(t("validate.timer"));
      parts.push(t("validate.checkedBy", { who: x.created_by ? esc(memberLabel(x.created_by)) : esc(c.name) }));
      return `<li><span class="rt-emo" aria-hidden="true">${esc(r.emoji)}</span><span class="grow"><b>${esc(r.title)}</b><small>${parts.join(t("sep"))}</small></span>
        <button class="vbtn no" data-act="refuseOne" data-id="${x.routine_id}" data-day="${x.day}" aria-label="${t("validate.refuse")}">✕</button>
        <button class="vbtn yes" data-act="validateOne" data-id="${x.routine_id}" data-day="${x.day}" aria-label="${t("btn.validate")}">✓</button></li>`;
    }).join("")}</ul>
    <p class="muted small">${S.autoValidate ? t("validate.autoOn") : t("validate.autoOff")}</p></section>`;
}
function pToday() {
  const day = S.day, td = todayISO();
  const nav = `<div class="daynav"><button data-act="dayPrev" aria-label="${t("day.prev")}" ${day <= addDays(td, -6) ? "disabled" : ""}>‹</button><h1>${fmtDay(day)}</h1><button data-act="dayNext" aria-label="${t("day.next")}" ${day >= td ? "disabled" : ""}>›</button></div>`;
  const tip = S.tip && day === td ? `<aside class="tip"><span aria-hidden="true">💡</span><p>${esc(S.tip)}</p></aside>` : "";
  const blocks = S.children.map(c => {
    const v = viewFor(c), due = dueOn(S.routines, c.id, day, S.completions);
    const main = due.filter(r => !r.is_bonus), bonus = due.filter(r => r.is_bonus);
    const nd = main.filter(r => v.done.has(r.id + "|" + day)).length;
    const n = gardenNow(S.gardens[c.id]);
    return `<section class="kid" style="--c:${esc(c.color)}">
      <div class="kid-head"><button class="kid-plant" data-act="showGarden" data-id="${c.id}" aria-label="${t("garden.see", { name: esc(c.name) })}" style="border:0;background:none;padding:0">${n ? stageSVG(n.stage, n.species, c.color) : plantSVG(0, c.color)}</button>
        <div><h2>${esc(c.emoji)} ${esc(c.name)}</h2><p class="meta"><span>⭐ ${t("parent.toSpend", { n: v.balance })}</span>${!n ? "" : n.waiting ? `<span>🌱 ${t("garden.firstFrom", { date: fmtLong(n.start) })}</span>` : `<span>🌱 ${t("garden.dayOf", { d: n.dayIdx, len: n.len })}${t("sep")}${t("garden.goodDays", { n: n.good })}</span>`}${v.current > 1 ? `<span>🔥 ${t("parent.inARow", { n: v.current })}</span>` : ""}${periodOn(c.id, day) ? `<span>🏖️ ${esc(periodOn(c.id, day).name)}</span>` : ""}</p></div>
        <div class="ring" style="--p:${main.length ? Math.round(nd / main.length * 100) : 0}" aria-label="${t("parent.doneOf", { n: nd, total: main.length })}"><span>${fmtNum(nd)}/${fmtNum(main.length)}</span></div></div>
      ${due.length ? `<ul class="rlist">${[...due.filter(isOneoff), ...main.filter(r => !isOneoff(r)), ...bonus.filter(r => !isOneoff(r))].map(r => rowP(c, r, day, v)).join("")}</ul>`
        : `<p class="empty">${t("parent.nothing")}${isParent() ? ` <button class="link" data-act="tab" data-tab="routines" data-child="${c.id}">${t("parent.addRoutines")}</button>` : ""}</p>`}
      ${day === td ? `<div class="actions" style="margin:10px 0 0"><button class="btn sm ghost" data-act="newOneoff" data-child="${c.id}">+ ${t("oneoff.btn")}${ptag()}</button></div>` : ""}
    </section>`;
  }).join("");
  return nav + (day === td ? pendingBlock() + nudge() : "") + tip + blocks;
}
function pRoutines() {
  const c = curChild(), t0 = todayISO(), hp = periodOn(c.id, t0), vac = !!hp && !S.showHabitual;
  if (!dlg.open) { S.hctx = vac ? hp.id : null; S.reviewing = null; }
  const habit = S.routines.filter(r => r.child_id === c.id && !isOneoff(r) && !isHolidayR(r));
  // Pendant des vacances : routines habituelles telles qu'elles s'appliquent, puis routines de vacances
  const list = vac ? [...habit.map(r => ({ ...(effective(r, t0) || r), off: !effective(r, t0), habit: true })), ...S.routines.filter(r => r.holiday_period_id === hp.id).map(r => ({ ...r, hol: true }))] : habit;
  const banner = hp ? `<div class="banner hol"><p>🏖️ <b>${esc(hp.name)}</b>${t("sep")}${t("hol.until", { date: fmtLong(hp.end_day) })}</p><p class="small">${vac ? t("hol.vacView") : t("hol.habitView")}</p>
    <button class="btn sm ghost" data-act="toggleHabitual">${vac ? t("hol.seeHabitual") : t("hol.seeVac")}</button></div>` : "";
  const oneoffs = S.routines.filter(r => r.child_id === c.id && isOneoff(r) && r.end_day >= t0).sort((a, b) => a.start_day < b.start_day ? -1 : 1);
  const extra = `<h3 class="grp">⭐ ${t("oneoff.current")}</h3>${oneoffs.length ? `<ul class="hist">${oneoffs.map(r => `<li><span>${esc(r.emoji)} ${esc(r.title)}</span><span class="muted">${r.start_day === r.end_day ? fmtDate(r.start_day) : t("oneoff.beforeShort", { date: fmtDate(r.end_day) })}${t("sep")}${r.is_bonus ? t("routine.bonus") : t("routine.mandatory")}</span><button class="link" data-act="delOneoff" data-id="${r.id}">${t("btn.delete")}</button></li>`).join("")}</ul>` : `<p class="muted">${t("common.none")}</p>`}
    <div class="actions"><button class="btn ghost" data-act="newOneoff" data-child="${c.id}">+ ${t("oneoff.btn")}${ptag()}</button><button class="btn ghost" data-act="manageOneoffTpl">${t("oneoff.manageTpl")}${ptag()}</button></div>`;
  const groups = MOMENTS().map(([k, l, , e]) => {
    const rs = list.filter(r => r.moment === k); if (!rs.length) return "";
    return `<h3 class="grp">${e} ${l}</h3><ul class="rlist">${rs.map(r => {
      const parts = r.off ? [t("hol.off")] : [daysLabel(r.days)];
      if (!r.off && r.place) parts.push(esc(r.place));
      if (!r.off && r.timer_minutes) parts.push("⏱ " + t("routine.minutes", { n: r.timer_minutes }));
      if (!r.off && r.is_bonus) parts.push(t("routine.bonus"));
      if (r.adjusted) parts.push(t("hol.adjusted"));
      if (r.hol) parts.unshift("🏖️ " + t("hol.vacRoutine"));
      return `<li><button class="rt ${r.off ? "off" : ""}" ${r.habit ? `data-act="holEdit" data-p="${hp.id}"` : `data-act="editRoutine"`} data-id="${r.id}">
      <span class="rt-emo" aria-hidden="true">${esc(r.emoji)}</span>
      <span class="rt-txt"><b>${esc(r.title)}</b><small>${parts.join(t("sep"))}</small></span>
      <span class="rt-stars">${fmtNum(r.stars)} ⭐</span></button></li>`; }).join("")}</ul>`;
  }).join("");
  return chips() + banner + `<div class="actions"><button class="btn" data-act="routineTemplates">${t("routine.chooseTpl")}</button><button class="btn ghost" data-act="newRoutine">${vac ? t("hol.newRoutine") : t("routine.create")}</button></div>`
    + (groups || `<p class="empty">${t("routine.none", { name: esc(c.name) })}</p>`) + extra;   // exceptionnelles en cours visibles aussi en vue vacances
}
function pRewards() {
  const c = curChild(), v = viewFor(c), r = rhythmOf(c.id), td = todayISO();
  const list = S.rewards.filter(w => (!w.child_id || w.child_id === c.id) && (!w.event_date || w.event_date >= td));
  const hist = [
    ...S.redemptions.filter(z => z.child_id === c.id).map(z => ({ ...z, kind: "gift" })),

  ].sort((a, b) => a.created_at < b.created_at ? 1 : -1).slice(0, 20);
  const drift = c.price_rhythm && Math.abs(r - c.price_rhythm) / c.price_rhythm > .2;
  const P = isParent(), rnd = x => fmtNum(Math.round(x * 10) / 10);
  const row = w => { const cost = costFor(w, c.id); return `<li class="gift"><button class="gift-main" ${P ? `data-act="editReward" data-id="${w.id}"` : "disabled"}><span class="g-emo" aria-hidden="true">${esc(w.emoji)}</span><span><b>${esc(w.title)}</b><small>${w.child_id ? t("reward.for", { name: esc(c.name) }) : t("reward.forAll")}${t("sep")}${daysLabelFor(cost, c.id)}</small>${w.event_date || w.place ? `<small class="when">${w.event_date ? "📅 " + fmtLong(w.event_date) : ""}${w.event_date && w.place ? t("sep") : ""}${w.place ? "📍 " + esc(w.place) : ""}</small>` : ""}</span></button>
      <button class="btn sm ${v.balance >= cost ? "" : "ghost"}" data-act="pRedeem" data-id="${w.id}" ${v.balance >= cost ? "" : "disabled"} aria-label="${t("reward.exchangeN", { n: cost })}">${fmtNum(cost)} ⭐</button></li>`; };
  const groups = TIERS().map(([k, l, d]) => { const ws = list.filter(w => (w.tier || "moment") === k).sort((a, b) => costFor(a, c.id) - costFor(b, c.id)); return ws.length ? `<h3 class="tier-h">${l}<small>${d}</small></h3><ul class="glist">${ws.map(row).join("")}</ul>` : ""; }).join("");
  return chips() + `<div class="balance"><span class="big">⭐ ${fmtNum(v.balance)}</span><span>${t("reward.balanceFor", { n: v.balance, name: esc(c.name) })}</span>${v.pendingStars ? `<span class="muted">${t("reward.pending", { n: v.pendingStars })}</span>` : ""}<span class="muted">${t("reward.rhythm", { n: rnd(r) })}</span></div>
    ${drift && P ? `<div class="banner"><p>${t("reward.drift", { name: esc(c.name), old: rnd(c.price_rhythm), now: rnd(r) })}</p><button class="btn sm" data-act="repriceChild">${t("reward.reprice")}</button></div>` : ""}
    ${P ? `<div class="actions"><button class="btn" data-act="rewardTemplates">${t("reward.chooseTpl")}</button><button class="btn ghost" data-act="newReward">${t("reward.create")}</button></div>` : ""}
    ${groups || `<p class="empty">${t("reward.none", { name: esc(c.name) })}</p>`}
    ${hist.length ? `<h3 class="grp">${t("reward.history")}</h3><ul class="hist">${hist.map(z => z.kind === "gift"
      ? `<li><span>${esc(z.emoji)} ${esc(z.title)}</span><span class="muted">${fmtDate(z.created_at)}</span><span class="num">−${fmtNum(z.cost)} ⭐</span><span class="muted">${t("common.by", { who: z.created_by ? esc(memberLabel(z.created_by)) : esc(c.name) })}</span>${P ? `<button class="link" data-act="cancelRedeem" data-id="${z.id}">${t("btn.cancel")}</button>` : ""}</li>`
      : `<li>${brokenStar(20)}<span>${esc(z.title)}</span><span class="muted">${fmtDate(z.created_at)}</span><span class="num">−${fmtNum(z.stars)} ⭐</span><span class="muted">${t("common.by", { who: esc(memberLabel(z.created_by)) })}</span>${P ? `<button class="link" data-act="cancelPenalty" data-id="${z.id}">${t("btn.cancel")}</button>` : ""}</li>`).join("")}</ul>` : ""}`;
}
function pFamily() {
  const kids = S.children.map(c => {
    const devs = S.devices.filter(d => d.child_id === c.id);
    const gn = gardenNow(S.gardens[c.id]);
    return `<div class="krow">${gn ? stageSVG(gn.stage, gn.species, c.color) : plantSVG(0, c.color)}<div class="grow"><b>${esc(c.emoji)} ${esc(c.name)}</b>
      ${devs.map(d => `<div class="dev">📱 ${esc(d.label || t("family.hisPhone"))}${t("sep")}${t("family.since", { date: fmtDate(d.created_at) })} ${isParent() ? `<button class="link" data-act="revokeDevice" data-id="${d.id}">${t("family.disconnect")}</button>` : ""}</div>`).join("")}</div>
      ${isParent() ? `<div class="btns"><button class="btn sm ghost" data-act="editChild" data-id="${c.id}">${t("btn.edit")}</button><button class="btn sm ghost" data-act="deviceCode" data-id="${c.id}">${t("family.connectDevice")}</button><button class="btn sm ghost" data-act="childHere" data-id="${c.id}">${t("family.childHere")}</button></div>` : ""}</div>`;
  }).join("");
  const pushOn = store.get("pushOn", false), times = store.get("pushTimes", ["07:30", "18:30"]);
  const P = isParent(), me = S.session?.user.id;
  const members = S.members.map(m => `<div class="krow"><div class="grow"><b>${esc(m.relation || m.display_name || t("role.parent"))}</b>${m.user_id === me ? " " + t("family.you") : ""}
      <div class="dev">${m.relation && m.display_name ? esc(m.display_name) + t("sep") : ""}${m.role === "helper" ? t("role.helper") : t("role.parent")}</div></div>
      ${P || m.user_id === me ? `<div class="btns"><button class="btn sm ghost" data-act="editMember" data-id="${m.user_id}">${t("btn.edit")}</button></div>` : ""}</div>`).join("");
  return `<section class="sec"><h2>${t("family.children")}</h2>${kids || `<p class="muted">${t("family.noChild")}</p>`}${P ? `<div class="actions"><button class="btn" data-act="newChild">${t("child.add")}${S.children.length >= 1 ? ptag() : ""}</button></div>` : ""}</section>
    <section class="sec"><h2>${t("family.members")}</h2>${members}
      ${P ? `<p class="muted small">${t("family.rolesHelp")}</p><div class="actions"><button class="btn ghost" data-act="invite">${t("family.invite")}</button></div>` : ""}</section>
    <section class="sec"><h2>${t("week.title")}</h2><p class="muted">${esc(weekSummary(WEEK))}</p><p class="muted small">${t("week.help")}</p>${P ? `<div class="actions"><button class="btn ghost" data-act="editWeek" data-mode="family">${t("btn.edit")}</button></div>` : ""}</section>
    ${P ? `<section class="sec"><h2>${t("pause.title")}</h2><p class="muted">${t("pause.help")}</p>
      ${S.pauses.length ? `<ul class="hist">${S.pauses.map(p => { const k = S.children.find(c => c.id === p.child_id); return `<li><span>${esc(k ? k.emoji + " " + k.name : "")}${t("sep")}${esc(p.reason || t("pause.default"))}</span><span class="muted">${t("pause.range", { from: fmtDate(p.start_day), to: fmtDate(p.end_day) })}</span><button class="link" data-act="delPause" data-id="${p.id}">${t("btn.delete")}</button></li>`; }).join("")}</ul>` : ""}
      <div class="actions"><button class="btn ghost" data-act="newPause">${t("pause.new")}</button></div></section>
    ${holidaySection()}
    <section class="sec"><h2>${t("validate.section")}</h2><p class="muted">${t("validate.sectionHelp")}</p>
      <label class="check"><input type="checkbox" data-act="toggleAuto" ${S.autoValidate ? "checked" : ""}> ${t("validate.autoLabel")}</label></section>` : ""}
    <section class="sec"><h2>${t("push.title")}</h2><p class="muted">${t("push.parentHelp")}</p>
      <div class="f two"><label>${t("push.morning")}<input type="time" id="t1" value="${esc(times[0] || "")}"></label><label>${t("push.evening")}<input type="time" id="t2" value="${esc(times[1] || "")}"></label></div>
      <div class="actions"><button class="btn" data-act="pushParent">${pushOn ? t("push.update") : t("push.enable")}</button>${pushOn ? `<button class="btn ghost" data-act="pushOff">${t("btn.disable")}</button>` : ""}</div></section>
    <section class="sec"><h2>${t("print.title")}</h2><p class="muted">${t("print.help")}</p><div class="actions"><button class="btn ghost" data-act="printPlan">${t("print.btn")}</button></div></section>
    <section class="sec"><h2>${t("pin.title")}</h2><p class="muted">${t("pin.help")}</p><div class="actions"><button class="btn ghost" data-act="setPin">${store.get("pin") ? t("pin.change") : t("pin.create")}</button></div></section>
    <section class="sec"><h2>${t("backup.title")}</h2><p class="muted">${t("backup.help")}</p><div class="actions"><button class="btn ghost" data-act="exportData">${t("backup.btn")}</button></div></section>
    ${P ? planSection() : ""}
    <section class="sec"><h2>${t("account.title")}</h2><p class="muted">${esc(S.session?.user.email || "")}</p><div class="actions">${installBtn()}${P ? `<button class="btn ghost" data-act="renameFamily">${t("account.rename")}</button>` : ""}<button class="btn danger ghost" data-act="logout">${t("btn.logout")}</button></div></section>`;
}

function planSection() {
  const plan = S.plan || "founder";
  return `<section class="sec"><h2>${t("premium.myPlan")}</h2><p><b>${t("premium.plan." + plan)}</b></p><p class="muted">${t("premium.planHelp." + plan)}</p>
    ${plan === "free" ? `<div class="actions"><a class="btn" href="${premiumHref("plan")}">${t("premium.see")}</a></div>` : ""}</section>`;
}
// Rappel discret, hors action : au plus une fois par semaine, parent d'une famille gratuite
function nudge() {
  if (isPremium() || !isParent() || Date.now() - store.get("nudgeAt", 0) < 7 * 864e5) return "";
  const td = todayISO(), md = td.slice(5), yr = gardenYearOfISO(td);
  const flowers = S.children.reduce((a, c) => a + ((S.gardens[c.id] && S.gardens[c.id].flowers) || []).length, 0);
  let k = null;
  if (md >= "09-23" && md <= "10-07" && !store.get("nudge:year" + yr) && flowers) k = "year" + yr;
  else if (flowers && !store.get("nudge:flower")) k = "flower";
  if (!k) return "";
  const key = k === "flower" ? "flower" : "year";
  return `<aside class="banner nudge"><p>${t("premium.nudge." + key)}</p><div class="btns"><button class="btn sm ghost" data-act="dismissNudge" data-k="${k}">${t("premium.later")}</button><a class="btn sm" href="${premiumHref("nudge-" + key)}" data-act="dismissNudge" data-k="${k}">${t("premium.see")}</a></div></aside>`;
}
function pMalus() {
  if (!isPremium()) return `<section class="card center"><div class="up-emo" aria-hidden="true">${brokenStar(40)}</div><h1>${t("premium.malus.title")}</h1><p>${t("premium.malus.text")}</p><button class="btn" data-act="upsell" data-key="malus">${t("premium.discover")}</button></section>`;
  const P = isParent(), f = S.mfilter || "all", now = Date.now();
  const chipsM = `<div class="chips" role="tablist">${[["all", t("malus.all"), "#7A6A5F"], ...S.children.map(c => [c.id, c.emoji + " " + c.name, c.color])].map(([k, l, col]) =>
    `<button role="tab" aria-selected="${f === k}" class="chip ${f === k ? "on" : ""}" style="--c:${esc(col)}" data-act="mFilter" data-id="${k}">${esc(l)}</button>`).join("")}</div>`;
  const list = S.pevents.filter(e => f === "all" || e.child_id === f).sort((a, b) => a.created_at < b.created_at ? 1 : -1);
  const sum = d => list.filter(e => now - new Date(e.created_at) < d * 864e5).reduce((a, e) => a + e.stars, 0);
  const dayLbl = k => { const td = todayISO(); return k === td ? t("day.today") : k === addDays(td, -1) ? t("day.yesterday") : fmtLong(k); };
  const byDay = []; list.forEach(e => { const k = isoInTz(new Date(e.created_at)); const g = byDay.find(x => x.k === k); g ? g.items.push(e) : byDay.push({ k, items: [e] }); });
  const item = e => { const k = S.children.find(c => c.id === e.child_id) || { name: "", emoji: "" };
    return `<li>${brokenStar(24)}<span class="grow"><b>${esc(e.emoji)} ${esc(e.title)}</b><small>${f === "all" ? esc(k.emoji + " " + k.name) + t("sep") : ""}${t("malus.byAt", { who: esc(memberLabel(e.created_by)), time: fmtTime(e.created_at) })}</small></span>
      <span class="num">−${fmtNum(e.stars)} ⭐</span>${P ? `<button class="vbtn no" data-act="cancelPenalty" data-id="${e.id}" aria-label="${t("malus.cancelAria")}">↺</button>` : ""}</li>`; };
  return chipsM + `<div class="balance"><span class="big">${brokenStar(28)} ${fmtNum(sum(7))}</span><span>${t("malus.week", { n: sum(7) })}</span><span class="muted">${t("malus.month", { n: sum(30), total: list.length })}</span></div>
    ${P ? `<div class="actions"><button class="btn danger" data-act="breakStar">${brokenStar(18)} ${t("malus.break")}</button><button class="btn ghost" data-act="penaltyCatalog">${t("malus.catalog")}</button></div>` : ""}
    ${byDay.length ? byDay.map(g => `<h3 class="grp">${dayLbl(g.k)}</h3><ul class="vlist">${g.items.map(item).join("")}</ul>`).join("")
      : `<p class="empty">${f === "all" ? t("malus.none") : t("malus.noneChild")}</p>`}`;
}
