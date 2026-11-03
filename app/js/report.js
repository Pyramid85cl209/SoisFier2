"use strict";
/* SoisFier : Report de la semaine (EP-13, F04-09, R04-11).
   Grille à toucher : le Parent choisit l'enfant (« Saisir sans photo ») ou le scan le désigne (scan.js), choisit la semaine (en cours ou
   précédente), touche les ronds cochés sur la feuille papier, puis « Reporter » envoie tout en un seul appel à public.report_sheet
   (le serveur contrôle Parent, Premium, semaine, jour, routine due ; rien n'est enregistré avant). Depuis la v31 (V2) : grille
   pré-remplie par le scan (coches lues, cases incertaines, lignes arrêtées) ; routine déjà validée ce jour-là affichée « déjà faite »
   (DEC-13) ; une coche de l'enfant en attente reste un rond normal (DEC-16). */
const REP = { child: null, week: "cur", marks: { cur: new Set(), prev: new Set() }, unsure: { cur: new Set(), prev: new Set() }, scan: null, busy: false };
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
// Coche déjà validée ce jour-là (coches des 62 derniers jours chargées par data.js) : rond plein, désactivé, « déjà faite » (DEC-13)
const repDone = (rid, day) => (S.completions || []).some(c => c.routine_id === rid && c.day === day && c.validated_at);
// Grille pré-remplie par le scan pour une semaine : coches lues sur les jours dus, passés, pas déjà faits ; cases incertaines à part
function repPrefill(key) {
  const sc = REP.scan, marks = new Set(), unsure = new Set(); if (!sc) return { marks, unsure };
  const td = todayISO(), { dates, due, rs } = repRows(REP.child, repFirst(key));
  for (const r of rs) dates.forEach((d, i) => {
    if (!due[i].has(r.id) || d > td || repDone(r.id, d)) return;
    const dow = dowOf(d);
    if (sc.marks.get(r.id)?.has(dow)) marks.add(repKey(r.id, d)); else if (sc.unsure.has(r.id + "|" + dow)) unsure.add(repKey(r.id, d));
  });
  return { marks, unsure };
}

function repGrid() {
  const c = S.children.find(k => k.id === REP.child), first = repFirst(REP.week), { dates, due, rs } = repRows(c.id, first);
  const td = todayISO(), marks = REP.marks[REP.week], unsure = REP.unsure[REP.week], order = weekOrder();
  const body = MOMENTS().map(([k, l, , e]) => {
    const list = rs.filter(r => r.moment === k); if (!list.length) return "";
    return `<h3 class="grp">${e} ${l}</h3>` + list.map(r => `<div class="rp-row"><div class="rp-name">${isHolidayR(r) ? "🏖️ " : ""}${esc(r.emoji)} ${esc(r.title)}</div><div class="rp-cells">${dates.map((d, i) => {
      if (!due[i].has(r.id)) return `<span class="rp-off" aria-hidden="true"></span>`;
      const abbr = `<small aria-hidden="true">${t("days.abbr")[order[i] - 1]}</small>`;
      if (repDone(r.id, d)) return `<button type="button" class="rp-c done" disabled aria-label="${esc(repLabel(r, order[i], "sAlready"))}">${abbr}<span class="rp-dot" aria-hidden="true">✓</span><small class="rp-tx" aria-hidden="true">${t("report.sAlready")}</small></button>`;
      const future = d > td, on = marks.has(repKey(r.id, d)), uns = !on && unsure.has(repKey(r.id, d));
      const label = repLabel(r, order[i], repState(on, future)) + (uns ? t("sep") + t("scan.unsure") : "");
      return `<button type="button" class="rp-c ${on ? "on" : ""} ${uns ? "unsure" : ""}" data-act="repToggle" data-r="${r.id}" data-d="${d}" aria-pressed="${on}" aria-label="${esc(label)}" ${future ? "disabled" : ""}>${abbr}<span class="rp-dot" aria-hidden="true">${on ? "✓" : uns ? "⚠️" : ""}</span></button>`;
    }).join("")}</div></div>`).join("");
  }).join("");
  // Lignes de la feuille dont la routine est arrêtée depuis l'impression : grisées et signalées en texte, jamais reportées (CA15, DEC-12)
  const stopped = (REP.scan?.stopped || []).map(n => `<div class="rp-row rp-stopped"><div class="rp-name">${t("scan.line", { n: fmtNum(n) })}${t("sep")}${t("report.sStopped")}</div></div>`).join("");
  return (unsure.size ? `<p class="rp-warn">⚠️ ${t("scan.unsureNote")}</p>` : "") + (body || `<p class="empty">${t("report.none")}</p>`) + stopped
    + (dates.some(d => d > td) ? `<p class="muted small">${t("report.futureNote")}</p>` : "");
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

function repOpen(childId, scan) {
  REP.child = childId; REP.week = "cur"; REP.scan = scan || null; REP.busy = false;
  const cur = repPrefill("cur"), prev = repPrefill("prev");
  REP.marks = { cur: cur.marks, prev: prev.marks }; REP.unsure = { cur: cur.unsure, prev: prev.unsure };
  const c = S.children.find(k => k.id === childId); if (!c) return;
  const pill = (k, label, on) => `<label class="rp-w ${on ? "on" : ""}"><input type="radio" name="rp-week" value="${k}" data-act="repWeek" class="vh" ${on ? "checked" : ""}>${label}</label>`;
  openSheet(`<h2 id="rp-title" tabindex="-1">${esc(c.emoji)} ${esc(c.name)}</h2>
    <p class="muted small">${t(scan ? "scan.intro" : "report.intro")}</p>
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
  REP.unsure[REP.week].delete(k);   // case incertaine touchée : vérifiée par le Parent
  const r = S.routines.find(x => x.id === el.dataset.r), dow = dowOf(el.dataset.d);
  el.classList.toggle("on", on); el.classList.remove("unsure"); el.setAttribute("aria-pressed", String(on));
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
// Résultat : « {n} coches reportées. » ; les éléments non reportés (déjà faits, pas prévus, routine arrêtée) sont listés en texte
function repResult(childId, list) {
  const done = list.filter(x => x.status === "reported" || x.status === "validated").length;
  const msg = t("report.done", { n: done });
  const notes = list.filter(x => x.status === "already_done" || x.status === "not_due" || x.status === "stopped");
  if (!notes.length) { closeSheet(); return toast(msg); }
  const why = { already_done: t("report.sAlready"), not_due: t("report.sNotDue"), stopped: t("report.sStopped") };
  const c = S.children.find(k => k.id === childId);
  openSheet(`<h2 id="rp-title" tabindex="-1">${c ? esc(c.emoji) + " " + esc(c.name) : ""}</h2><p role="status">${msg}</p>
    <ul class="hist">${notes.map(x => { const r = S.routines.find(q => q.id === x.routine); return `<li><span>${r ? esc(r.emoji) + " " + esc(r.title) : why.stopped}</span><span class="muted">${fmtDate(x.day)}${r ? t("sep") + why[x.status] : ""}</span></li>`; }).join("")}</ul>
    <div class="sheet-actions"><button class="btn" data-act="closeSheet">${t("btn.close")}</button></div>`);
  const h = $("#rp-title", dlg); if (h) h.focus();
}
