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
    <div class="f"><span>${t("oneoff.when")}</span>${seg("when", [["le", t("oneoff.on")], ["avant", t("oneoff.before")]], "le")}<input id="x-date" type="date" min="${td}" value="${td}" style="margin-top:6px" aria-label="${t("oneoff.dateAria")}"></div>
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
A.pickPenChild = el => { S.currentChild = el.value; A.breakStar(); };
A.breakStar = () => {
  if (needPremium("malus")) return;
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
A.penaltyCatalog = el => {
  if (needPremium("malus")) return;
  if (el && el.dataset) S.penFrom = el.dataset.from || null;   // ouverte depuis Famille : « Retour » ferme la fenêtre
  const have = new Set(S.penalties.map(p => p.title.toLowerCase()));
  const sugg = TPL_P.map((x, i) => ({ ...x, i })).filter(x => !have.has(x.t.toLowerCase()));
  openSheet(`<h2>${t("malus.catalog")}</h2><p class="muted">${t("malus.catalogHelp")}</p>
    ${S.penalties.length ? `<ul class="hist">${S.penalties.map(p => `<li><span>${esc(p.emoji)} ${esc(p.title)}</span><span>${fmtNum(p.stars)} ⭐</span><button class="link" data-act="delPenalty" data-id="${p.id}" aria-label="${t("a11y.delete", { name: p.title })}">${t("btn.delete")}</button></li>`).join("")}</ul>` : ""}
    ${sugg.length ? `<h3 class="grp">${t("common.suggestions")}</h3><ul class="tpl">${sugg.map(x => `<li><label><input type="checkbox" value="${x.i}"><span>${x.e} ${esc(x.t)} (${fmtNum(x.s)} ⭐)</span></label></li>`).join("")}</ul>` : ""}
    <h3 class="grp">${t("malus.createTitle")}</h3>
    <div class="f two"><label>${t("malus.reason")}<input id="np-title" maxlength="60"></label><label>${t("form.stars")}<select id="np-stars">${[1, 2, 3].map(n => `<option value="${n}">${fmtNum(n)}</option>`).join("")}</select></label></div>
    <div class="sheet-actions"><button class="btn ghost" data-act="${S.penFrom === "family" ? "closeSheet" : "breakStar"}">${t("btn.back")}</button><button class="btn" data-act="savePenalties">${t("btn.save")}</button></div>`);
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
  await reloadParent(t("malus.deleted"), ["pe"]); if (el.dataset.from !== "page") A.penaltyCatalog();
};

// Routines
A.newRoutine = () => routineForm(null);
A.editRoutine = el => routineForm(S.routines.find(r => r.id === el.dataset.id));
A.pickEmoji = el => { const t = $("#" + (el.dataset.target || "f-emoji")); if (t) t.value = el.dataset.e; $$(".emo-box .emo", dlg).forEach(b => b.classList.toggle("on", b === el)); };
A.seg = el => { S.form[el.dataset.group] = el.dataset.v; $$("button", el.parentElement).forEach(b => { const on = b === el; b.classList.toggle("on", on); b.setAttribute("aria-checked", on); }); };
const syncDays = () => $$(".day", dlg).forEach(b => { const on = S.form.days.includes(+b.dataset.v); b.classList.toggle("on", on); b.setAttribute("aria-pressed", on); });
A.toggleDay = el => { const v = +el.dataset.v; S.form.days = S.form.days.includes(v) ? S.form.days.filter(d => d !== v) : [...S.form.days, v]; syncDays(); };
A.daysPreset = el => { S.form.days = { all: [1, 2, 3, 4, 5, 6, 7], week: workDays(), we: weekendDays() }[el.dataset.v]; syncDays(); };
// « Pour » (DEC-09) : à partir de deux enfants, hors vacances, la routine ou les modèles vont aux enfants cochés ; l'enfant affiché est coché d'office (au moins un reste coché)
const forField = (firstId, id) => S.children.length < 2 || S.hctx ? "" : `<div class="f"><span id="${id}">${t("form.for")}</span><div class="chips wrap" role="group" aria-labelledby="${id}">${S.children.map(c =>
  `<button type="button" class="chip for-chip ${c.id === firstId ? "on" : ""}" style="--c:${esc(c.color)};--cc:${esc(chipColor(c.color))}" aria-pressed="${c.id === firstId}" data-act="forToggle" data-id="${c.id}"><span aria-hidden="true">${esc(c.emoji)}</span> <bdi>${esc(c.name)}</bdi></button>`).join("")}</div></div>`;
const forIds = () => { const on = $$(".for-chip.on", dlg).map(b => b.dataset.id); return on.length ? S.children.map(c => c.id).filter(i => on.includes(i)) : [S.currentChild]; };
A.forToggle = el => {
  if (el.classList.contains("on") && $$(".for-chip.on", dlg).length < 2) return;
  const on = !el.classList.contains("on"); el.classList.toggle("on", on); el.setAttribute("aria-pressed", on);
  if (dlg.onForChange) dlg.onForChange();
};
const REMIND_TIMES = (() => { const o = []; for (let h = 5; h < 24; h++) for (const m of [0, 15, 30, 45]) o.push(String(h).padStart(2, "0") + ":" + String(m).padStart(2, "0")); return o; })();   // 05:00 à 23:45 (R11-10)
A.saveRoutine = async el => {
  const title = $("#f-title").value.trim();
  if (!title) return toast(t("routine.needName"), true);
  if (!S.form.days.length) return toast(t("routine.needDay"), true);
  const row = { title, emoji: $("#f-emoji").value.trim() || "⭐", moment: S.form.moment, days: [...S.form.days].sort((a, b) => a - b),
    stars: +$("#f-stars").value, place: $("#f-place").value || null, timer_minutes: $("#f-timer").value ? +$("#f-timer").value : null, is_bonus: $("#f-bonus").checked };
  const rem = $("#f-remind"); if (rem && !rem.disabled) row.remind_at = rem.value || null;   // gratuit : champ fermé, le serveur refuse aussi (SF:premium_reminder) ; l'heure déjà réglée est gardée
  const id = el.dataset.id, ids = id ? [] : forIds();
  let error;
  if (id) ({ error } = await sb.from("routines").update(row).eq("id", id));
  else ({ error } = await sb.from("routines").insert(ids.map(cid => ({ ...row, family_id: S.family.id, child_id: cid, holiday_period_id: S.hctx || null, position: S.routines.filter(r => r.child_id === cid).length }))));   // une seule écriture pour tous les enfants cochés (ADR-56)
  if (error) throw error;
  await afterHolidayEdit(id ? t("routine.saved") : ids.length > 1 ? t("routine.addedN", { n: ids.length }) : t("routine.added"), !!(S.hctx || (id && isHolidayR(S.routines.find(r => r.id === id) || {}))));
};
A.delRoutine = async el => {
  if (!await confirmSheet(t("routine.delTitle"), t("routine.delText"), t("btn.delete"), true)) return;
  const { error } = await sb.from("routines").update({ active: false }).eq("id", el.dataset.id); if (error) throw error;
  await reloadParent(t("routine.deletedToast"), ["r"]);
};
// Titres déjà présents pour un enfant, dans la langue du moment (routines habituelles et exceptionnelles ; vacances : celles de la période ouverte)
const haveTitles = cid => new Set(S.routines.filter(r => r.child_id === cid && (!isHolidayR(r) || r.holiday_period_id === S.hctx)).map(r => r.title.toLowerCase()));
function tplList(ids, checked) {
  const have = {}; ids.forEach(i => { have[i] = haveTitles(i); });
  return TPL_CATS.map(k => {
    const list = TPL_R.map((x, i) => ({ ...x, i })).filter(x => x.c === k);
    return `<h3 class="grp">${t("tpl.cat." + k)}</h3><ul class="tpl">${list.map(x => {
      const by = ids.filter(i => have[i].has(x.t.toLowerCase())), all = by.length === ids.length, part = !all && by.length > 0;
      const note = all ? t("sep") + t("common.alreadyAdded") : part ? t("sep") + t("quick.hadFor", { names: by.map(i => `<bdi>${esc(S.children.find(c => c.id === i).name)}</bdi>`).join(t("sep")) }) : "";
      return `<li><label class="${all ? "had" : ""}"><input type="checkbox" value="${x.i}" ${all ? "disabled" : ""} ${!all && checked.has(x.i) ? "checked" : ""}><span>${x.e} ${esc(x.t)}${x.b ? " " + t("routine.bonusTag") : ""}${t("sep")}${momentLabel(x.m)}${x.d ? t("sep") + lower(t("days.week")) : ""}${note}</span></label></li>`; }).join("")}</ul>`;
  }).join("");
}
A.routineTemplates = () => {
  const c = curChild();
  openSheet(`<h2>${S.hctx ? "🏖️ " : ""}${t("routine.tplFor", { name: esc(c.name) })}</h2>${S.hctx ? `<p class="muted">${t("hol.tplHelp")}</p>` : `<p><button class="btn ghost sm" data-act="quickStart" data-id="${c.id}">⚡ ${t("quick.open")}</button></p>`}${forField(c.id, "for-l")}
    <div id="tpl-list">${tplList([c.id], new Set())}</div><div class="sheet-actions"><button class="btn" data-act="addRoutineTpl">${t("common.addSelection")}</button></div>`);
  dlg.onForChange = () => { const keep = new Set($$("#tpl-list input:checked", dlg).map(i => +i.value)); $("#tpl-list").innerHTML = tplList(forIds(), keep); };
};
A.addRoutineTpl = async () => {
  const picks = $$(".tpl input:checked:not(:disabled)", dlg).map(i => TPL_R[+i.value]);
  if (!picks.length) return toast(t("routine.needOne"), true);
  const ids = forIds(), rows = [];
  for (const cid of ids) {   // un modèle déjà présent pour un enfant n'est créé que pour les autres (F04-02 CA10) ; une seule écriture pour tous (ADR-56)
    const have = haveTitles(cid); let n = S.routines.filter(r => r.child_id === cid).length;
    picks.filter(x => !have.has(x.t.toLowerCase())).forEach(x => rows.push(tplRow(x, cid, n++)));
  }
  const { error } = await sb.from("routines").insert(rows); if (error) throw error;
  await afterHolidayEdit(t("routine.addedN", { n: rows.length }), !!S.hctx);
};
// Ligne de routine d'un modèle : ni catégorie ni tranche d'âge enregistrées (DEC-03, DEC-08)
const tplRow = (x, cid, position) => ({ family_id: S.family.id, child_id: cid, title: x.t, emoji: x.e, moment: x.m, place: x.p != null ? PLACES()[x.p] : null,
  stars: x.s || 1, days: tplDays(x.d), is_bonus: !!x.b, timer_minutes: x.tm || null, position, holiday_period_id: S.hctx || null });

// Démarrage rapide par âge (F04-10, R04-12, ADR-56) : la tranche sert à choisir l'ensemble et n'est jamais enregistrée
A.quickStart = el => {
  const c = S.children.find(k => k.id === (el && el.dataset.id)) || curChild(); if (!c) return;
  openSheet(`<h2>${t("quick.title", { name: `<bdi>${esc(c.name)}</bdi>` })}</h2><p class="muted">${t("quick.help")}</p>
    <div class="ages">${STARTERS.map((st, i) => `<button class="btn" data-act="quickAge" data-id="${c.id}" data-i="${i}">${t("quick.age." + i)}</button>`).join("")}<button class="btn ghost" data-act="quickSelf" data-id="${c.id}">${t("quick.self")}</button></div>`);
};
A.quickSelf = el => { S.currentChild = el.dataset.id; A.routineTemplates(); };
A.quickAge = el => {
  const c = S.children.find(k => k.id === el.dataset.id), st = STARTERS[+el.dataset.i], haveR = haveTitles(c.id), haveW = new Set(S.rewards.map(w => w.title.toLowerCase()));
  const rs = st.r.map(k => TPL_R.findIndex(x => x.k === k)), ws = st.w.map(k => TPL_W.findIndex(x => x.k === k));
  const line = (x, had, extra) => `<li><label class="${had ? "had" : ""}"><input type="checkbox" class="${extra.cls}" value="${extra.i}" ${had ? "disabled" : "checked"}><span>${x.e} ${esc(x.t)}${t("sep")}${extra.note}${had ? t("sep") + t("common.alreadyAdded") : ""}</span></label></li>`;
  openSheet(`<h2>${t("quick.setTitle", { name: `<bdi>${esc(c.name)}</bdi>`, age: t("quick.age." + el.dataset.i) })}</h2>
    <h3 class="grp">${t("quick.routines")}</h3><ul class="tpl">${rs.map(i => line(TPL_R[i], haveR.has(TPL_R[i].t.toLowerCase()), { cls: "qr", i, note: momentLabel(TPL_R[i].m) })).join("")}</ul>
    <h3 class="grp">${t("quick.rewards")}</h3><ul class="tpl">${ws.map(i => line(TPL_W[i], haveW.has(TPL_W[i].t.toLowerCase()), { cls: "qw", i, note: t(`tier.${TPL_W[i].tier}.name`) })).join("")}</ul>
    <div class="sheet-actions"><button class="btn ghost" data-act="quickStart" data-id="${c.id}">${t("intro.back")}</button><button class="btn" data-act="quickAdd" data-id="${c.id}">${t("btn.add")}</button></div>`);
};
A.quickAdd = async el => {
  const c = S.children.find(k => k.id === el.dataset.id);
  const rs = $$(".qr:checked:not(:disabled)", dlg).map(i => TPL_R[+i.value]), ws = $$(".qw:checked:not(:disabled)", dlg).map(i => +i.value);
  if (!rs.length) return toast(t("routine.needOne"), true);
  el.disabled = true;
  try {
    const base = S.routines.filter(r => r.child_id === c.id).length;
    const { data, error } = await sb.from("routines").insert(rs.map((x, i) => ({ ...tplRow(x, c.id, base + i), holiday_period_id: null }))).select(); if (error) throw error;   // routines d'abord, en une écriture
    S.routinesAll = [...(S.routinesAll || []), ...data]; S.routines = [...S.routines, ...data];   // le rythme des prix tient compte des routines ajoutées
    let nW = 0, failed = false;
    if (ws.length) {
      try {
        const wrows = tplRewardRows(ws);
        if (wrows.length) { const r2 = await sb.from("rewards").insert(wrows); if (r2.error) throw r2.error; await markPriced(S.children.map(k => k.id)); nW = wrows.length; }
        else failed = true;
      } catch (e) { console.error(e); failed = true; }
    }
    closeSheet(); await reloadParent(null, ["r", "w", "c"]);
    toast(failed ? t("quick.rewardsFailed", { n: rs.length }) : nW ? t("quick.addedBoth", { r: t("quick.nRoutines", { n: rs.length }), w: t("quick.nRewards", { n: nW }) }) : t("routine.addedN", { n: rs.length }), failed);
  } catch (e) { el.disabled = false; throw e; }
};

// Récompenses
A.newReward = () => rewardForm(null);
A.editReward = el => rewardForm(S.rewards.find(w => w.id === el.dataset.id));
// DEC-47 : pas de récompense à prix calculé tant qu'aucun enfant concerné n'a de routine habituelle obligatoire
function noRhythmSheet(ids) {
  const c = S.children.find(k => ids.includes(k.id) && !hasRhythm(k.id)) || S.children.find(k => k.id === ids[0]);
  openSheet(`<h2>${t("reward.noRhythmTitle")}</h2><p>${t("reward.noRhythm", { name: esc(c.name) })}</p>
    <div class="sheet-actions"><button class="btn ghost" data-act="closeSheet">${t("btn.close")}</button><button class="btn" data-act="goRoutines" data-child="${c.id}">${t("reward.goRoutines")}</button></div>`);
}
A.goRoutines = el => { closeSheet(); S.tab = "routines"; S.currentChild = el.dataset.child; S.reviewing = null; render(); scrollTo(0, 0); };
A.saveReward = async el => {
  const title = $("#w-title").value.trim(), fixed = $("#w-fixed").checked, days = parseInt($("#w-days").value, 10), cost = parseInt($("#w-cost").value, 10);
  if (!title) return toast(t("reward.needName"), true);
  if (fixed && !(cost >= 1 && cost <= PRICE_CAP)) return toast(t("reward.badPrice"), true);
  if (!fixed && !(days >= 1 && days <= 365)) return toast(t("reward.badDays"), true);
  const who = $("#w-for").value || null, ids = who ? [who] : S.children.map(k => k.id), id = el.dataset.id, old = id ? S.rewards.find(w => w.id === id) : null, tier = $("#w-tier").value;
  let costs = {}, base = cost;
  if (!fixed) {
    const res = pricesFor(days, ids, tier, id); if (!res) return noRhythmSheet(ids);   // DEC-47
    costs = res.costs; base = who ? costs[who] : res.common;
    // DT06-03 : à la modification, les prix ne sont recalculés que si la durée change ; ils restent figés sinon
    if (old && old.duration_days === days && old.costs) ids.forEach(k => { if (old.costs[k] != null) costs[k] = +old.costs[k]; });
    if (old && old.duration_days === days && who && old.costs && old.costs[who] != null) base = +old.costs[who];
    else if (old && old.duration_days === days && !who) base = Math.min(...Object.values(costs));
  }
  const row = { title, emoji: $("#w-emoji").value.trim() || "🎁", tier, child_id: who, duration_days: fixed ? null : days, costs, cost: base,
    event_date: $("#w-date").value || null, place: $("#w-place").value.trim() || null };
  if (!fixed) await markPriced(ids);
  const { error } = id ? await sb.from("rewards").update(row).eq("id", id) : await sb.from("rewards").insert({ ...row, family_id: S.family.id });
  if (error) throw error;
  closeSheet(); await reloadParent(id ? t("reward.saved") : t("reward.added"), ["w", "c"]);
};
A.delReward = async el => {
  if (!await confirmSheet(t("reward.delTitle"), t("reward.delText"), t("btn.delete"), true)) return;
  const { error } = await sb.from("rewards").update({ active: false }).eq("id", el.dataset.id); if (error) throw error;
  await reloadParent(t("reward.deleted"), ["w"]);
};
// Prix des récompenses du référentiel (R06-05, F06-02 CA9) : chaque prix tient compte des récompenses existantes et des cases cochées de niveau inférieur ;
// le prix affiché est celui qui sera enregistré. `checked` : indices cochés ; renvoie { indice: { costs, common } }
function tplPrices(checked) {
  const ids = S.children.map(k => k.id), out = {}, extra = {}; ids.forEach(id => extra[id] = []);
  const order = TPL_W.map((x, i) => ({ ...x, i })).sort((a, b) => TIER_RANK[a.tier] - TIER_RANK[b.tier] || a.d - b.d), done = [];
  for (const x of order) {
    const ex = {}; ids.forEach(id => ex[id] = done.filter(d => TIER_RANK[d.tier] < TIER_RANK[x.tier] && d.res.costs[id] != null).map(d => ({ tier: d.tier, cost: d.res.costs[id] })));
    const res = pricesFor(x.d, ids, x.tier, null, ex); out[x.i] = res;
    if (res && checked.has(x.i)) done.push({ tier: x.tier, res });
  }
  return out;
}
const tplPriceText = (res, c) => t("reward.tplPrice", { n: res ? (res.costs[c.id] ?? res.common) : 0, name: esc(c.name) });
A.rewardTemplates = () => {
  const have = new Set(S.rewards.map(w => w.title.toLowerCase())), c = curChild(), ids = S.children.map(k => k.id);
  if (!ids.some(hasRhythm)) return noRhythmSheet([c.id]);   // DEC-47 : message à la place de la liste
  const pr = tplPrices(new Set());
  openSheet(`<h2>${t("reward.tplTitle")}</h2><p class="muted">${hasRhythm(c.id) ? t("reward.tplHelp", { name: esc(c.name), n: fmtNum(Math.round(rhythmOf(c.id) * 10) / 10) }) : t("reward.tplHelpNoRhythm", { name: esc(c.name) })}</p>
    ${TIERS().filter(([k]) => k !== "event").map(([k, l, d]) => `<h3 class="tier-h">${l}<small>${d}</small></h3><ul class="tpl">${TPL_W.map((x, i) => ({ ...x, i })).filter(x => x.tier === k).map(x => { const had = have.has(x.t.toLowerCase()); return `<li><label class="${had ? "had" : ""}"><input type="checkbox" value="${x.i}" ${had ? "disabled" : ""}><span>${x.e} ${esc(x.t)} <span class="tp" data-i="${x.i}">${tplPriceText(pr[x.i], c)}</span>${had ? t("sep") + t("common.alreadyAdded") : ""}</span></label></li>`; }).join("")}</ul>`).join("")}
    <h3 class="tier-h">${t("tier.event.name")}<small>${t("tier.event.hint")}</small></h3><p class="muted">${t("reward.eventHelp")}</p>
    <div class="sheet-actions"><button class="btn ghost" data-act="newEvent">${t("reward.createEvent")}</button><button class="btn" data-act="addRewardTpl">${t("common.addSelection")}</button></div>`);
  // F06-02 CA9 : à chaque case cochée ou décochée, les prix affichés sont recalculés
  dlg.onchange = e => { if (!e.target.matches(".tpl input")) return; const chk = new Set($$(".tpl input:checked", dlg).map(i => +i.value)), p2 = tplPrices(chk);
    $$(".tp", dlg).forEach(el => { el.textContent = tplPriceText(p2[+el.dataset.i], c); }); };
};
A.newEvent = () => rewardForm(null, { tier: "event", emoji: "🎪", title: t("reward.eventDefault"), duration_days: 30 });
// Lignes de récompenses du référentiel (indices de `TPL_W`) avec leurs prix calculés ; les prix enregistrés sont ceux qui étaient affichés (F06-02 CA9)
function tplRewardRows(chk) {
  const pr = tplPrices(new Set(chk));
  return chk.map(i => ({ x: TPL_W[i], res: pr[i] })).filter(o => o.res).sort((a, b) => TIER_RANK[a.x.tier] - TIER_RANK[b.x.tier] || a.x.d - b.x.d)
    .map(({ x, res }) => ({ family_id: S.family.id, title: x.t, emoji: x.e, tier: x.tier, duration_days: x.d, costs: res.costs, cost: res.common }));
}
A.addRewardTpl = async () => {
  const chk = $$(".tpl input:checked", dlg).map(i => +i.value);
  if (!chk.length) return toast(t("reward.needOne"), true);
  const ids = S.children.map(k => k.id);
  if (!ids.some(hasRhythm)) return noRhythmSheet(ids);
  const rows = tplRewardRows(chk);
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
    () => sb.rpc("redeem", { p_child: c.id, p_reward: w.id, ...(id ? { p_id: id } : {}) }), ["z", "s"], t("reward.exchanged"));   // EP-09 : le serveur relit le prix et le solde
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
A.pickColor = el => { S.form.color = el.dataset.v; $$(".sw", dlg).forEach(b => { b.classList.toggle("on", b === el); b.setAttribute("aria-pressed", String(b === el)); }); };
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
  if (!id) A.quickStart({ dataset: { id: res.data.id } });   // F04-10 CA1 : le démarrage rapide s'ouvre après l'ajout d'un enfant
  refreshParts(["c", "w"]).then(render).catch(() => {});
};
A.delChild = async el => {
  const c = S.children.find(k => k.id === el.dataset.id);
  if (!await confirmSheet(t("child.delTitle", { name: c.name }), (nR => nR ? t("child.delTextRewards", { n: nR }) : t("child.delText"))(S.rewards.filter(w => w.child_id === c.id).length), t("btn.delete"), true)) return;   // DT03-06 : les récompenses réservées partent avec l'enfant
  await mutate(() => sb.from("children").delete().eq("id", c.id));
  const other = x => x.child_id !== c.id;
  S.children = S.children.filter(k => k.id !== c.id);
  ["routines", "completions", "redemptions", "pevents", "pauses", "holidays", "hp", "ho"].forEach(k => { if (Array.isArray(S[k])) S[k] = S[k].filter(other); });
  S.devices = (S.devices || []).map(d => ({ ...d, child_ids: (d.child_ids || [d.child_id]).filter(x => x !== c.id) })).filter(d => d.child_ids.length);   // l'appareil reste pour les enfants qui restent (F03-09 CA9)
  if (S.currentChild === c.id) S.currentChild = S.children[0]?.id || null;
  saveParentCache(); render(); toast(t("common.deletedM"));
  refreshParts(["c", "w", "d"]).then(render).catch(() => {});
};
A.deviceCode = async el => {
  const c = S.children.find(k => k.id === el.dataset.id);
  let ids = [c.id];
  if (S.children.length >= 2) {   // appareil commun (F03-09) : un ou plusieurs enfants ; chaque enfant d'un appareil commun a son code d'enfant (R03-11)
    ids = await kidsSheet(c.id, t("device.pickTitle"), t("device.pickHelp"), t("device.getCode")); if (!ids) return;
    if (ids.length > 1 && !await ensureKidCodes(ids)) return;
  }
  const { data, error } = await sb.rpc("create_child_code", { p_child: ids[0], p_children: ids }); if (error) throw error;
  const who = ids.length > 1 ? ids.map(i => `<bdi>${esc(S.children.find(k => k.id === i)?.name || "")}</bdi>`).join(t("sep")) : `<bdi>${esc(c.name)}</bdi>`;
  openSheet(`<h2>${ids.length > 1 ? t("device.sharedOf", { names: who }) : t("device.phoneOf", { name: esc(c.name) })}</h2><div class="code" aria-label="${t("device.codeAria", { code: data.split("").join(" ") })}">${esc(data)}</div>
    <p>${t("device.help")}</p>
    <div class="sheet-actions"><button class="btn" data-act="closeSheetReload">${t("btn.done")}</button></div>`);
};
A.closeSheetReload = async () => { closeSheet(); await reloadParent(null, ["d"]); };   // l'appareil relié apparaît
A.revokeDevice = async el => {
  const id = el.dataset.id;
  if (!await confirmSheet(t("device.revokeTitle"), t("device.revokeText") + " " + t("device.revokeLost"), t("family.disconnect"), true)) return;
  await mutate(() => sb.from("child_devices").delete().eq("id", id));
  S.devices = S.devices.filter(d => d.id !== id); saveParentCache(); render(); toast(t("device.revoked"));
  refreshParts(["d"]).then(render).catch(() => {});
};
A.childHere = async el => {
  if (!await ensurePin()) return;
  const cid = el.dataset.id; let ids = [cid];
  if (S.children.length >= 2) {   // F03-06 CA8 : un ou plusieurs enfants ; plusieurs ouvrent « Qui es-tu ? » (R03-10)
    ids = await kidsSheet(cid, t("device.hereTitle"), t("device.hereHelp"), t("btn.validate")); if (!ids) return;
    if (ids.length > 1 && !await ensureKidCodes(ids)) return;
  }
  // La ligne de ce téléphone est réutilisée si le serveur la reconnaît (R03-08) ; ses enfants sont mis à jour. Adresse d'envoi des rappels de l'adulte : notée sur la ligne (ADR-57, R11-10).
  const map = store.get("sameDevice", {}), old = ids.map(i => map[i]).find(Boolean) || null;
  const r = await sb.rpc("child_pair_here", { p_child: ids[0], p_label: t("device.sameLabel", { who: memberLabel(S.session.user.id) }), p_children: ids, p_token: old, p_endpoint: await curEndpoint() }); if (r.error) throw r.error;
  const tok = r.data.token;
  Object.keys(map).forEach(k => { if (map[k] === old || map[k] === tok) delete map[k]; });
  ids.forEach(i => { map[i] = tok; }); store.set("sameDevice", map);
  clearChildStore(); store.set("childToken", tok); store.set("childFromParent", true);
  S.childNow = null; S.kidPick = null; S.kidSeq = [];
  if (ids.length > 1) await loadKids(tok, ids[0]);   // liste des enfants reliés, pour « Qui es-tu ? »
  S.screen = "child"; S.ctab = "today"; S.cs = null; render(); if (!kidsList()) await loadChild(null);
};
// « Code oublié ? » : le mot de passe du compte connecté sur ce téléphone remplace le code (DEC-28). Compteur propre, vérifié avant tout envoi (DEC-55).
async function forgotPin(sess) {
  const wait = guardLeft("pwdGuard"); if (wait) { toast(t("pin.locked", { n: wait }), true); return false; }
  const pw = await passwordSheet(); if (pw === null) return false;
  if (!navigator.onLine) { toast(t("pin.pwdNeedNet"), true); return false; }
  const { error } = await sb.auth.signInWithPassword({ email: sess.user.email, password: pw });
  if (error) {
    if (isNetErr(error)) { toast(t("pin.pwdNeedNet"), true); return false; }
    if (error.status === 429 || /rate limit|too many/i.test(error.message || "")) { toast(t("err.rateLimit"), true); return false; }
    const n = guardFail("pwdGuard"); toast(n ? t("pin.locked", { n }) : t("pin.pwdWrong"), true); return false;
  }
  guardReset("pwdGuard"); guardReset("pinGuard"); store.del("pinH"); S.askPin = true;   // code effacé : un nouveau est proposé à l'arrivée dans l'espace parent
  return true;
}
A.exitChild = async () => {
  await pinMigrate();
  if (hasPin()) {
    const sess = (await sb.auth.getSession()).data.session;   // parent connecté (Mode enfant ici) : « Code oublié ? » possible
    const wait = guardLeft("pinGuard");
    const v = await pinSheet(t("kid.parentSpace"), wait ? t("pin.locked", { n: wait }) : t("pin.enter"), { forgot: !!sess, locked: !!wait });
    if (v === null) return;
    if (v.forgot) { if (!await forgotPin(sess)) return; }
    else {
      if (!await pinCheck(v)) { const n = guardFail("pinGuard"); return toast(n ? t("pin.locked", { n }) : t("pin.wrong"), true); }
      guardReset("pinGuard");
    }
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
  // DT03-04 : coches pas encore envoyées (hors ligne) : avertissement, la sortie peut être annulée
  const pending = (store.get("queue", []) || []).length;
  if (pending && !await confirmSheet(t("kid.exitOfflineTitle"), t("kid.exitOfflineText", { n: pending }), t("kid.exitAnyway"), true)) return;
  if (store.get("cpushOn")) {
    try { const reg = await navigator.serviceWorker.ready; const sub = await reg.pushManager.getSubscription();
      if (sub) { await sb.rpc("push_unsubscribe", { p_endpoint: sub.endpoint }); await sub.unsubscribe(); } } catch {}
    store.set("pushOn", false);
  }
  // EP-09 (DT03-02, ADR-49) : sur le téléphone propre de l'enfant, la sortie retire l'appareil chez le parent (hors ligne : file locale, sinon purge de 3 mois)
  if (!store.get("childFromParent")) await unpairDevice(store.get("childToken"));
  clearChildStore(); S.childNow = null; S.kidPick = null; S.kidSeq = [];
  S.cs = null;
  const { data } = await sb.auth.getSession();
  if (data.session) { S.session = data.session; S.tab = "family"; await enterParent(); if (S.askPin) { S.askPin = false; A.setPin(); } } else { S.screen = "auth"; render(); }
};
