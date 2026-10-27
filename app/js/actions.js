"use strict";
/* SoisFier : Actions : navigation, connexion, langue, aujourd'hui, jardin */
/* ================= Actions ================= */
const A = {};
document.addEventListener("submit", e => e.preventDefault());
document.addEventListener("click", async e => {
  const el = e.target.closest("[data-act]"); if (!el) return;
  const fn = A[el.dataset.act]; if (!fn) return;
  if (el.tagName !== "INPUT") e.preventDefault();
  if (el.dataset.busy) return; el.dataset.busy = "1";
  try { await fn(el, e); } catch (err) { console.error(err); toast(errMsg(err), true); }
  finally { delete el.dataset.busy; }
});

// Navigation
A.reload = () => location.reload();
A.upsell = el => upsell(el.dataset.key, el.dataset.n ? { n: +el.dataset.n, year: el.dataset.y } : {});
A.dismissNudge = el => { store.set("nudge:" + el.dataset.k, Date.now()); store.set("nudgeAt", Date.now()); if (el.tagName === "A") location.href = el.getAttribute("href"); else render(); };
A.tab = el => { S.tab = el.dataset.tab; S.reviewing = null; if (el.dataset.child) S.currentChild = el.dataset.child; if (S.tab === "today") S.day = todayISO(); render(); scrollTo(0, 0); };
A.ctab = el => { S.ctab = el.dataset.tab; render(); scrollTo(0, 0); };
A.pickChild = el => { S.currentChild = el.dataset.id; render(); };
A.dayPrev = () => { S.day = addDays(S.day, -1); render(); };
A.dayNext = () => { if (S.day < todayISO()) S.day = addDays(S.day, 1); render(); };
A.install = async () => { if (!installEvt) return; installEvt.prompt(); await installEvt.userChoice; installEvt = null; render(); };

// Connexion
A.authMode = el => { S.authMode = el.dataset.v; render(); };
A.goPair = () => { S.screen = "pair"; render(); };
A.toAuth = () => { S.screen = "auth"; render(); };
A.login = async () => {
  const email = $("#a-email").value.trim(), password = $("#a-pass").value;
  if (!email || !password) return toast(t("auth.needBoth"), true);
  const { data, error } = await sb.auth.signInWithPassword({ email, password }); if (error) throw error;
  S.session = data.session; await enterParent();
};
A.signup = async () => {
  const email = $("#a-email").value.trim(), password = $("#a-pass").value, name = ($("#a-name")?.value || "").trim();
  if (!email || password.length < 6) return toast(t("auth.needSignup"), true);
  const { data, error } = await sb.auth.signUp({ email, password, options: { data: { display_name: name, locale: curLang() }, emailRedirectTo: location.origin + location.pathname } });
  if (error) throw error;
  if (data.session) { S.session = data.session; await enterParent(); }
  else { S.authMode = "login"; render(); openSheet(`<h2>${t("auth.checkMail")}</h2><p>${t("auth.checkMailText", { email: `<b>${esc(email)}</b>` })}</p><div class="sheet-actions"><button class="btn" data-act="closeSheet">${t("btn.gotIt")}</button></div>`); }
};
A.forgot = async () => {
  const email = $("#a-email").value.trim(); if (!email) return toast(t("auth.emailFirst"), true);
  const { error } = await sb.auth.resetPasswordForEmail(email, { redirectTo: location.origin + location.pathname }); if (error) throw error;
  toast(t("auth.resetSent"));
};
A.closeSheet = () => closeSheet();
// Langue : choisie sur l'appareil ; enregistrée aussi pour le membre connecté et pour les rappels de cet appareil
A.pickLang = () => openSheet(`<h2>${t("lang.title")}</h2><ul class="tpl">${LANGS.map(l => `<li><button class="pen" data-act="setLang" data-v="${l}" lang="${l}"><span>${t("lang." + l)}${REVIEW.includes(l) ? ` <small class="muted">(${t("lang.toReview")})</small>` : ""}</span><span>${l === curLang() ? "✓" : ""}</span></button></li>`).join("")}</ul>
  <div class="sheet-actions"><button class="btn ghost" data-act="closeSheet">${t("btn.close")}</button></div>`);
A.setLang = async el => {
  const l = el.dataset.v; if (!LANGS.includes(l)) return;
  store.set("lang", l);
  if (new URLSearchParams(location.search).has("lang")) history.replaceState(null, "", location.pathname);
  await loadI18n(); closeSheet(); render();
  try {
    if (S.screen === "parent" && S.family && S.session) await sb.from("family_members").update({ locale: l }).eq("family_id", S.family.id).eq("user_id", S.session.user.id);
    if ("serviceWorker" in navigator) { const reg = await navigator.serviceWorker.ready; const sub = await reg.pushManager.getSubscription(); if (sub) await sb.rpc("push_set_locale", { p_endpoint: sub.endpoint, p_locale: l }); }
  } catch {}
};
A.logout = async () => {
  if (sb) await sb.auth.signOut().catch(() => {});
  ["parentCache", "pushOn"].forEach(k => store.del(k));
  Object.assign(S, { session: null, family: null, children: [], routines: [], screen: "auth", tab: "today", wk: null }); render();
};
A.createFamily = async () => {
  const name = $("#o-name").value.trim();
  const rel = $("#o-rel").value;
  const w = S.wk || detectWeek();
  const { data: fid, error } = await sb.rpc("create_family", { p_name: name || t("onboard.defaultName"), p_display_name: S.session.user.user_metadata?.display_name || "",
    p_week_start: w.start, p_weekend: w.weekend, p_timezone: w.tz }); if (error) throw error;
  await sb.from("family_members").update({ relation: rel }).eq("family_id", fid).eq("user_id", S.session.user.id);
  await enterParent();
};
A.joinFamily = async () => {
  const code = $("#o-code").value.trim(); if (code.length < 6) return toast(t("pair.need6"), true);
  const { error } = await sb.rpc("join_family", { p_code: code, p_display_name: S.session.user.user_metadata?.display_name || "" }); if (error) throw error;
  await enterParent(); toast(t("onboard.joined"));
};
A.pair = async () => {
  const code = $("#p-code").value.trim(); if (code.length < 6) return toast(t("pair.need6"), true);
  const { data, error } = await sb.rpc("child_pair", { p_code: code, p_label: null }); if (error) throw error;
  store.set("childToken", data.token); store.del("queue"); store.del("pin"); store.del("lastEarned"); store.del("seenFlowers");
  S.screen = "child"; S.ctab = "today"; S.cs = null; render(); await loadChild(); celebrate(true);
  setTimeout(() => { if (S.screen === "child" && !dlg.open) A.cReminders({ ask: true }); }, 1800);   // v28 : rappels proposés une fois, sur le téléphone de l'enfant seulement
};

// Aujourd'hui (parent)
// Coches, validations et refus : écran changé tout de suite (instant), compteurs ajustés localement, retour arrière si le serveur refuse
const isDone = (c, rid, day) => c.routine_id === rid && c.day === day;
const earnStats = c => ({ pending_stars: -c.stars, pending_count: -1, earned: c.stars, done_count: 1 });
A.pToggle = async el => {
  const childId = el.dataset.child, rid = el.dataset.id, day = S.day;
  const cur = S.completions.find(c => isDone(c, rid, day));
  if (!cur) {
    const r = S.routines.find(x => x.id === rid), stars = r ? (effective(r, day) || r).stars : 0, me = S.session?.user.id;
    celebrate(false);
    return instant(() => { S.completions = [...S.completions, { child_id: childId, routine_id: rid, day, stars, source: "parent", validated_at: new Date().toISOString(), validated_by: me, created_by: me }]; bumpStats(childId, { earned: stars, done_count: 1 }); },
      async () => { const res = await sb.from("completions").insert({ family_id: S.family.id, child_id: childId, routine_id: rid, day, source: "parent" }); return res.error && res.error.code === "23505" ? {} : res; },
      ["x", "s"]);
  }
  if (!cur.validated_at) return A.validateOne({ dataset: { id: rid, day } });
  if (Date.now() - new Date(cur.validated_at).getTime() >= 5 * 60 * 1000) return toast(t("routine.alreadyValidated"), true);
  return instant(() => { S.completions = S.completions.filter(c => c !== cur); bumpStats(cur.child_id, { earned: -cur.stars, done_count: -1 }); },
    () => sb.from("completions").delete().eq("routine_id", rid).eq("day", day), ["x", "s"], t("routine.unchecked"));
};
A.validateOne = async el => {
  const { id, day } = el.dataset, now = new Date().toISOString(), me = S.session?.user.id;
  const cur = S.completions.find(c => isDone(c, id, day) && !c.validated_at); if (!cur) return;
  celebrate(false);
  return instant(() => { S.completions = S.completions.map(c => c === cur ? { ...c, validated_at: now, validated_by: me } : c); bumpStats(cur.child_id, earnStats(cur)); },
    () => sb.from("completions").update({ validated_at: now }).eq("routine_id", id).eq("day", day).is("validated_at", null), ["x", "s"], t("validate.done"));
};
A.refuseOne = async el => {
  const { id, day } = el.dataset;
  const cur = S.completions.find(c => isDone(c, id, day) && !c.validated_at); if (!cur) return;
  return instant(() => { S.completions = S.completions.filter(c => c !== cur); bumpStats(cur.child_id, { pending_stars: -cur.stars, pending_count: -1 }); },
    () => sb.from("completions").delete().eq("routine_id", id).eq("day", day).is("validated_at", null), ["x", "s"], t("validate.refused"));
};
A.validateAll = async () => {
  const now = new Date().toISOString(), me = S.session?.user.id, pend = S.completions.filter(c => !c.validated_at); if (!pend.length) return;
  celebrate(true);
  return instant(() => { S.completions = S.completions.map(c => c.validated_at ? c : { ...c, validated_at: now, validated_by: me }); pend.forEach(c => bumpStats(c.child_id, earnStats(c))); },
    () => sb.from("completions").update({ validated_at: now }).eq("family_id", S.family.id).is("validated_at", null), ["x", "s"], t("validate.allDone"));
};
A.toggleAuto = async el => {
  const v = el.checked;
  const { error } = await sb.from("families").update({ auto_validate: v }).eq("id", S.family.id);
  if (error) { el.checked = !v; throw error; }
  S.autoValidate = v; toast(v ? t("validate.autoEnabled") : t("validate.manualOnly"));
};

// Jardin
function bloomCeremony(f) {
  const c = S.cs ? S.cs.child : null;
  const nm = SP[f.species] ? spName(f.species) : t("bloom.yourFlower");
  openSheet(`<div class="center"><h2>${t("bloom.title")}</h2><div style="max-width:220px;margin:0 auto">${stageSVG(13, f.species, c ? c.color : "#E58358", nm, f.grade)}</div>
    <p class="grade">${GRADE_NAME[f.grade]}</p><p>${t("bloom.text", { name: esc(nm), season: SEASON_NAME[f.season] })}</p>
    <div class="sheet-actions" style="justify-content:center"><button class="btn" data-act="closeSheet">${t("bloom.see")}</button></div></div>`);
  celebrate(f.grade >= 2); S.ctab = "garden"; render();
}
// Badges en plus avec le Premium (côté parent uniquement)
function badgeTeaser(c) {
  if (isPremium()) return "";
  const v = viewFor(c), free = BADGES.filter(b => FREE_BADGE(b.k)), got = free.filter(b => hasBadge(v, b)).length, more = BADGES.length - free.length;
  return `<button class="teaser" data-act="upsell" data-key="badges" data-n="${more}"><span aria-hidden="true">🏅</span><span><b>${t("premium.badges.title", { n: more })}</b><small>${t("premium.badgesGot", { n: got, total: free.length, name: esc(c.name) })}</small></span></button>`;
}
A.showGarden = el => {
  const c = S.children.find(k => k.id === el.dataset.id), gd = S.gardens[c.id]; if (!gd) return;
  const n = gardenNow(gd), se = seasonOfISO(gd.today), yr = gardenYearOfISO(gd.today), fl = gd.flowers || [];
  openSheet(`<h2>${t("garden.gardenOf", { name: esc(c.name) })}</h2>
    <div class="scene" style="max-width:240px;margin:0 auto">${stageSVG(n.stage, n.species, c.color)}<p>${n.waiting ? t("garden.firstFromDot", { date: fmtLong(n.start) }) : t("garden.status", { stage: STAGE_NAME[n.stage], d: n.dayIdx, len: n.len, n: n.good, date: fmtLong(n.end) })}</p></div>
    ${dots14(gd)}
    <h3 class="grp">${t("garden.bedOf", { season: SEASON_NAME[se] })}</h3><div class="scene">${parterreSVG(se, fl.filter(f => f.season === se && f.garden_year === yr), true)}</div>
    ${isPremium() ? `<h3 class="grp">${t("garden.gardenYear", { year: yr })}</h3><div class="scene">${gardenSVG(c.name, yr, fl.filter(f => f.garden_year === yr), { season: se })}</div>`
      : `<button class="teaser" data-act="upsell" data-key="garden" data-n="${fl.filter(f => f.garden_year === yr).length}" data-y="${esc(yr)}"><span aria-hidden="true">🏞️</span><span><b>${t("premium.garden.title", { n: fl.filter(f => f.garden_year === yr).length, year: yr })}</b><small>${t("premium.tag")}</small></span></button>`}
    ${badgeTeaser(c)}
    <div class="sheet-actions"><button class="btn" data-act="closeSheet">${t("btn.close")}</button></div>`);
};
A.showYear = el => {
  const y = el.dataset.y, fl = (S.cs.garden.flowers || []).filter(f => f.garden_year === y);
  openSheet(`<h2>${t("kid.myGarden", { year: esc(y) })}</h2><div class="scene">${gardenSVG(S.cs.child.name, y, fl, null)}</div><p>${t("garden.yearCount", { n: fl.length, big: fl.filter(f => f.grade === 3).length })}</p><div class="sheet-actions"><button class="btn" data-act="closeSheet">${t("btn.close")}</button></div>`);
};
/* Pauses (v27) : modifiables comme une période. Une pause commencée (premier jour passé) et créée il y a plus
   de 24 h ne se supprime plus : son premier jour est figé, « Arrêter » fixe son dernier jour à hier.
   Même règle côté serveur (déclencheur pauses_check, code SF:pause_started). */
const pauseGrace = p => !p.created_at || Date.now() - Date.parse(p.created_at) < 864e5;
const pauseLocked = p => p.start_day < todayISO() && !pauseGrace(p);
const reasonSelect = cur => `<label class="f">${t("pause.reason")}<select id="pz-why">${PAUSE_REASONS.map(k => `<option value="${k}" ${k === cur ? "selected" : ""}>${t("pause.r." + k)}</option>`).join("")}${cur && !PAUSE_REASONS.includes(cur) ? `<option value="${esc(cur)}" selected>${esc(cur)}</option>` : ""}</select></label>`;
A.cAnyway = () => { S.kidAnyway = todayISO(); render(); };
A.newPause = () => {
  const td = todayISO();
  openSheet(`<h2>⏸️ ${t("pause.new")}</h2><p class="muted">${t("pause.during")}</p>
    <div class="f"><span>${t("family.children")}</span><ul class="tpl">${S.children.map(c => `<li><label><input type="checkbox" value="${c.id}" checked> ${esc(c.emoji)} ${esc(c.name)}</label></li>`).join("")}</ul></div>
    <div class="f two"><label>${t("pause.from")}<input type="date" id="pz-from" value="${td}"></label><label>${t("pause.to")}<input type="date" id="pz-to" value="${addDays(td, 6)}"></label></div>
    ${reasonSelect("sick")}
    <div class="sheet-actions"><button class="btn" data-act="savePause">${t("btn.save")}</button></div>`);
};
A.savePause = async () => {
  const ids = $$(".tpl input:checked", dlg).map(i => i.value), a = $("#pz-from").value, b = $("#pz-to").value;
  if (!ids.length) return toast(t("pause.needChild"), true);
  if (!a || !b || b < a) return toast(t("pause.badDates"), true);
  const { error } = await sb.from("pauses").insert(ids.map(id => ({ family_id: S.family.id, child_id: id, start_day: a, end_day: b, reason: $("#pz-why").value })));
  if (error) throw error; closeSheet(); await reloadParent(t("pause.saved"), ["pz"]);
};
// Modifier : dates (premier jour figé si la pause est verrouillée) et motif ; arrêter ou supprimer
A.editPause = el => {
  const p = (S.pauses || []).find(x => x.id === el.dataset.id); if (!p) return;
  const c = S.children.find(k => k.id === p.child_id) || { emoji: "", name: "" }, td = todayISO(), locked = pauseLocked(p);
  const help = locked ? t("pause.lockedHelp") : p.start_day < td ? t("pause.graceHelp") : "";
  openSheet(`<h2>⏸️ ${t("pause.edit")}</h2><p class="muted">${esc(c.emoji + " " + c.name)}${t("sep")}${t("pause.state." + holState(p))}</p>
    ${help ? `<p class="muted small">${help}</p>` : ""}
    <div class="f two"><label>${t("pause.from")}<input type="date" id="pz-from" value="${p.start_day}" ${locked ? "disabled" : ""}></label><label>${t("pause.to")}<input type="date" id="pz-to" value="${p.end_day}" ${locked ? `min="${addDays(td, -1)}"` : ""}></label></div>
    ${reasonSelect(p.reason)}
    <div class="actions"><button class="btn sm ghost danger" data-act="${locked ? "stopPause" : "delPause"}" data-id="${p.id}">${locked ? t("pause.stop") : t("btn.delete")}</button></div>
    <div class="sheet-actions"><button class="btn" data-act="savePauseEdit" data-id="${p.id}">${t("btn.save")}</button></div>`);
};
A.savePauseEdit = async el => {
  const p = (S.pauses || []).find(x => x.id === el.dataset.id); if (!p) return closeSheet();
  const locked = pauseLocked(p), a = locked ? p.start_day : $("#pz-from").value, b = $("#pz-to").value;
  if (!a || !b || b < a) return toast(t("pause.badDates"), true);
  if (locked && b < addDays(todayISO(), -1) && b < p.end_day) return toast(t("pause.endTooEarly"), true);
  const { error } = await sb.from("pauses").update({ start_day: a, end_day: b, reason: $("#pz-why").value }).eq("id", p.id);
  if (error) throw error; closeSheet(); await reloadParent(t("pause.saved"), ["pz"]);
};
// Arrêter : dernier jour = hier ; les jours déjà en pause restent neutres
A.stopPause = async el => {
  const p = (S.pauses || []).find(x => x.id === el.dataset.id); if (!p) return;
  const c = S.children.find(k => k.id === p.child_id) || { name: "" }, y = addDays(todayISO(), -1);
  if (!await confirmSheet(t("pause.stopTitle"), t("pause.stopText", { name: c.name, date: fmtLong(y) }), t("pause.stop"), true)) return A.editPause(el);
  const { error } = await sb.from("pauses").update({ end_day: y }).eq("id", p.id); if (error) throw error;
  await reloadParent(t("pause.stopped"), ["pz"]);
};
A.delPause = async el => {
  if (!await confirmSheet(t("pause.delTitle"), t("pause.delText"), t("btn.delete"), true)) return A.editPause(el);
  const { error } = await sb.from("pauses").delete().eq("id", el.dataset.id); if (error) throw error;
  await reloadParent(t("pause.deleted"), ["pz"]);
};
