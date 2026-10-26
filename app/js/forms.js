"use strict";
/* SoisFier : Impression et formulaires */
/* ================= Impression ================= */
function printPlanning(ids) {
  const td = todayISO(), first = addDays(td, -((dowOf(td) - WEEK.start + 7) % 7)), order = weekOrder();
  const pages = S.children.filter(c => ids.includes(c.id)).map(c => {
    // Semaine imprimée : chaque jour suit le Mode vacances s'il s'applique (routines en pause, statut, jours, étoiles, routines de vacances)
    const dates = order.map((_, i) => addDays(first, i));
    const due = dates.map(d => new Map(dueOn(S.routines, c.id, d).filter(r => !isOneoff(r)).map(r => [r.id, r])));
    const rs = S.routines.filter(r => r.child_id === c.id && !isOneoff(r) && due.some(m => m.has(r.id)));
    const hols = holidaysOf(c.id).filter(p => p.start_day <= dates[6] && p.end_day >= dates[0]);
    const rows = MOMENTS().map(([k, l, , e]) => {
      const list = rs.filter(r => r.moment === k); if (!list.length) return "";
      return `<tr class="grp-row"><td colspan="8">${e} ${l}</td></tr>` + list.map(r => {
        const ef = due.map(m => m.get(r.id)).find(Boolean) || r;   // étoiles et statut du premier jour où elle est due
        return `<tr><td class="n">${isHolidayR(r) ? "🏖️ " : ""}${esc(r.emoji)} ${esc(r.title)} (${fmtNum(ef.stars)} ⭐)${ef.is_bonus ? t("sep") + t("routine.bonus") : ""}</td>${due.map(m => m.has(r.id) ? `<td><span class="circ"></span></td>` : `<td class="off"></td>`).join("")}</tr>`;
      }).join("");
    }).join("");
    const gifts = S.rewards.filter(w => (!w.child_id || w.child_id === c.id) && (!w.event_date || w.event_date >= td));   // sans les événements passés
    return `<section class="pp"><h1>${esc(c.emoji)} ${t("print.weekOf", { name: esc(c.name) })}</h1><p>${t("print.weekStart", { date: parseISO(first).toLocaleDateString(loc(), { day: "numeric", month: "long" }) })}</p>${hols.map(p => `<p>🏖️ ${esc(p.name)}${t("sep")}${holLabel(p)}</p>`).join("")}
      <table><thead><tr><th class="n">${t("print.routine")}</th>${order.map(d => `<th>${t("days.abbr")[d - 1]}</th>`).join("")}</tr></thead><tbody>${rows || `<tr><td colspan="8">${t("print.none")}</td></tr>`}</tbody></table>
      ${gifts.length ? `<div class="gifts"><b>${t("print.myRewards")}</b> ${gifts.map(w => `${esc(w.emoji)} ${esc(w.title)} (${fmtNum(costFor(w, c.id))} ⭐)`).join(t("sep"))}</div>` : ""}</section>`;
  }).join("");
  $("#print").innerHTML = pages; setTimeout(() => window.print(), 50);
}

/* ================= Formulaires ================= */
const iconField = (id, value, groups) => `<div class="f"><span>${t("form.icon")}</span><div class="emo-row"><input id="${id}" class="emo-in" value="${esc(value)}" maxlength="8" aria-label="${t("form.iconChosen")}"><small class="muted">${t("form.iconHint")}</small></div>${emoPicker(id, groups)}</div>`;
function routineForm(r) {
  const isNew = !r;
  r = r || { title: "", emoji: "⭐", place: "", moment: "matin", stars: 1, days: [1, 2, 3, 4, 5, 6, 7], is_bonus: false, timer_minutes: null };
  S.form = { moment: r.moment, days: [...r.days] };
  openSheet(`<h2>${isNew ? t("routine.new") : t("routine.edit")}</h2>
    <label class="f">${t("form.name")}<input id="f-title" maxlength="60" value="${esc(r.title)}" placeholder="${t("routine.placeholder")}"></label>
    ${iconField("f-emoji", r.emoji, EMO_R)}
    <div class="f"><span>${t("form.moment")}</span><div class="seg" role="radiogroup">${MOMENTS().map(([k, , sh, e]) => `<button type="button" role="radio" aria-checked="${r.moment === k}" class="${r.moment === k ? "on" : ""}" data-act="seg" data-group="moment" data-v="${k}">${e} ${sh}</button>`).join("")}</div></div>
    <div class="f"><span>${t("form.days")}</span><div class="days">${weekOrder().map(d => `<button type="button" class="day ${r.days.includes(d) ? "on" : ""}" data-act="toggleDay" data-v="${d}" aria-pressed="${r.days.includes(d)}" aria-label="${dayName(d)}">${DAYS()[d - 1]}</button>`).join("")}</div>
      <div class="presets"><button type="button" class="link" data-act="daysPreset" data-v="all">${t("days.all")}</button>${WEEK.weekend.length ? `<button type="button" class="link" data-act="daysPreset" data-v="week">${t("days.week")}</button><button type="button" class="link" data-act="daysPreset" data-v="we">${t("days.weekend")}</button>` : ""}</div></div>
    <div class="f two"><label>${t("form.stars")}<select id="f-stars">${[1, 2, 3, 4, 5].map(n => `<option value="${n}" ${n === r.stars ? "selected" : ""}>${fmtNum(n)}</option>`).join("")}</select></label>
      <label>${t("form.place")}<select id="f-place"><option value="">${t("form.noPlace")}</option>${[...new Set([...PLACES(), ...(r.place && !PLACES().includes(r.place) ? [r.place] : [])])].map(p => `<option ${p === r.place ? "selected" : ""}>${esc(p)}</option>`).join("")}</select></label></div>
    <label class="f">${t("form.timer")}<select id="f-timer"><option value="">${t("form.noTimer")}</option>${[2, 3, 5, 10, 15, 20, 30].map(n => `<option value="${n}" ${n === r.timer_minutes ? "selected" : ""}>${t("form.minutes", { n })}</option>`).join("")}</select></label>
    <label class="check"><input type="checkbox" id="f-bonus" ${r.is_bonus ? "checked" : ""}> ${t("routine.bonusHelp")}</label>
    <div class="sheet-actions">${isNew ? "" : `<button class="btn danger ghost" data-act="delRoutine" data-id="${r.id}">${t("btn.delete")}</button>`}<button class="btn" data-act="saveRoutine" data-id="${r.id || ""}">${isNew ? t("btn.add") : t("btn.save")}</button></div>`);
}
function rewardForm(w, preset) {
  const isNew = !w;
  w = w || { title: "", emoji: "🎁", tier: "moment", duration_days: 10, child_id: null, costs: {}, cost: 10, event_date: null, place: "", ...(preset || {}) };
  const fixed = !w.duration_days;
  openSheet(`<h2>${isNew ? (w.tier === "event" ? t("reward.newEvent") : t("reward.new")) : t("reward.edit")}</h2>
    <label class="f">${t("form.name")}<input id="w-title" maxlength="60" value="${esc(w.title)}" placeholder="${w.tier === "event" ? t("reward.eventPlaceholder") : t("reward.placeholder")}"></label>
    ${iconField("w-emoji", w.emoji, EMO_W)}
    <div class="f two"><label>${t("reward.level")}<select id="w-tier" data-act="tierChange">${TIERS().map(([k, l]) => `<option value="${k}" ${w.tier === k ? "selected" : ""}>${l}</option>`).join("")}</select></label>
      <label>${t("reward.forLabel")}<select id="w-for">${S.children.length > 1 ? `<option value="">${t("reward.allChildren")}</option>` : ""}${S.children.map(k => `<option value="${k.id}" ${w.child_id === k.id ? "selected" : ""}>${esc(k.name)}</option>`).join("")}</select></label></div>
    <label class="check"><input type="checkbox" id="w-fixed" ${fixed ? "checked" : ""} data-act="pricePreview"> ${t("reward.fixedHelp")}</label>
    <div class="f two"><label>${t("reward.effortDays")}<input id="w-days" type="number" inputmode="numeric" min="1" max="365" value="${w.duration_days || TIER_DAYS[w.tier] || 10}"></label>
      <label>${t("reward.fixedPrice")}<input id="w-cost" type="number" inputmode="numeric" min="1" max="5000" value="${w.cost}"></label></div>
    <p class="muted" id="w-preview"></p>
    <div class="f two"><label>${t("reward.date")}<input id="w-date" type="date" value="${esc(w.event_date || "")}"></label><label>${t("reward.place")}<input id="w-place" maxlength="80" value="${esc(w.place || "")}"></label></div>
    <div class="sheet-actions">${isNew ? "" : `<button class="btn danger ghost" data-act="delReward" data-id="${w.id}">${t("btn.delete")}</button>`}<button class="btn" data-act="saveReward" data-id="${w.id || ""}">${isNew ? t("btn.add") : t("btn.save")}</button></div>`);
  const upd = () => { const d = +$("#w-days").value || 0, fx = $("#w-fixed").checked, who = $("#w-for").value;
    $("#w-preview").textContent = fx ? t("reward.samePrice") : t("reward.computed", { list: (who ? [S.children.find(k => k.id === who)] : S.children).map(k => t("reward.priceOf", { name: k.name, n: fmtNum(roundPrice(d * rhythmOf(k.id))) })).join(t("sep")) }); };
  ["#w-days", "#w-for"].forEach(q => $(q).addEventListener("input", upd)); $("#w-fixed").addEventListener("change", upd); upd();
  $("#w-tier").addEventListener("change", e => { $("#w-days").value = TIER_DAYS[e.target.value]; upd(); });
  if (isNew && preset && preset.child_id === undefined && S.children.length > 1) $("#w-for").value = "";
}
function childForm(c) {
  const isNew = !c;
  c = c || { name: "", emoji: "🧒", color: COLORS[S.children.length % COLORS.length] };
  S.form = { color: c.color };
  openSheet(`<h2>${isNew ? t("child.add") : t("btn.edit")}</h2>
    <label class="f">${t("child.firstName")}<input id="k-name" maxlength="40" value="${esc(c.name)}" autocomplete="off"></label>
    <div class="f"><span>${t("child.avatar")}</span><div class="emo-row"><input id="k-emoji" class="emo-in" value="${esc(c.emoji)}" maxlength="8" aria-label="${t("child.avatarChosen")}">${EMO_K.map(e => `<button type="button" class="emo" data-act="pickEmoji" data-target="k-emoji" data-e="${e}" aria-label="${e}">${e}</button>`).join("")}</div></div>
    <div class="f"><span>${t("child.potColor")}</span><div class="swatches">${COLORS.map(col => `<button type="button" class="sw ${col === c.color ? "on" : ""}" style="background:${col}" data-act="pickColor" data-v="${col}" aria-label="${t("child.color", { c: col })}"></button>`).join("")}</div></div>
    <p class="muted">${t("child.privacy")}</p>
    <div class="sheet-actions">${isNew ? "" : `<button class="btn danger ghost" data-act="delChild" data-id="${c.id}">${t("btn.delete")}</button>`}<button class="btn" data-act="saveChild" data-id="${c.id || ""}">${isNew ? t("btn.add") : t("btn.save")}</button></div>`);
}
// Semaine et fuseau : à l'inscription (mode « onboard ») ou dans les réglages de la famille
function weekForm(mode) {
  const w = mode === "onboard" ? (S.wk || detectWeek()) : { ...WEEK };
  S.form = { wkMode: mode };
  const zones = tzList(); if (!zones.includes(w.tz)) zones.unshift(w.tz);
  openSheet(`<h2>${t("week.title")}</h2><p class="muted">${t("week.help")}</p>
    <label class="f">${t("week.firstDay")}<select id="wk-start">${[1, 2, 3, 4, 5, 6, 7].map(d => `<option value="${d}" ${d === w.start ? "selected" : ""}>${dayName(d)}</option>`).join("")}</select></label>
    <div class="f"><span>${t("week.weekendDays")}</span><ul class="tpl">${[1, 2, 3, 4, 5, 6, 7].map(d => `<li><label><input type="checkbox" class="wk-we" value="${d}" ${w.weekend.includes(d) ? "checked" : ""}> ${dayName(d)}</label></li>`).join("")}</ul></div>
    <label class="f">${t("week.timezone")}<select id="wk-tz">${zones.map(z => `<option value="${esc(z)}" ${z === w.tz ? "selected" : ""}>${esc(tzLabel(z))}</option>`).join("")}</select></label>
    ${mode === "family" ? `<p class="muted small">${t("week.changeNote")}</p>` : ""}
    <div class="sheet-actions"><button class="btn" data-act="saveWeek">${t("btn.save")}</button></div>`);
}
function pinSheet(title, text) {
  return new Promise(res => {
    openSheet(`<h2>${esc(title)}</h2><p>${esc(text)}</p><label class="f">${t("pin.code4")}<input id="pin-in" class="pin" type="password" inputmode="numeric" maxlength="4" autocomplete="off"></label>
      <div class="sheet-actions"><button class="btn ghost" id="pin-no">${t("btn.cancel")}</button><button class="btn" id="pin-ok">${t("btn.validate")}</button></div>`);
    const inp = $("#pin-in"); setTimeout(() => inp.focus(), 50);
    $("#pin-no").onclick = () => { closeSheet(); res(null); };
    $("#pin-ok").onclick = () => { const v = inp.value.trim(); closeSheet(); res(v); };
    dlg.addEventListener("close", () => res(null), { once: true });
  });
}
async function ensurePin() {
  if (store.get("pin")) return true;
  const p = await pinSheet(t("pin.createTitle"), t("pin.createText"));
  if (!p) return false;
  if (!/^\d{4}$/.test(p)) { toast(t("pin.need4"), true); return false; }
  store.set("pin", p); toast(t("pin.saved")); return true;
}
