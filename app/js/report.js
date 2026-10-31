"use strict";
/* SoisFier : Report de la semaine (EP-13 V1, F04-09, R04-11).
   Grille à toucher, sans caméra : le Parent choisit l'enfant, la semaine (en cours ou précédente), touche les ronds cochés sur la feuille
   papier, puis « Reporter » envoie tout en un seul appel à public.report_sheet (le serveur contrôle Parent, Premium, semaine, jour,
   routine due ; rien n'est enregistré avant). La V2 (scan.js) pré-remplira la même grille. */
const REP = { child: null, week: "cur", marks: { cur: new Set(), prev: new Set() }, busy: false };
const repKey = (rid, day) => rid + "|" + day;
// Premier jour de la semaine en cours (« cur ») ou de la précédente (« prev »), comme la feuille imprimée
const repFirst = k => { const td = todayISO(), f = addDays(td, -((dowOf(td) - WEEK.start + 7) % 7)); return k === "prev" ? addDays(f, -7) : f; };
// Routines habituelles de la semaine et, pour chaque jour, celles qui sont dues : même calcul que printPlanning (Mode vacances compris)
function repRows(childId, first) {
  const dates = weekOrder().map((_, i) => addDays(first, i));
  const due = dates.map(d => new Map(dueOn(S.routines, childId, d).filter(r => !isOneoff(r)).map(r => [r.id, r])));
  const rs = S.routines.filter(r => r.child_id === childId && !isOneoff(r) && due.some(m => m.has(r.id)));
  return { dates, due, rs };
}
// Nom accessible d'un rond : « {routine}, {jour}, coché » (F04-09 CA10) ; « à venir » pour un jour pas encore passé
const repLabel = (r, dow, state) => t("report.cell", { routine: r.title, day: dayName(dow), state: t("report." + state) });
const repState = (on, future) => future ? "future" : on ? "checked" : "unchecked";

function repGrid() {
  const c = S.children.find(k => k.id === REP.child), first = repFirst(REP.week), { dates, due, rs } = repRows(c.id, first);
  const td = todayISO(), marks = REP.marks[REP.week], order = weekOrder();
  const body = MOMENTS().map(([k, l, , e]) => {
    const list = rs.filter(r => r.moment === k); if (!list.length) return "";
    return `<h3 class="grp">${e} ${l}</h3>` + list.map(r => `<div class="rp-row"><div class="rp-name">${isHolidayR(r) ? "🏖️ " : ""}${esc(r.emoji)} ${esc(r.title)}</div><div class="rp-cells">${dates.map((d, i) => {
      if (!due[i].has(r.id)) return `<span class="rp-off" aria-hidden="true"></span>`;
      const future = d > td, on = marks.has(repKey(r.id, d));
      return `<button type="button" class="rp-c ${on ? "on" : ""}" data-act="repToggle" data-r="${r.id}" data-d="${d}" aria-pressed="${on}" aria-label="${esc(repLabel(r, order[i], repState(on, future)))}" ${future ? "disabled" : ""}><small aria-hidden="true">${t("days.abbr")[order[i] - 1]}</small><span class="rp-dot" aria-hidden="true">${on ? "✓" : ""}</span></button>`;
    }).join("")}</div></div>`).join("");
  }).join("");
  return (body || `<p class="empty">${t("report.none")}</p>`) + (dates.some(d => d > td) ? `<p class="muted small">${t("report.futureNote")}</p>` : "");
}
// Bouton « Reporter » : nombre de coches de la semaine choisie ; inactif sans coche, en cours d'envoi ou hors ligne (DEC-07)
function repSync() {
  const go = $("#rp-go", dlg); if (!go) return;
  const n = REP.marks[REP.week].size, off = !navigator.onLine;
  go.textContent = n ? t("report.go", { n }) : t("report.goNone");
  go.disabled = !n || REP.busy || off;
  const hint = $("#rp-off", dlg); if (hint) hint.hidden = !off;
}
window.addEventListener("online", repSync);
window.addEventListener("offline", repSync);

function repOpen(childId) {
  REP.child = childId; REP.week = "cur"; REP.marks = { cur: new Set(), prev: new Set() }; REP.busy = false;
  const c = S.children.find(k => k.id === childId); if (!c) return;
  const pill = (k, label, on) => `<label class="rp-w ${on ? "on" : ""}"><input type="radio" name="rp-week" value="${k}" data-act="repWeek" class="vh" ${on ? "checked" : ""}>${label}</label>`;
  openSheet(`<h2 id="rp-title" tabindex="-1">${esc(c.emoji)} ${esc(c.name)}</h2>
    <p class="muted small">${t("report.intro")}</p>
    <div class="seg rp-weeks" role="radiogroup" aria-label="${t("report.weekLabel")}">${pill("cur", t("report.thisWeek"), true)}${pill("prev", t("report.lastWeek"), false)}</div>
    <p class="muted small" id="rp-date"></p>
    <div id="rp-grid"></div>
    <p class="muted small" id="rp-off" hidden>${t("report.offline")}</p>
    <div class="sheet-actions"><button class="btn ghost" data-act="closeSheet">${t("btn.cancel")}</button><button class="btn" id="rp-go" data-act="repGo" disabled></button></div>`);
  repWeekDraw();
  const h = $("#rp-title", dlg); if (h) h.focus();
}
function repWeekDraw() {
  $("#rp-grid", dlg).innerHTML = repGrid();
  $("#rp-date", dlg).textContent = t("print.weekStart", { date: parseISO(repFirst(REP.week)).toLocaleDateString(loc(), { day: "numeric", month: "long" }) });
  $$(".rp-w", dlg).forEach(l => l.classList.toggle("on", l.querySelector("input").value === REP.week));
  repSync();
}

// Bouton « ✍️ Reporter la semaine » (Routines, Parent) : l'incitation Premium s'ouvre en gratuit et rien n'est lu (CA1)
A.reportWeek = () => {
  if (needPremium("report")) return;
  if (S.children.length === 1) return repOpen(S.children[0].id);
  const cur = curChild().id;
  openSheet(`<h2 id="rp-pick">${t("report.pickChild")}</h2>
    <ul class="tpl" role="radiogroup" aria-labelledby="rp-pick">${S.children.map(c => `<li><label><input type="radio" name="rp-child" value="${c.id}" ${c.id === cur ? "checked" : ""}> ${esc(c.emoji)} ${esc(c.name)}</label></li>`).join("")}</ul>
    <div class="sheet-actions"><button class="btn ghost" data-act="closeSheet">${t("btn.cancel")}</button><button class="btn" data-act="repPick">${t("report.continue")}</button></div>`);
};
A.repPick = () => { const v = $("input[name=rp-child]:checked", dlg); if (v) repOpen(v.value); };
A.repWeek = el => { if (!el.checked || el.value === REP.week) return; REP.week = el.value; repWeekDraw(); };
A.repToggle = el => {
  const marks = REP.marks[REP.week], k = repKey(el.dataset.r, el.dataset.d), on = !marks.has(k);
  if (el.dataset.d > todayISO()) return;   // jour à venir : le serveur le refuse (SF:scan_day), l'écran ne le propose pas
  if (on) marks.add(k); else marks.delete(k);
  const r = S.routines.find(x => x.id === el.dataset.r), dow = dowOf(el.dataset.d);
  el.classList.toggle("on", on); el.setAttribute("aria-pressed", String(on));
  el.setAttribute("aria-label", repLabel(r, dow, repState(on, false)));
  el.querySelector(".rp-dot").textContent = on ? "✓" : "";
  repSync();
};
A.repGo = async () => {
  const key = REP.week, marks = REP.marks[key];
  if (REP.busy || !marks.size) return;
  if (!navigator.onLine) return toast(t("report.offline"), true);
  const childId = REP.child, items = [...marks].map(k => { const [routine, day] = k.split("|"); return { routine, day }; });
  REP.busy = true; repSync();
  let res;
  try { res = await mutate(() => sb.rpc("report_sheet", { p_child: childId, p_week_start: repFirst(key), p_items: items })); }
  finally { REP.busy = false; repSync(); }
  repResult(childId, Array.isArray(res) ? res : []);
  refreshParts(["x", "s", "g"]).then(render).catch(() => {});   // coches, compteurs et jardin ; badges en arrière-plan
};
// Résultat : « {n} coches reportées. » ; les éléments non reportés (déjà faits, pas prévus, routine supprimée) sont listés en texte
function repResult(childId, list) {
  const done = list.filter(x => x.status === "reported" || x.status === "validated").length;
  const msg = t("report.done", { n: done });
  const notes = list.filter(x => x.status === "already_done" || x.status === "not_due" || x.status === "stopped");
  if (!notes.length) { closeSheet(); return toast(msg); }
  const why = { already_done: t("report.sAlready"), not_due: t("report.sNotDue"), stopped: t("routine.deleted") };
  const c = S.children.find(k => k.id === childId);
  openSheet(`<h2 id="rp-title" tabindex="-1">${c ? esc(c.emoji) + " " + esc(c.name) : ""}</h2><p role="status">${msg}</p>
    <ul class="hist">${notes.map(x => { const r = S.routines.find(q => q.id === x.routine); return `<li><span>${r ? esc(r.emoji) + " " + esc(r.title) : t("routine.deleted")}</span><span class="muted">${fmtDate(x.day)}${t("sep")}${why[x.status]}</span></li>`; }).join("")}</ul>
    <div class="sheet-actions"><button class="btn" data-act="closeSheet">${t("btn.close")}</button></div>`);
  const h = $("#rp-title", dlg); if (h) h.focus();
}
