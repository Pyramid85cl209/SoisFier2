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

// Mise à jour (v28c) : vérifiée à l'ouverture et à chaque retour dans l'app ; quand la nouvelle version prend la main,
// l'app se recharge une fois (après la fermeture d'une fenêtre ouverte, pour ne rien perdre d'une saisie ou d'un défi chrono).
function swSetup() {
  if (!("serviceWorker" in navigator)) return;
  const sw = navigator.serviceWorker, had = !!sw.controller;
  let reloading = false;
  const askVersion = () => { if (sw.controller) sw.controller.postMessage("version"); };
  sw.addEventListener("message", e => { if (e.data && e.data.version) { S.version = e.data.version.replace(/^(apercu-)?soisfier-/, ""); if (S.screen === "parent" && S.tab === "family") render(); } });
  sw.addEventListener("controllerchange", () => {
    if (!had) return askVersion();   // première installation : rien à recharger
    if (reloading) return; reloading = true;
    const go = () => { if (dlg.open) return dlg.addEventListener("close", () => setTimeout(go, 50), { once: true }); location.reload(); };
    go();
  });
  sw.register("sw.js", { updateViaCache: "none" }).then(reg => {
    const check = () => reg.update().catch(() => {});
    check();
    document.addEventListener("visibilitychange", () => { if (document.visibilityState === "visible") check(); });
  }).catch(() => {});
  askVersion();
}
async function boot() {
  swSetup();
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
