"use strict";
/* SoisFier : Mode vacances (Premium) */
/* ================= Mode vacances (Premium) =================
   Une période par enfant. Pendant la période, chaque routine habituelle suit son réglage (holiday_overrides),
   et les routines de vacances (routines.holiday_period_id) s'ajoutent. Le serveur applique les mêmes règles (private.routine_rules). */
const holLabel = p => t("pause.range", { from: fmtDate(p.start_day), to: fmtDate(p.end_day) });
const holState = p => { const td = todayISO(); return p.end_day < td ? "past" : p.start_day > td ? "next" : "now"; };
/* Section « Vacances et absences » de Famille (v27) : Mode vacances d'abord, pause ensuite, une seule liste chronologique.
   Une pause qui chevauche un Mode vacances l'emporte (jour neutre) : la ligne le dit. */
function vacSection() {
  const td = todayISO(), kid = id => S.children.find(c => c.id === id) || { emoji: "", name: "" };
  const hols = (S.holidays || []).filter(p => p.end_day >= td), pzs = (S.pauses || []).filter(p => p.end_day >= td);
  const rows = [...hols.map(p => ({ k: "h", p })), ...pzs.map(p => ({ k: "p", p }))]
    .sort((a, b) => a.p.start_day < b.p.start_day ? -1 : a.p.start_day > b.p.start_day ? 1 : a.k < b.k ? -1 : 1);
  const row = ({ k, p }) => { const c = kid(p.child_id), who = esc(c.emoji + " " + c.name);
    if (k === "h") return `<li><button class="pen hrow" data-act="holReview" data-id="${p.id}" aria-label="${t("hol.review")} ${esc(p.name)}"><span><b>🏖️ ${esc(p.name)}</b><small>${who}${t("sep")}${holLabel(p)}${t("sep")}${t("hol.state." + holState(p))}</small></span><span class="link">${t("hol.review")}</span></button></li>`;
    const wins = hols.some(h => h.child_id === p.child_id && h.active !== false && h.start_day <= p.end_day && p.start_day <= h.end_day);
    return `<li><button class="pen hrow" data-act="editPause" data-id="${p.id}" aria-label="${t("pause.edit")}"><span><b>⏸️ ${esc(pauseReason(p))}</b><small>${who}${t("sep")}${holLabel(p)}${t("sep")}${t("pause.state." + holState(p))}${wins ? `<br><span class="pz">${t("vac.pauseWins")}</span>` : ""}</small></span><span class="link">${t("btn.edit")}</span></button></li>`; };
  return `<p class="muted">${t("vac.help")}</p>
    ${rows.length ? `<ul class="tpl">${rows.map(row).join("")}</ul>` : ""}
    <div class="actions"><button class="btn" data-act="holNew">${t("hol.new")}${ptag()}</button><button class="btn ghost" data-act="newPause">${t("pause.new")}</button></div>`;
}
// Après une modification faite pendant des vacances : alerte, puis retour à la revue si elle était ouverte
async function afterHolidayEdit(msg, holiday) {
  const back = S.reviewing; await refreshParts(["hp", "ho", "r"]);
  if (back && (S.holidays || []).some(p => p.id === back)) { A.holReview({ dataset: { id: back } }); render(); }
  else { closeSheet(); render(); }
  toast(holiday ? t("hol.onlyThese") : msg);
}
A.toggleHabitual = () => { S.showHabitual = !S.showHabitual; render(); };
// Création : enfant, nom, dates, reprise éventuelle d'une période précédente du même enfant
A.holNew = el => {
  if (needPremium("holidays")) return;
  const pick = el && el.dataset.child, keep = id => pick && dlg.open ? $(id)?.value : null;   // changement d'enfant : on garde la saisie
  const f = S.hform = { child: pick || curChild().id, name: keep("#h-name") ?? "", from: keep("#h-from") || todayISO(), to: keep("#h-to") || addDays(todayISO(), 13) };
  const prev = (S.holidays || []).filter(p => p.child_id === f.child).sort((a, b) => a.start_day < b.start_day ? 1 : -1);
  openSheet(`<h2>🏖️ ${t("hol.new")}</h2><p class="muted">${t("hol.newHelp")}</p>
    <div class="f"><span>${t("hol.child")}</span><div class="seg" role="radiogroup">${S.children.map(c => `<button type="button" role="radio" aria-checked="${c.id === f.child}" class="${c.id === f.child ? "on" : ""}" data-act="holNew" data-child="${c.id}">${esc(c.emoji)} ${esc(c.name)}</button>`).join("")}</div></div>
    <label class="f">${t("hol.name")}<input id="h-name" maxlength="40" value="${esc(f.name)}" placeholder="${t("hol.namePlaceholder")}"></label>
    <div class="f two"><label>${t("pause.from")}<input type="date" id="h-from" value="${f.from}"></label><label>${t("pause.to")}<input type="date" id="h-to" value="${f.to}"></label></div>
    ${prev.length ? `<label class="f">${t("hol.copyFrom")}<select id="h-copy"><option value="">${t("hol.copyNone")}</option>${prev.map(p => `<option value="${p.id}">${esc(p.name)} (${holLabel(p)})</option>`).join("")}</select></label>` : ""}
    <div class="sheet-actions"><button class="btn" data-act="holCreate">${t("hol.next")}</button></div>`);
};
A.holCreate = async () => {
  const f = S.hform, name = $("#h-name").value.trim(), a = $("#h-from").value, b = $("#h-to").value, copy = $("#h-copy") ? $("#h-copy").value : "";
  if (!name) return toast(t("hol.needName"), true);
  if (!a || !b || b < a) return toast(t("pause.badDates"), true);
  if (b < todayISO()) return toast(t("hol.pastDates"), true);
  const { data: id, error } = await sb.rpc("holiday_create", { p_child: f.child, p_name: name, p_from: a, p_to: b, p_copy: copy || null });
  if (error) throw error;
  S.hform = null; S.currentChild = f.child; await refreshParts(["hp", "ho", "r"]); A.holReview({ dataset: { id } }); render();
};
// Revue : chaque routine habituelle (comme d'habitude par défaut), puis les routines de vacances
A.holReview = el => {
  const p = (S.holidays || []).find(x => x.id === el.dataset.id); if (!p) return closeSheet();
  const c = S.children.find(k => k.id === p.child_id); S.currentChild = c.id; S.hctx = p.id; S.reviewing = p.id;
  const habit = S.routines.filter(r => r.child_id === c.id && !isOneoff(r) && !isHolidayR(r)).sort((a, b) => MOMENTS_K.findIndex(m => m[0] === a.moment) - MOMENTS_K.findIndex(m => m[0] === b.moment));
  const vac = S.routines.filter(r => r.holiday_period_id === p.id);
  const sibs = (S.holidays || []).filter(x => x.child_id !== c.id && S.routines.some(r => r.holiday_period_id === x.id));
  const setting = r => { const o = p.ov[r.id]; if (!o) return t("hol.same");
    if (o.status === "off") return "⏸️ " + t("hol.off");
    const parts = [o.status ? t(o.status === "bonus" ? "routine.bonus" : "routine.mandatory") : null, o.days ? daysLabel(o.days) : null, o.stars ? t("hol.starsN", { n: o.stars }) : null].filter(Boolean);
    return "✏️ " + parts.join(t("sep")); };
  const started = holState(p) !== "next";
  openSheet(`<h2>🏖️ ${esc(p.name)}</h2><p class="muted">${esc(c.emoji + " " + c.name)}${t("sep")}${holLabel(p)}${t("sep")}${t("hol.state." + holState(p))}</p>
    <div class="actions" style="margin-top:0"><button class="btn sm ghost" data-act="holDates" data-id="${p.id}">${t("hol.editDates")}</button><button class="btn sm ghost danger" data-act="holStop" data-id="${p.id}">${started ? t("hol.stop") : t("btn.delete")}</button></div>
    <h3 class="grp">${t("hol.habitTitle")}</h3><p class="muted small">${t("hol.habitHelp")}</p>
    ${habit.length ? `<ul class="tpl">${habit.map(r => `<li><button class="pen" data-act="holEdit" data-p="${p.id}" data-id="${r.id}"><span>${esc(r.emoji)} ${esc(r.title)}</span><span class="muted">${setting(r)}</span></button></li>`).join("")}</ul>` : `<p class="empty">${t("common.none")}</p>`}
    <h3 class="grp">🏖️ ${t("hol.vacTitle")}</h3>
    ${vac.length ? `<ul class="tpl">${vac.map(r => `<li><button class="pen" data-act="editRoutine" data-id="${r.id}"><span>${esc(r.emoji)} ${esc(r.title)}</span><span class="muted">${daysLabel(r.days)}${t("sep")}${fmtNum(r.stars)} ⭐${r.is_bonus ? t("sep") + t("routine.bonus") : ""}</span></button></li>`).join("")}</ul>` : `<p class="muted">${t("hol.vacNone")}</p>`}
    <div class="actions"><button class="btn ghost sm" data-act="newRoutine">+ ${t("hol.newRoutine")}</button><button class="btn ghost sm" data-act="routineTemplates">${t("routine.chooseTpl")}</button>${sibs.length ? `<button class="btn ghost sm" data-act="holSib" data-id="${p.id}">${t("hol.fromSibling")}</button>` : ""}</div>
    <div class="sheet-actions"><button class="btn" data-act="holClose">${t("btn.done")}</button></div>`);
};
A.holClose = () => { S.reviewing = null; S.hctx = null; closeSheet(); render(); };
// Réglage d'une routine habituelle pour la période
A.holEdit = el => {
  const p = S.holidays.find(x => x.id === el.dataset.p), r = S.routines.find(x => x.id === el.dataset.id), o = p.ov[r.id] || {};
  S.form = { st: o.status || "", days: [...(o.days || r.days)], p: p.id, r: r.id };
  const cap = x => x.charAt(0).toLocaleUpperCase(loc()) + x.slice(1);
  const opts = [["", t("hol.same")], ["required", cap(t("routine.mandatory"))], ["bonus", cap(t("routine.bonus"))], ["off", t("hol.off")]];
  openSheet(`<h2>${esc(r.emoji)} ${esc(r.title)}</h2><p class="muted">🏖️ ${esc(p.name)}${t("sep")}${t("hol.usually", { what: [daysLabel(r.days), t("hol.starsN", { n: r.stars }), r.is_bonus ? t("routine.bonus") : t("routine.mandatory")].join(t("sep")) })}</p>
    <div class="f"><span>${t("hol.status")}</span><div class="seg" role="radiogroup">${opts.map(([k, l]) => `<button type="button" role="radio" aria-checked="${S.form.st === k}" class="${S.form.st === k ? "on" : ""}" data-act="seg" data-group="st" data-v="${k}">${l}</button>`).join("")}</div></div>
    <div class="f"><span>${t("form.days")}</span><div class="days">${weekOrder().map(d => `<button type="button" class="day ${S.form.days.includes(d) ? "on" : ""}" data-act="toggleDay" data-v="${d}" aria-pressed="${S.form.days.includes(d)}" aria-label="${dayName(d)}">${DAYS()[d - 1]}</button>`).join("")}</div>
      <div class="presets"><button type="button" class="link" data-act="daysPreset" data-v="all">${t("days.all")}</button>${WEEK.weekend.length ? `<button type="button" class="link" data-act="daysPreset" data-v="week">${t("days.week")}</button><button type="button" class="link" data-act="daysPreset" data-v="we">${t("days.weekend")}</button>` : ""}</div></div>
    <label class="f">${t("form.stars")}<select id="h-stars">${[1, 2, 3, 4, 5].map(n => `<option value="${n}" ${n === (o.stars || r.stars) ? "selected" : ""}>${fmtNum(n)}</option>`).join("")}</select></label>
    <p class="muted small">${t("hol.editHelp")}</p>
    <div class="sheet-actions">${p.ov[r.id] ? `<button class="btn ghost" data-act="holReset">${t("hol.reset")}</button>` : ""}<button class="btn" data-act="holSave">${t("btn.save")}</button></div>`);
};
A.holSave = async () => {
  const f = S.form, p = S.holidays.find(x => x.id === f.p), r = S.routines.find(x => x.id === f.r);
  if (!f.days.length) return toast(t("routine.needDay"), true);
  const days = [...f.days].sort((a, b) => a - b), stars = +$("#h-stars").value;
  const row = { period_id: p.id, routine_id: r.id, child_id: r.child_id, family_id: S.family.id, status: f.st || null,
    days: days.join() === [...r.days].sort((a, b) => a - b).join() ? null : days, stars: stars === r.stars ? null : stars };
  await holWrite(p, r, (row.status || row.days || row.stars) ? row : null);
};
A.holReset = async () => { const f = S.form; await holWrite(S.holidays.find(x => x.id === f.p), S.routines.find(x => x.id === f.r), null); };
// Écrit un réglage : l'écran est mis à jour tout de suite, l'enregistrement suit ; en cas d'erreur, retour à l'état précédent
async function holWrite(p, r, row) {
  const before = p.ov[r.id], ho = S.ho || [];
  const apply = o => { if (o) p.ov[r.id] = o; else delete p.ov[r.id];
    S.ho = [...ho.filter(v => !(v.period_id === p.id && v.routine_id === r.id)), ...(o ? [o] : [])]; };
  apply(row);
  if (S.reviewing) A.holReview({ dataset: { id: S.reviewing } }); else closeSheet();
  render(); toast(t("hol.onlyThese"));
  const { error } = row ? await sb.from("holiday_overrides").upsert(row) : await sb.from("holiday_overrides").delete().eq("period_id", p.id).eq("routine_id", r.id);
  if (error) { apply(before); if (S.reviewing && dlg.open) A.holReview({ dataset: { id: S.reviewing } }); render(); throw error; }
  saveParentCache(); bgRefresh();
}
// Nom et dates (début modifiable tant que la période n'a pas commencé)
A.holDates = el => {
  const p = S.holidays.find(x => x.id === el.dataset.id), started = holState(p) !== "next";
  openSheet(`<h2>🏖️ ${t("hol.editDates")}</h2><label class="f">${t("hol.name")}<input id="h-name" maxlength="40" value="${esc(p.name)}"></label>
    <div class="f two"><label>${t("pause.from")}<input type="date" id="h-from" value="${p.start_day}" ${started ? "disabled" : ""}></label><label>${t("pause.to")}<input type="date" id="h-to" value="${p.end_day}"></label></div>
    <div class="sheet-actions"><button class="btn ghost" data-act="holReview" data-id="${p.id}">${t("btn.back")}</button><button class="btn" data-act="holSaveDates" data-id="${p.id}">${t("btn.save")}</button></div>`);
};
A.holSaveDates = async el => {
  const name = $("#h-name").value.trim(), a = $("#h-from").value, b = $("#h-to").value;
  if (!name) return toast(t("hol.needName"), true);
  if (!a || !b || b < a) return toast(t("pause.badDates"), true);
  const { error } = await sb.from("holiday_periods").update({ name, start_day: a, end_day: b }).eq("id", el.dataset.id); if (error) throw error;
  await refreshParts(["hp"]); A.holReview(el); render(); toast(t("common.savedM"));
};
// Supprimer (pas encore commencée) ou arrêter (dernier jour : hier ; les étoiles gagnées restent)
A.holStop = async el => {
  const p = S.holidays.find(x => x.id === el.dataset.id), td = todayISO(), started = p.start_day < td;
  if (!await confirmSheet(started ? t("hol.stopTitle") : t("hol.delTitle"), started ? t("hol.stopText", { date: fmtLong(addDays(td, -1)), name: esc(p.name) }) : t("hol.delText"), started ? t("hol.stop") : t("btn.delete"), true)) return A.holReview(el);
  const { error } = started ? await sb.from("holiday_periods").update({ end_day: addDays(td, -1) }).eq("id", p.id)
    : await sb.from("holiday_periods").delete().eq("id", p.id);
  if (error) throw error;
  S.reviewing = null; S.hctx = null; closeSheet(); await reloadParent(started ? t("hol.stopped") : t("common.deletedF"), ["hp", "ho", "r"]);
};
// Copier les routines de vacances d'un frère ou d'une sœur
A.holSib = el => {
  const p = S.holidays.find(x => x.id === el.dataset.id);
  const sibs = S.holidays.filter(x => x.child_id !== p.child_id && S.routines.some(r => r.holiday_period_id === x.id));
  openSheet(`<h2>${t("hol.fromSibling")}</h2><p class="muted">${t("hol.fromSiblingHelp")}</p>
    <ul class="tpl">${sibs.map(x => { const k = S.children.find(c => c.id === x.child_id) || { emoji: "", name: "" }; const n = S.routines.filter(r => r.holiday_period_id === x.id).length;
      return `<li><button class="pen" data-act="holSibCopy" data-from="${x.id}" data-id="${p.id}"><span>${esc(k.emoji + " " + k.name)}${t("sep")}${esc(x.name)}</span><span class="muted">${t("hol.routinesN", { n })}</span></button></li>`; }).join("")}</ul>
    <div class="sheet-actions"><button class="btn ghost" data-act="holReview" data-id="${p.id}">${t("btn.back")}</button></div>`);
};
A.holSibCopy = async el => {
  const { data: n, error } = await sb.rpc("holiday_copy", { p_from: el.dataset.from, p_to: el.dataset.id }); if (error) throw error;
  await refreshParts(["r"]); A.holReview(el); render(); toast(t("hol.copied", { n: n || 0 }));
};
A.repriceChild = async () => {
  const c = curChild(), r = rhythmOf(c.id), ws = S.rewards.filter(w => w.duration_days && (!w.child_id || w.child_id === c.id) && w.costs && w.costs[c.id] != null);
  for (const w of ws) { const costs = { ...w.costs, [c.id]: roundPrice(w.duration_days * r) }; const { error } = await sb.from("rewards").update({ costs, ...(w.child_id ? { cost: costs[c.id] } : {}) }).eq("id", w.id); if (error) throw error; }
  const { error } = await sb.from("children").update({ price_rhythm: r }).eq("id", c.id); if (error) throw error;
  await reloadParent(t("reward.repriced", { name: c.name }), ["w", "c"]);
};
async function markPriced(ids) { for (const id of ids) { const c = S.children.find(k => k.id === id); if (c && !c.price_rhythm) await sb.from("children").update({ price_rhythm: rhythmOf(id) }).eq("id", id); } }
