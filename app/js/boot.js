"use strict";
/* SoisFier : Démarrage */
/* ================= Démarrage ================= */
window.addEventListener("online", () => { flushQueue(); if (S.screen === "parent" && S.offline) enterParent(); });
document.addEventListener("visibilitychange", () => {
  if (document.visibilityState !== "visible") return;
  if (S.screen === "child") { flushQueue().then(loadChild); }
  else if (S.screen === "parent" && S.family) { if (S.day > todayISO()) S.day = todayISO(); refreshParent().then(render).catch(() => {}); }
});
if (sb) sb.auth.onAuthStateChange((event, session) => {
  if (event === "PASSWORD_RECOVERY") {
    S.session = session;
    setTimeout(async () => {
      await I18N.ready;
      openSheet(`<h2>${t("auth.newPassword")}</h2><label class="f">${t("auth.passwordMin")}<input id="np" type="password" minlength="6" autocomplete="new-password"></label><div class="sheet-actions"><button class="btn" data-act="savePass">${t("btn.save")}</button></div>`);
    }, 300);
  }
});
A.savePass = async () => {
  const p = $("#np").value; if (p.length < 6) return toast(t("auth.min6"), true);
  const { error } = await sb.auth.updateUser({ password: p }); if (error) throw error;
  closeSheet(); toast(t("auth.passwordChanged")); await enterParent();
};

async function boot() {
  if ("serviceWorker" in navigator) navigator.serviceWorker.register("sw.js").catch(() => {});
  await loadI18n();
  if (!sb) { S.screen = "error"; S.err = CFG_OK ? t("error.noService") : t("error.noConfig"); return render(); }
  if (store.get("childToken")) {
    S.screen = "child"; S.cs = store.get("childCache"); render();
    await flushQueue(); await loadChild(); return;
  }
  const { data } = await sb.auth.getSession();
  S.session = data.session;
  if (!S.session) { S.screen = "auth"; return render(); }
  await enterParent();
}
boot();
