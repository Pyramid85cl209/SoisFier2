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
};

// Aujourd'hui (parent)
A.pToggle = async el => {
  const childId = el.dataset.child, rid = el.dataset.id, day = S.day;
  const cur = S.completions.find(c => c.routine_id === rid && c.day === day);
  if (!cur) {
    S.completions.push({ child_id: childId, routine_id: rid, day, stars: 0, source: "parent", validated_at: new Date().toISOString() }); render(); celebrate(false);
    const { error } = await sb.from("completions").insert({ family_id: S.family.id, child_id: childId, routine_id: rid, day, source: "parent" });
    if (error && error.code !== "23505") throw error;
  } else if (!cur.validated_at) {
    return A.validateOne({ dataset: { id: rid, day } });
  } else if (Date.now() - new Date(cur.validated_at).getTime() < 5 * 60 * 1000) {
    S.completions = S.completions.filter(c => c !== cur); render();
    const { error } = await sb.from("completions").delete().eq("routine_id", rid).eq("day", day); if (error) throw error;
    toast(t("routine.unchecked"));
  } else {
    return toast(t("routine.alreadyValidated"), true);
  }
  await reloadParent(null, ["x", "s"]);
};
A.validateOne = async el => {
  const { id, day } = el.dataset;
  const { error } = await sb.from("completions").update({ validated_at: new Date().toISOString() }).eq("routine_id", id).eq("day", day).is("validated_at", null);
  if (error) throw error; celebrate(false); await reloadParent(t("validate.done"), ["x", "s"]);
};
A.refuseOne = async el => {
  const { id, day } = el.dataset;
  const { error } = await sb.from("completions").delete().eq("routine_id", id).eq("day", day).is("validated_at", null);
  if (error) throw error; await reloadParent(t("validate.refused"), ["x", "s"]);
};
A.validateAll = async () => {
  const { error } = await sb.from("completions").update({ validated_at: new Date().toISOString() }).eq("family_id", S.family.id).is("validated_at", null);
  if (error) throw error; celebrate(true); await reloadParent(t("validate.allDone"), ["x", "s"]);
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
A.newPause = () => {
  const td = todayISO();
  openSheet(`<h2>${t("pause.new")}</h2><p class="muted">${t("pause.during")}</p>
    <div class="f"><span>${t("family.children")}</span><ul class="tpl">${S.children.map(c => `<li><label><input type="checkbox" value="${c.id}" checked> ${esc(c.emoji)} ${esc(c.name)}</label></li>`).join("")}</ul></div>
    <div class="f two"><label>${t("pause.from")}<input type="date" id="pz-from" value="${td}"></label><label>${t("pause.to")}<input type="date" id="pz-to" value="${addDays(td, 6)}"></label></div>
    <label class="f">${t("pause.reason")}<select id="pz-why">${t("pause.reasons").map(r => `<option>${r}</option>`).join("")}</select></label>
    <div class="sheet-actions"><button class="btn" data-act="savePause">${t("btn.save")}</button></div>`);
};
A.savePause = async () => {
  const ids = $$(".tpl input:checked", dlg).map(i => i.value), a = $("#pz-from").value, b = $("#pz-to").value;
  if (!ids.length) return toast(t("pause.needChild"), true);
  if (!a || !b || b < a) return toast(t("pause.badDates"), true);
  const { error } = await sb.from("pauses").insert(ids.map(id => ({ family_id: S.family.id, child_id: id, start_day: a, end_day: b, reason: $("#pz-why").value })));
  if (error) throw error; closeSheet(); await reloadParent(t("pause.saved"), ["pz"]);
};
A.delPause = async el => {
  if (!await confirmSheet(t("pause.delTitle"), t("pause.delText"), t("btn.delete"), true)) return;
  const { error } = await sb.from("pauses").delete().eq("id", el.dataset.id); if (error) throw error;
  await reloadParent(t("pause.deleted"), ["pz"]);
};
