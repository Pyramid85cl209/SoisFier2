"use strict";
/* SoisFier : Actions : routines exceptionnelles, malus, routines, récompenses, enfants */
// Routines exceptionnelles
A.newOneoff = el => {
  if (needPremium("oneoff")) return;
  const c = S.children.find(k => k.id === el.dataset.child) || curChild(); S.oneoffChild = c.id;
  const saved = S.oneoffTpl, have = new Set(saved.map(x => x.title.toLowerCase()));
  const base = TPL_X.map((x, i) => ({ ...x, i })).filter(x => !have.has(x.t.toLowerCase()));
  openSheet(`<h2>${t("oneoff.for", { name: esc(c.name) })}</h2>
    ${saved.length ? `<h3 class="grp">${t("oneoff.myTpl")}</h3><ul class="tpl">${saved.map(x => `<li><button class="pen" data-act="oneoffFrom" data-tpl="${x.id}"><span>${esc(x.emoji)} ${esc(x.title)}</span><span>${fmtNum(x.stars)} ⭐</span></button></li>`).join("")}</ul>` : ""}
    ${base.length ? `<h3 class="grp">${t("common.suggestions")}</h3><ul class="tpl">${base.map(x => `<li><button class="pen" data-act="oneoffFrom" data-base="${x.i}"><span>${x.e} ${esc(x.t)}</span><span>${fmtNum(x.s)} ⭐</span></button></li>`).join("")}</ul>` : ""}
    <div class="sheet-actions"><button class="btn" data-act="oneoffFrom">${t("oneoff.createNew")}</button></div>`);
};
A.oneoffFrom = el => {
  const tp = el.dataset.tpl ? S.oneoffTpl.find(x => x.id === el.dataset.tpl) : null, b = el.dataset.base != null ? TPL_X[+el.dataset.base] : null;
  const r = tp ? { title: tp.title, emoji: tp.emoji, stars: tp.stars, moment: tp.moment, is_bonus: tp.is_bonus } : b ? { title: b.t, emoji: b.e, stars: b.s, moment: b.m, is_bonus: true } : { title: "", emoji: "⭐", stars: 1, moment: "journee", is_bonus: true };
  const td = todayISO(), c = S.children.find(k => k.id === S.oneoffChild);
  S.form = { moment: r.moment, when: "le", type: r.is_bonus ? "bonus" : "oblig", tpl: tp ? tp.id : null };
  const seg = (group, opts, cur) => `<div class="seg" role="radiogroup">${opts.map(([k, l]) => `<button type="button" role="radio" aria-checked="${cur === k}" class="${cur === k ? "on" : ""}" data-act="seg" data-group="${group}" data-v="${k}">${l}</button>`).join("")}</div>`;
  openSheet(`<h2>${t("oneoff.for", { name: esc(c.name) })}</h2>
    <label class="f">${t("form.name")}<input id="x-title" maxlength="60" value="${esc(r.title)}" placeholder="${t("tpl.x.suitcase")}"></label>
    ${iconField("x-emoji", r.emoji, EMO_R)}
    <div class="f"><span>${t("oneoff.when")}</span>${seg("when", [["le", t("oneoff.on")], ["avant", t("oneoff.before")]], "le")}<input id="x-date" type="date" min="${td}" value="${td}" style="margin-top:6px"></div>
    <div class="f"><span>${t("oneoff.type")}</span>${seg("type", [["bonus", t("oneoff.bonus")], ["oblig", t("oneoff.mandatory")]], S.form.type)}<small class="muted" style="font-weight:400">${t("oneoff.typeHelp")}</small></div>
    <div class="f two"><label>${t("form.stars")}<select id="x-stars">${[1, 2, 3, 4, 5].map(n => `<option value="${n}" ${n === r.stars ? "selected" : ""}>${fmtNum(n)}</option>`).join("")}</select></label>
      <label>${t("form.moment")}<select id="x-moment">${MOMENTS().map(([k, , l]) => `<option value="${k}" ${k === r.moment ? "selected" : ""}>${l}</option>`).join("")}</select></label></div>
    ${tp ? "" : `<label class="check"><input type="checkbox" id="x-keep"> ${t("oneoff.keepTpl")}</label>`}
    <div class="sheet-actions"><button class="btn" data-act="saveOneoff">${t("btn.add")}</button></div>`);
};
A.saveOneoff = async () => {
  const title = $("#x-title").value.trim(), date = $("#x-date").value, td = todayISO(); if (!title) return toast(t("routine.needName"), true);
  if (!date || date < td) return toast(t("oneoff.needDate"), true);
  const row = { family_id: S.family.id, child_id: S.oneoffChild, kind: "oneoff", title, emoji: $("#x-emoji").value.trim() || "⭐", stars: +$("#x-stars").value,
    moment: $("#x-moment").value, is_bonus: S.form.type !== "oblig", start_day: S.form.when === "avant" ? td : date, end_day: date, days: [], position: 0 };
  const { error } = await sb.from("routines").insert(row); if (error) throw error;
  if (S.form.tpl) { const tp = S.oneoffTpl.find(x => x.id === S.form.tpl); await sb.from("oneoff_templates").update({ use_count: (tp.use_count || 0) + 1, last_used: new Date().toISOString() }).eq("id", tp.id); }
  else if ($("#x-keep") && $("#x-keep").checked) await sb.from("oneoff_templates").upsert({ family_id: S.family.id, title, emoji: row.emoji, stars: row.stars, moment: row.moment, is_bonus: row.is_bonus }, { onConflict: "family_id,title" });
  closeSheet(); await reloadParent(t("oneoff.added"), ["r", "ot"]);
};
A.delOneoff = async el => {
  if (!await confirmSheet(t("oneoff.delTitle"), t("oneoff.delText"), t("btn.delete"), true)) return;
  const { error } = await sb.from("routines").update({ active: false }).eq("id", el.dataset.id); if (error) throw error;
  await reloadParent(t("common.deletedF"), ["r"]);
};
A.manageOneoffTpl = () => needPremium("oneoff") || openSheet(`<h2>${t("oneoff.tplTitle")}</h2><p class="muted">${t("oneoff.tplHelp")}</p>
  ${S.oneoffTpl.length ? `<ul class="hist">${S.oneoffTpl.map(x => `<li><span>${esc(x.emoji)} ${esc(x.title)}</span><span class="muted">${t("oneoff.times", { n: x.use_count })}</span><button class="link" data-act="delOneoffTpl" data-id="${x.id}">${t("btn.delete")}</button></li>`).join("")}</ul>` : `<p class="empty">${t("oneoff.noTpl")}</p>`}
  <div class="sheet-actions"><button class="btn" data-act="closeSheet">${t("btn.close")}</button></div>`);
A.delOneoffTpl = async el => { const { error } = await sb.from("oneoff_templates").delete().eq("id", el.dataset.id); if (error) throw error; await reloadParent(t("oneoff.tplDeleted"), ["ot"]); A.manageOneoffTpl(); };

// Étoiles cassées
A.mFilter = el => { S.mfilter = el.dataset.id; if (el.dataset.id !== "all") S.currentChild = el.dataset.id; render(); };
A.pickPenChild = el => { S.currentChild = el.value; A.breakStar(); };
A.breakStar = () => {
  if (needPremium("malus")) return;
  if (S.tab === "malus" && S.mfilter && S.mfilter !== "all") S.currentChild = S.mfilter;
  const c = curChild(), v = viewFor(c);
  const pick = S.children.length > 1 ? `<label class="f">${t("malus.child")}<select id="pen-child" onchange="A.pickPenChild(this)">${S.children.map(k => `<option value="${k.id}" ${k.id === c.id ? "selected" : ""}>${esc(k.emoji + " " + k.name)}</option>`).join("")}</select></label>` : "";
  if (v.balance <= 0 && !pick) return toast(t("malus.nothingToBreak", { name: c.name }), true);
  const n13 = `${[1, 2, 3].map(n => `<option value="${n}">${fmtNum(n)}</option>`).join("")}`;
  openSheet(`<h2>${brokenStar(26)} ${t("malus.break")}</h2>${pick}
    <p class="muted">${t("malus.breakHelp", { name: esc(c.name), n: v.balance })}</p>
    ${S.penalties.length ? `<ul class="tpl">${S.penalties.map(p => `<li><button class="pen" data-act="applyPenalty" data-id="${p.id}"><span>${esc(p.emoji)} ${esc(p.title)}</span><span aria-label="${t("kid.starsAria", { n: p.stars })}">${brokenStar(18).repeat(p.stars)}</span></button></li>`).join("")}</ul>`
      : `<p class="empty">${t("malus.noPreset")}</p>`}
    <h3 class="grp">${t("malus.otherReason")}</h3>
    <div class="f two"><label>${t("malus.reason")}<input id="pen-title" maxlength="60" placeholder="${t("malus.reasonPlaceholder")}"></label><label>${t("form.stars")}<select id="pen-stars">${n13}</select></label></div>
    <div class="sheet-actions"><button class="btn ghost" data-act="penaltyCatalog">${t("malus.manage")}</button><button class="btn danger" data-act="applyPenalty">${t("malus.breakBtn")}</button></div>`);
};
A.applyPenalty = async el => {
  const c = curChild(), pid = el.dataset.id || null;
  let title = null, stars = null;
  if (!pid) { title = $("#pen-title").value.trim(); stars = +$("#pen-stars").value; if (!title) return toast(t("malus.needReason"), true); }
  const pe = pid && S.penalties.find(p => p.id === pid);
  const n = Math.min(pe ? pe.stars : stars, viewFor(c).balance);   // le solde ne passe jamais sous zéro (même règle que le serveur)
  closeSheet();
  return instant(() => { S.pevents = [{ id: "tmp:" + Date.now(), tmp: true, child_id: c.id, title: pe ? pe.title : title, emoji: pe ? pe.emoji : "💔", stars: n, created_at: new Date().toISOString(), created_by: S.session?.user.id }, ...S.pevents]; bumpStats(c.id, { broken: n, broken_count: 1 }); },
    () => sb.rpc("apply_penalty", { p_child: c.id, p_penalty: pid, p_title: title, p_emoji: null, p_stars: stars }), ["pv", "s"], t("malus.broken", { n, name: c.name }));
};
A.cancelPenalty = async el => {
  const e = S.pevents.find(x => x.id === el.dataset.id); if (!e || e.tmp) return;
  if (!await confirmSheet(t("malus.cancelTitle"), t("common.starsReturned"), t("malus.cancelBtn"))) return;
  return instant(() => { S.pevents = S.pevents.filter(x => x !== e); bumpStats(e.child_id, { broken: -e.stars, broken_count: -1 }); },
    () => sb.from("penalty_events").delete().eq("id", e.id), ["pv", "s"], t("malus.cancelled"));
};
A.penaltyCatalog = () => {
  if (needPremium("malus")) return;
  const have = new Set(S.penalties.map(p => p.title.toLowerCase()));
  const sugg = TPL_P.map((x, i) => ({ ...x, i })).filter(x => !have.has(x.t.toLowerCase()));
  openSheet(`<h2>${t("malus.catalog")}</h2><p class="muted">${t("malus.catalogHelp")}</p>
    ${S.penalties.length ? `<ul class="hist">${S.penalties.map(p => `<li><span>${esc(p.emoji)} ${esc(p.title)}</span><span>${fmtNum(p.stars)} ⭐</span><button class="link" data-act="delPenalty" data-id="${p.id}">${t("btn.delete")}</button></li>`).join("")}</ul>` : ""}
    ${sugg.length ? `<h3 class="grp">${t("common.suggestions")}</h3><ul class="tpl">${sugg.map(x => `<li><label><input type="checkbox" value="${x.i}"><span>${x.e} ${esc(x.t)} (${fmtNum(x.s)} ⭐)</span></label></li>`).join("")}</ul>` : ""}
    <h3 class="grp">${t("malus.createTitle")}</h3>
    <div class="f two"><label>${t("malus.reason")}<input id="np-title" maxlength="60"></label><label>${t("form.stars")}<select id="np-stars">${[1, 2, 3].map(n => `<option value="${n}">${fmtNum(n)}</option>`).join("")}</select></label></div>
    <div class="sheet-actions"><button class="btn ghost" data-act="breakStar">${t("btn.back")}</button><button class="btn" data-act="savePenalties">${t("btn.save")}</button></div>`);
};
A.savePenalties = async () => {
  const rows = $$(".tpl input:checked", dlg).map(i => TPL_P[+i.value]).map(x => ({ family_id: S.family.id, title: x.t, emoji: x.e, stars: x.s }));
  const title = $("#np-title").value.trim();
  if (title) rows.push({ family_id: S.family.id, title, emoji: "💔", stars: +$("#np-stars").value });
  if (!rows.length) return toast(t("malus.needOne"), true);
  const { error } = await sb.from("penalties").insert(rows); if (error) throw error;
  await reloadParent(t("malus.added", { n: rows.length }), ["pe"]); A.penaltyCatalog();
};
A.delPenalty = async el => {
  const { error } = await sb.from("penalties").update({ active: false }).eq("id", el.dataset.id); if (error) throw error;
  await reloadParent(t("malus.deleted"), ["pe"]); A.penaltyCatalog();
};

// Routines
A.newRoutine = () => routineForm(null);
A.editRoutine = el => routineForm(S.routines.find(r => r.id === el.dataset.id));
A.pickEmoji = el => { const t = $("#" + (el.dataset.target || "f-emoji")); if (t) t.value = el.dataset.e; $$(".emo-box .emo", dlg).forEach(b => b.classList.toggle("on", b === el)); };
A.seg = el => { S.form[el.dataset.group] = el.dataset.v; $$("button", el.parentElement).forEach(b => { const on = b === el; b.classList.toggle("on", on); b.setAttribute("aria-checked", on); }); };
const syncDays = () => $$(".day", dlg).forEach(b => { const on = S.form.days.includes(+b.dataset.v); b.classList.toggle("on", on); b.setAttribute("aria-pressed", on); });
A.toggleDay = el => { const v = +el.dataset.v; S.form.days = S.form.days.includes(v) ? S.form.days.filter(d => d !== v) : [...S.form.days, v]; syncDays(); };
A.daysPreset = el => { S.form.days = { all: [1, 2, 3, 4, 5, 6, 7], week: workDays(), we: weekendDays() }[el.dataset.v]; syncDays(); };
A.saveRoutine = async el => {
  const title = $("#f-title").value.trim();
  if (!title) return toast(t("routine.needName"), true);
  if (!S.form.days.length) return toast(t("routine.needDay"), true);
  const row = { title, emoji: $("#f-emoji").value.trim() || "⭐", moment: S.form.moment, days: [...S.form.days].sort((a, b) => a - b),
    stars: +$("#f-stars").value, place: $("#f-place").value || null, timer_minutes: $("#f-timer").value ? +$("#f-timer").value : null, is_bonus: $("#f-bonus").checked };
  const id = el.dataset.id;
  const { error } = id ? await sb.from("routines").update(row).eq("id", id)
    : await sb.from("routines").insert({ ...row, family_id: S.family.id, child_id: S.currentChild, holiday_period_id: S.hctx || null, position: S.routines.filter(r => r.child_id === S.currentChild).length });
  if (error) throw error;
  await afterHolidayEdit(id ? t("routine.saved") : t("routine.added"), !!(S.hctx || (id && isHolidayR(S.routines.find(r => r.id === id) || {}))));
};
A.delRoutine = async el => {
  if (!await confirmSheet(t("routine.delTitle"), t("routine.delText"), t("btn.delete"), true)) return;
  const { error } = await sb.from("routines").update({ active: false }).eq("id", el.dataset.id); if (error) throw error;
  await reloadParent(t("routine.deletedToast"), ["r"]);
};
A.routineTemplates = () => {
  const c = curChild(); const have = new Set(S.routines.filter(r => r.child_id === c.id && (!isHolidayR(r) || r.holiday_period_id === S.hctx)).map(r => r.title.toLowerCase()));
  openSheet(`<h2>${S.hctx ? "🏖️ " : ""}${t("routine.tplFor", { name: esc(c.name) })}</h2>${S.hctx ? `<p class="muted">${t("hol.tplHelp")}</p>` : ""}${MOMENTS().map(([k, l, , e]) => {
    const list = TPL_R.map((x, i) => ({ ...x, i })).filter(x => x.m === k); if (!list.length) return "";
    return `<h3 class="grp">${e} ${l}</h3><ul class="tpl">${list.map(x => { const had = have.has(x.t.toLowerCase()); return `<li><label class="${had ? "had" : ""}"><input type="checkbox" value="${x.i}" ${had ? "disabled" : ""}><span>${x.e} ${esc(x.t)}${x.b ? " " + t("routine.bonusTag") : ""}${x.d ? t("sep") + lower(t("days.week")) : ""}${had ? t("sep") + t("common.alreadyAdded") : ""}</span></label></li>`; }).join("")}</ul>`;
  }).join("")}<div class="sheet-actions"><button class="btn" data-act="addRoutineTpl">${t("common.addSelection")}</button></div>`);
};
A.addRoutineTpl = async () => {
  const picks = $$(".tpl input:checked", dlg).map(i => TPL_R[+i.value]);
  if (!picks.length) return toast(t("routine.needOne"), true);
  const base = S.routines.filter(r => r.child_id === S.currentChild).length;
  const rows = picks.map((x, i) => ({ family_id: S.family.id, child_id: S.currentChild, title: x.t, emoji: x.e, moment: x.m, place: x.p != null ? PLACES()[x.p] : null,
    stars: x.s || 1, days: tplDays(x.d), is_bonus: !!x.b, timer_minutes: x.tm || null, position: base + i, holiday_period_id: S.hctx || null }));
  const { error } = await sb.from("routines").insert(rows); if (error) throw error;
  await afterHolidayEdit(t("routine.addedN", { n: rows.length }), !!S.hctx);
};

// Récompenses
A.newReward = () => rewardForm(null);
A.editReward = el => rewardForm(S.rewards.find(w => w.id === el.dataset.id));
A.saveReward = async el => {
  const title = $("#w-title").value.trim(), fixed = $("#w-fixed").checked, days = parseInt($("#w-days").value, 10), cost = parseInt($("#w-cost").value, 10);
  if (!title) return toast(t("reward.needName"), true);
  if (fixed && !(cost >= 1 && cost <= 5000)) return toast(t("reward.badPrice"), true);
  if (!fixed && !(days >= 1 && days <= 365)) return toast(t("reward.badDays"), true);
  const who = $("#w-for").value || null, ids = who ? [who] : S.children.map(k => k.id);
  const costs = fixed ? {} : pricesFor(days, ids);
  const row = { title, emoji: $("#w-emoji").value.trim() || "🎁", tier: $("#w-tier").value, child_id: who, duration_days: fixed ? null : days, costs,
    cost: fixed ? cost : (who ? costs[who] : roundPrice(days * 5)), event_date: $("#w-date").value || null, place: $("#w-place").value.trim() || null };
  if (!fixed) await markPriced(ids);
  const id = el.dataset.id;
  const { error } = id ? await sb.from("rewards").update(row).eq("id", id) : await sb.from("rewards").insert({ ...row, family_id: S.family.id });
  if (error) throw error;
  closeSheet(); await reloadParent(id ? t("reward.saved") : t("reward.added"), ["w", "c"]);
};
A.delReward = async el => {
  if (!await confirmSheet(t("reward.delTitle"), t("reward.delText"), t("btn.delete"), true)) return;
  const { error } = await sb.from("rewards").update({ active: false }).eq("id", el.dataset.id); if (error) throw error;
  await reloadParent(t("reward.deleted"), ["w"]);
};
A.rewardTemplates = () => {
  const have = new Set(S.rewards.map(w => w.title.toLowerCase())), c = curChild();
  openSheet(`<h2>${t("reward.tplTitle")}</h2><p class="muted">${t("reward.tplHelp", { name: esc(c.name), n: fmtNum(Math.round(rhythmOf(c.id) * 10) / 10) })}</p>
    ${TIERS().filter(([k]) => k !== "event").map(([k, l, d]) => `<h3 class="tier-h">${l}<small>${d}</small></h3><ul class="tpl">${TPL_W.map((x, i) => ({ ...x, i })).filter(x => x.tier === k).map(x => { const had = have.has(x.t.toLowerCase()); return `<li><label class="${had ? "had" : ""}"><input type="checkbox" value="${x.i}" ${had ? "disabled" : ""}><span>${x.e} ${esc(x.t)} ${t("reward.tplPrice", { n: roundPrice(x.d * rhythmOf(c.id)), name: esc(c.name) })}${had ? t("sep") + t("common.alreadyAdded") : ""}</span></label></li>`; }).join("")}</ul>`).join("")}
    <h3 class="tier-h">${t("tier.event.name")}<small>${t("tier.event.hint")}</small></h3><p class="muted">${t("reward.eventHelp")}</p>
    <div class="sheet-actions"><button class="btn ghost" data-act="newEvent">${t("reward.createEvent")}</button><button class="btn" data-act="addRewardTpl">${t("common.addSelection")}</button></div>`);
};
A.newEvent = () => rewardForm(null, { tier: "event", emoji: "🎪", title: t("reward.eventDefault"), duration_days: 30 });
A.addRewardTpl = async () => {
  const picks = $$(".tpl input:checked", dlg).map(i => TPL_W[+i.value]).sort((a, b) => TIER_RANK[a.tier] - TIER_RANK[b.tier] || a.d - b.d);
  if (!picks.length) return toast(t("reward.needOne"), true);
  const ids = S.children.map(k => k.id);
  // Les niveaux restent dans l'ordre : un niveau supérieur ne peut pas coûter autant qu'un niveau inférieur
  const maxBelow = {}; ids.forEach(id => maxBelow[id] = {});
  S.rewards.filter(w => w.duration_days).forEach(w => ids.forEach(id => { const r = TIER_RANK[w.tier || "moment"], v = costFor(w, id); maxBelow[id][r] = Math.max(maxBelow[id][r] || 0, v); }));
  const rows = picks.map(x => { const costs = pricesFor(x.d, ids);
    ids.forEach(id => { const r = TIER_RANK[x.tier]; const lower = Math.max(0, ...Object.entries(maxBelow[id]).filter(([k]) => +k < r).map(([, v]) => v));
      while (costs[id] <= lower) costs[id] += stepOf(costs[id]); maxBelow[id][r] = Math.max(maxBelow[id][r] || 0, costs[id]); });
    return { family_id: S.family.id, title: x.t, emoji: x.e, tier: x.tier, duration_days: x.d, costs, cost: roundPrice(x.d * 5) }; });
  const { error } = await sb.from("rewards").insert(rows); if (error) throw error;
  await markPriced(ids); closeSheet(); await reloadParent(t("reward.addedN", { n: rows.length }), ["w", "c"]);
};
A.pRedeem = async el => {
  const w = S.rewards.find(x => x.id === el.dataset.id), c = curChild(), cost = costFor(w, c.id);
  if (!await confirmSheet(t("reward.exchangeTitle"), t("reward.exchangeText", { n: cost, name: c.name, title: w.title }), t("reward.exchange"))) return;
  // Identifiant créé dans l'app : la ligne d'historique est annulable tout de suite
  const id = newId(), row = { family_id: S.family.id, child_id: c.id, reward_id: w.id, title: w.title, emoji: w.emoji, cost, ...(id ? { id } : {}) };
  celebrate(true);
  return instant(() => { S.redemptions = [{ ...row, id: id || "tmp:" + Date.now(), tmp: !id, created_at: new Date().toISOString(), created_by: S.session?.user.id }, ...S.redemptions]; bumpStats(c.id, { spent: cost, redeemed_count: 1 }); },
    () => sb.from("redemptions").insert(row), ["z", "s"], t("reward.exchanged"));
};
A.cancelRedeem = async el => {
  const z = S.redemptions.find(x => x.id === el.dataset.id); if (!z || z.tmp) return;
  if (!await confirmSheet(t("reward.cancelTitle"), t("common.starsReturned"), t("reward.cancelBtn"), true)) return;
  return instant(() => { S.redemptions = S.redemptions.filter(x => x !== z); bumpStats(z.child_id, { spent: -z.cost, redeemed_count: -1 }); },
    () => sb.from("redemptions").delete().eq("id", z.id), ["z", "s"], t("reward.cancelled"));
};

// Enfants
A.newChild = () => { if (S.children.length >= 1 && needPremium("children")) return; childForm(null); };
A.editChild = el => childForm(S.children.find(c => c.id === el.dataset.id));
A.pickColor = el => { S.form.color = el.dataset.v; $$(".sw", dlg).forEach(b => b.classList.toggle("on", b === el)); };
A.saveChild = async el => {
  const name = $("#k-name").value.trim(); if (!name) return toast(t("child.needName"), true);
  const row = { name, emoji: $("#k-emoji").value.trim() || "🧒", color: S.form.color };
  const id = el.dataset.id;
  const res = id ? await sb.from("children").update(row).eq("id", id).select().single()
    : await sb.from("children").insert({ ...row, family_id: S.family.id, position: S.children.length }).select().single();
  if (res.error) throw res.error;
  // Enfant enregistré : affiché tout de suite, prix des récompenses et enfants recalés en arrière-plan
  S.children = id ? S.children.map(k => k.id === id ? { ...k, ...res.data } : k) : [...S.children, res.data];
  S.currentChild = res.data.id; closeSheet();
  if (!id) S.tab = "routines";
  render(); toast(id ? t("common.savedM") : t("child.joined", { name }));
  if (!id) A.routineTemplates();
  refreshParts(["c", "w"]).then(render).catch(() => {});
};
A.delChild = async el => {
  const c = S.children.find(k => k.id === el.dataset.id);
  if (!await confirmSheet(t("child.delTitle", { name: c.name }), t("child.delText"), t("btn.delete"), true)) return;
  await mutate(() => sb.from("children").delete().eq("id", c.id));
  const other = x => x.child_id !== c.id;
  S.children = S.children.filter(k => k.id !== c.id);
  ["routines", "completions", "redemptions", "pevents", "devices", "pauses", "holidays", "hp", "ho"].forEach(k => { if (Array.isArray(S[k])) S[k] = S[k].filter(other); });
  if (S.currentChild === c.id) S.currentChild = S.children[0]?.id || null;
  saveParentCache(); render(); toast(t("common.deletedM"));
  refreshParts(["c", "w", "d"]).then(render).catch(() => {});
};
A.deviceCode = async el => {
  const c = S.children.find(k => k.id === el.dataset.id);
  const { data, error } = await sb.rpc("create_child_code", { p_child: c.id }); if (error) throw error;
  openSheet(`<h2>${t("device.phoneOf", { name: esc(c.name) })}</h2><div class="code" aria-label="${t("device.codeAria", { code: data.split("").join(" ") })}">${esc(data)}</div>
    <p>${t("device.help")}</p>
    <div class="sheet-actions"><button class="btn" data-act="closeSheetReload">${t("btn.done")}</button></div>`);
};
A.closeSheetReload = async () => { closeSheet(); await reloadParent(null, ["d"]); };   // l'appareil relié apparaît
A.revokeDevice = async el => {
  const id = el.dataset.id;
  if (!await confirmSheet(t("device.revokeTitle"), t("device.revokeText"), t("family.disconnect"), true)) return;
  await mutate(() => sb.from("child_devices").delete().eq("id", id));
  S.devices = S.devices.filter(d => d.id !== id); saveParentCache(); render(); toast(t("device.revoked"));
  refreshParts(["d"]).then(render).catch(() => {});
};
A.childHere = async el => {
  if (!await ensurePin()) return;
  const cid = el.dataset.id, map = store.get("sameDevice", {});
  let tok = map[cid];
  if (tok) {   // déjà connecté sur ce téléphone : on réutilise le même appareil
    const chk = await sb.rpc("child_state", { p_token: tok });
    if (chk.error) { if (/Appareil non reconnu|SF:device_unknown/.test(chk.error.message || "")) tok = null; else throw chk.error; }
  }
  if (!tok) {
    const { data: code, error } = await sb.rpc("create_child_code", { p_child: cid }); if (error) throw error;
    const r = await sb.rpc("child_pair", { p_code: code, p_label: t("device.sameLabel", { who: memberLabel(S.session.user.id) }) }); if (r.error) throw r.error;
    tok = r.data.token; map[cid] = tok; store.set("sameDevice", map);
  }
  store.set("childToken", tok); store.set("childFromParent", true); store.del("queue"); store.del("lastEarned"); store.del("seenFlowers");
  S.screen = "child"; S.ctab = "today"; S.cs = null; render(); await loadChild();
};
A.exitChild = async () => {
  const pin = store.get("pin");
  if (pin) {
    const v = await pinSheet(t("kid.parentSpace"), t("pin.enter"));
    if (v === null) return; if (v !== pin) return toast(t("pin.wrong"), true);
  } else {
    const a = 6 + Math.floor(Math.random() * 4), b = 6 + Math.floor(Math.random() * 4);
    const v = await new Promise(res => {
      openSheet(`<h2>${t("kid.parentSpace")}</h2><p>${t("pin.math", { a, b })}</p><label class="f">${t("pin.answer")}<input id="m-in" class="pin" inputmode="numeric" maxlength="3"></label>
        <div class="sheet-actions"><button class="btn ghost" id="m-no">${t("btn.cancel")}</button><button class="btn" id="m-ok">${t("btn.validate")}</button></div>`);
      $("#m-no").onclick = () => { closeSheet(); res(null); };
      $("#m-ok").onclick = () => { const x = $("#m-in").value; closeSheet(); res(x); };
      dlg.addEventListener("close", () => res(null), { once: true });
    });
    if (v === null) return; if (+v !== a * b) return toast(t("pin.wrongAnswer"), true);
  }
  await flushQueue();
  if (store.get("cpushOn")) {
    try { const reg = await navigator.serviceWorker.ready; const sub = await reg.pushManager.getSubscription();
      if (sub) { await sb.rpc("push_unsubscribe", { p_endpoint: sub.endpoint }); await sub.unsubscribe(); } } catch {}
    store.set("pushOn", false);
  }
  ["childToken", "childCache", "queue", "childFromParent", "cpushOn", "lastEarned", "seenFlowers"].forEach(k => store.del(k));
  S.cs = null;
  const { data } = await sb.auth.getSession();
  if (data.session) { S.session = data.session; S.tab = "family"; await enterParent(); } else { S.screen = "auth"; render(); }
};
