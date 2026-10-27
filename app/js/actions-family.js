"use strict";
/* SoisFier : Actions : mode enfant, rappels, famille et réglages */
// Mode enfant
A.cToggle = el => { const rid = el.dataset.id, day = todayISO(); const done = S.cs.completions.some(c => c.routine_id === rid && c.day === day); childToggle(rid, !done); };
A.cRedeem = async el => {
  const w = S.cs.rewards.find(x => x.id === el.dataset.id);
  if (!await confirmSheet(`${w.emoji} ${w.title}`, t("kid.exchangeConfirm", { n: w.cost }), t("kid.yesChoose"))) return;
  await flushQueue();
  const { error } = await sb.rpc("child_redeem", { p_token: store.get("childToken"), p_reward: w.id });
  if (error) { if (isNetErr(error)) return toast(t("kid.needInternet"), true); throw error; }
  celebrate(true); await loadChild();
  openSheet(`<h2>${t("kid.bravo")} ${esc(w.emoji)}</h2><p>${t("kid.showParents", { title: esc(w.title) })}</p><div class="sheet-actions"><button class="btn" data-act="closeSheet">${t("kid.super")}</button></div>`);
};
A.cTimer = el => {
  const r = S.cs.routines.find(x => x.id === el.dataset.id); const total = r.timer_minutes * 60; let left = total; let iv;
  const C = 2 * Math.PI * 92;
  openSheet(`<div class="timer"><h2>${esc(r.emoji)} ${esc(r.title)}</h2><p>${t("timer.go")}</p>
    <svg viewBox="0 0 220 220" aria-hidden="true"><circle cx="110" cy="110" r="92" fill="none" stroke="var(--line)" stroke-width="18"/>
    <circle id="tc" cx="110" cy="110" r="92" fill="none" stroke="var(--sun)" stroke-width="18" stroke-linecap="round" transform="rotate(-90 110 110)" stroke-dasharray="${C}" stroke-dashoffset="0"/></svg>
    <div class="tleft" id="tl" role="timer">${Math.floor(left / 60)}:${pad(left % 60)}</div>
    <div class="sheet-actions" style="justify-content:center"><button class="btn ghost" id="t-stop">${t("timer.stop")}</button><button class="btn" id="t-done">${t("timer.done")}</button></div></div>`);
  const stop = () => clearInterval(iv);
  iv = setInterval(() => {
    left--; const tl = $("#tl"), tc = $("#tc"); if (!tl) return stop();
    tl.textContent = `${Math.floor(Math.max(left, 0) / 60)}:${pad(Math.max(left, 0) % 60)}`;
    tc.setAttribute("stroke-dashoffset", (C * (1 - Math.max(left, 0) / total)).toFixed(1));
    if (left <= 0) { stop(); tl.textContent = t("timer.over"); $("#t-done").textContent = t("timer.doneAnyway"); if (navigator.vibrate) navigator.vibrate([200, 100, 200]); }
  }, 1000);
  $("#t-stop").onclick = () => { stop(); closeSheet(); };
  $("#t-done").onclick = () => { stop(); closeSheet(); childToggle(r.id, true, left > 0 ? "timer" : "child"); if (left > 0) toast(t("timer.success")); };
  dlg.addEventListener("close", stop, { once: true });
};
A.sound = el => store.set("sound", el.checked);

// Rappels
// Fenêtre « Mes rappels » de l'enfant (v28) ; ask : proposée une fois juste après la connexion du téléphone
A.cReminders = el => {
  const ask = el && el.ask, pushOn = store.get("cpushOn", false), ct = store.get("cpushTimes", ["07:30", "18:00"]);
  openSheet(`<div id="rem-sheet"><h2>🔔 ${t("kid.reminders")}</h2><p class="muted">${ask ? t("kid.remindersAsk") : t("kid.remindersHelp")}</p>
    <div class="f two"><label>${t("kid.remindMorning")}<input type="time" id="t1" value="${esc(ct[0] || "")}"></label><label>${t("kid.remindEvening")}<input type="time" id="t2" value="${esc(ct[1] || "")}"></label></div>
    ${ask ? "" : `<label class="check"><input type="checkbox" id="snd" data-act="sound" ${store.get("sound", true) ? "checked" : ""}> ${t("kid.sound")}</label>`}
    <div class="sheet-actions">${ask ? `<button class="btn ghost" data-act="closeSheet">${t("kid.later")}</button>` : pushOn ? `<button class="btn ghost" data-act="pushOff">${t("btn.disable")}</button>` : ""}<button class="btn" data-act="pushChild">${pushOn ? t("push.update") : t("push.enable")}</button></div></div>`);
};

A.pushParent = async () => {
  const times = readTimes(); if (!times.length) return toast(t("push.needTime"), true);
  const j = await getPushSub();
  const { error } = await sb.rpc("parent_push_subscribe", { p_family: S.family.id, p_endpoint: j.endpoint, p_p256dh: j.keys.p256dh, p_auth: j.keys.auth, p_times: times, p_locale: curLang() }); if (error) throw error;
  store.set("pushOn", true); store.set("pushTimes", times); render(); toast(t("push.enabled"));
};
A.pushChild = async () => {
  const times = readTimes(); if (!times.length) return toast(t("push.needTime"), true);
  const j = await getPushSub();
  const { error } = await sb.rpc("child_push_subscribe", { p_token: store.get("childToken"), p_endpoint: j.endpoint, p_p256dh: j.keys.p256dh, p_auth: j.keys.auth, p_times: times, p_locale: curLang() }); if (error) throw error;
  store.set("cpushOn", true); store.set("cpushTimes", times); render(); closeSheet(); toast(t("push.enabled"));
};
A.pushOff = async () => {
  const reg = await navigator.serviceWorker.ready; const sub = await reg.pushManager.getSubscription();
  if (sub) { await sb.rpc("push_unsubscribe", { p_endpoint: sub.endpoint }); await sub.unsubscribe(); }
  store.set(S.screen === "child" ? "cpushOn" : "pushOn", false); render(); if ($("#rem-sheet")) A.cReminders(); toast(t("push.disabled"));
};

// Famille et réglages
A.invite = () => {
  if (!isPremium() && S.members.filter(m => m.role !== "helper").length >= 2) return upsell("adults");
  openSheet(`<h2>${t("family.invite")}</h2>${relationField(RELATIONS()[1], "inv")}
    <div class="f"><span>${t("member.rights")}</span><div class="seg" role="radiogroup"><button type="button" role="radio" aria-checked="true" class="on" data-act="seg" data-group="role" data-v="parent">${t("role.parent")}</button><button type="button" role="radio" aria-checked="false" data-act="seg" data-group="role" data-v="helper">${t("role.helper")}${ptag()}</button></div></div>
    <div class="sheet-actions"><button class="btn" data-act="makeInvite">${t("member.makeCode")}</button></div>`, S.form = { role: "parent" });
};
A.makeInvite = async () => {
  const rel = readRelation("inv"), role = S.form.role || "parent";
  if (role === "helper" && needPremium("helpers")) return;
  const { data, error } = await sb.rpc("create_invite", { p_family: S.family.id, p_relation: rel, p_role: role }); if (error) throw error;
  openSheet(`<h2>${t("member.inviteWho", { who: esc(rel || t("member.aMemberLower")) })}</h2><div class="code">${esc(data)}</div><p>${t("member.inviteHelp", { who: esc(rel || t("member.thePerson")), role: lower(role === "helper" ? t("role.helper") : t("role.parent")) })}</p>
    <div class="sheet-actions">${navigator.share ? `<button class="btn ghost" data-act="shareInvite" data-code="${esc(data)}">${t("btn.share")}</button>` : ""}<button class="btn" data-act="closeSheet">${t("btn.done")}</button></div>`);
};
A.editMember = el => {
  const m = S.members.find(x => x.user_id === el.dataset.id), self = m.user_id === S.session?.user.id;
  S.form = { role: m.role };
  openSheet(`<h2>${esc(m.relation || m.display_name || t("member.member"))}</h2>${relationField(m.relation, "mem")}
    ${isParent() && !self ? `<div class="f"><span>${t("member.rights")}</span><div class="seg" role="radiogroup">${[["parent", t("role.parent")], ["helper", t("role.helper")]].map(([k, l]) => `<button type="button" role="radio" aria-checked="${m.role === k}" class="${m.role === k ? "on" : ""}" data-act="seg" data-group="role" data-v="${k}">${l}</button>`).join("")}</div></div>` : ""}
    <div class="sheet-actions">${isParent() && !self ? `<button class="btn danger ghost" data-act="removeMember" data-id="${m.user_id}">${t("member.remove")}</button>` : ""}<button class="btn" data-act="saveMember" data-id="${m.user_id}">${t("btn.save")}</button></div>`);
};
A.saveMember = async el => {
  const id = el.dataset.id, self = id === S.session?.user.id, row = { relation: readRelation("mem") };
  if (isParent() && !self) row.role = S.form.role;
  await mutate(() => sb.from("family_members").update(row).eq("family_id", S.family.id).eq("user_id", id));
  S.members = S.members.map(m => m.user_id === id ? { ...m, ...row } : m); if (self) S.me = { ...S.me, ...row };
  closeSheet(); saveParentCache(); render(); toast(t("member.saved"));
  refreshParts(["m"]).then(render).catch(() => {});
};
A.removeMember = async el => {
  const m = S.members.find(x => x.user_id === el.dataset.id);
  if (!await confirmSheet(t("member.removeTitle", { who: m.relation || m.display_name || t("member.thisMember") }), t("member.removeText"), t("member.removeBtn"), true)) return;
  await mutate(() => sb.from("family_members").delete().eq("family_id", S.family.id).eq("user_id", m.user_id));
  S.members = S.members.filter(x => x.user_id !== m.user_id); saveParentCache(); render(); toast(t("member.removed"));
  refreshParts(["m"]).then(render).catch(() => {});
};
A.shareInvite = async el => { try { await navigator.share({ title: "SoisFier", text: t("member.shareText", { code: el.dataset.code, url: location.origin + location.pathname }) }); } catch {} };
A.setPin = async () => {
  const p = await pinSheet(t("pin.title"), t("pin.chooseText"));
  if (p === null) return; if (!/^\d{4}$/.test(p)) return toast(t("pin.need4"), true);
  store.set("pin", p); render(); toast(t("pin.saved"));
};
A.renameFamily = async () => {
  openSheet(`<h2>${t("account.rename")}</h2><label class="f">${t("form.name")}<input id="fam-name" maxlength="40" value="${esc(S.family.name)}"></label><div class="sheet-actions"><button class="btn" data-act="saveFamilyName">${t("btn.save")}</button></div>`);
};
A.saveFamilyName = async () => {
  const name = $("#fam-name").value.trim(); if (!name) return toast(t("account.needName"), true);
  const { error } = await sb.from("families").update({ name }).eq("id", S.family.id); if (error) throw error;
  S.family.name = name; closeSheet(); render(); toast(t("account.nameSaved"));
};
A.editWeek = el => weekForm(el.dataset.mode || "family");
A.saveWeek = async () => {
  const w = { start: +$("#wk-start").value, weekend: $$(".wk-we:checked", dlg).map(i => +i.value).sort((a, b) => a - b), tz: $("#wk-tz").value };
  if (w.weekend.length > 3) return toast(t("week.max3"), true);
  if (S.form.wkMode === "onboard") { S.wk = w; closeSheet(); const o = $("#o-week"); if (o) o.textContent = weekSummary(w); return; }
  await mutate(() => sb.from("families").update({ week_start: w.start, weekend_days: w.weekend, timezone: w.tz }).eq("id", S.family.id));
  // Semaine appliquée tout de suite ; compteurs et jardins (recalculés par le serveur) suivent
  setWeek({ week_start: w.start, weekend_days: w.weekend, timezone: w.tz }); S.family.week = { ...WEEK };
  closeSheet(); saveParentCache(); render(); toast(t("week.saved"));
  refreshParts(["f", "s", "g"]).then(render).catch(() => {});
};
A.printPlan = () => {
  if (S.children.length === 1) return printPlanning([S.children[0].id]);
  openSheet(`<h2>${t("print.title")}</h2><ul class="tpl">${S.children.map(c => `<li><label><input type="checkbox" value="${c.id}" checked> ${esc(c.emoji)} ${esc(c.name)}</label></li>`).join("")}</ul>
    <div class="sheet-actions"><button class="btn" data-act="doPrint">${t("btn.print")}</button></div>`);
};
A.doPrint = () => { const ids = $$(".tpl input:checked", dlg).map(i => i.value); closeSheet(); if (ids.length) printPlanning(ids); };
A.exportData = async () => {
  const fid = S.family.id;
  const names = ["children", "routines", "rewards", "completions", "redemptions", "penalties", "penalty_events", "child_badges", "flowers", "pauses"];
  const res = await Promise.all(names.map(t => sb.from(t).select("*").eq("family_id", fid)));
  for (const q of res) if (q.error) throw q.error;
  const out = { exported_at: new Date().toISOString(), family: S.family }; names.forEach((n, i) => out[n] = res[i].data);
  const blob = new Blob([JSON.stringify(out, null, 2)], { type: "application/json" });
  const a = document.createElement("a"); a.href = URL.createObjectURL(blob); a.download = `soisfier-${todayISO()}.json`; document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(a.href), 5000); toast(t("backup.done"));
};
