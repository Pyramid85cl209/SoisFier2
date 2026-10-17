"use strict";
/* SoisFier : Feuille, dialogues, célébration, rendu, connexion, membres */
/* ================= Feuille / dialogues ================= */
const dlg = $("#sheet");
function openSheet(html) { dlg.innerHTML = `<div class="sheet-in">${html}</div>`; if (!dlg.open) dlg.showModal(); const f = dlg.querySelector("input:not([type=checkbox]),select"); if (f && f.dataset.autofocus !== undefined) f.focus(); }
function closeSheet() { if (dlg.open) dlg.close(); }
dlg.addEventListener("click", e => { if (e.target === dlg) closeSheet(); });
function confirmSheet(title, text, okLabel, danger = false) {
  return new Promise(res => {
    openSheet(`<h2>${esc(title)}</h2><p>${esc(text)}</p><div class="sheet-actions"><button class="btn ghost" id="c-no">${t("btn.cancel")}</button><button class="btn ${danger ? "danger" : ""}" id="c-yes">${esc(okLabel)}</button></div>`);
    $("#c-no").onclick = () => { closeSheet(); res(false); };
    $("#c-yes").onclick = () => { closeSheet(); res(true); };
    dlg.addEventListener("close", () => res(false), { once: true });
  });
}

/* ================= Célébration ================= */
let audioCtx = null;
function chime(big) {
  if (store.get("sound", true) === false) return;
  try {
    audioCtx = audioCtx || new (window.AudioContext || window.webkitAudioContext)();
    const notes = big ? [523, 659, 784, 1047] : [659, 988];
    notes.forEach((f, i) => {
      const o = audioCtx.createOscillator(), g = audioCtx.createGain(), t = audioCtx.currentTime + i * .09;
      o.type = "sine"; o.frequency.value = f; g.gain.setValueAtTime(.0001, t); g.gain.exponentialRampToValueAtTime(.18, t + .02); g.gain.exponentialRampToValueAtTime(.0001, t + .35);
      o.connect(g).connect(audioCtx.destination); o.start(t); o.stop(t + .4);
    });
  } catch {}
}
function celebrate(big = false) {
  chime(big);
  if (navigator.vibrate) navigator.vibrate(big ? [60, 40, 60] : 40);
  if (matchMedia("(prefers-reduced-motion: reduce)").matches) return;
  const c = document.createElement("canvas"); c.id = "confetti"; document.body.appendChild(c);
  const dpr = window.devicePixelRatio || 1; c.width = innerWidth * dpr; c.height = innerHeight * dpr;
  const x = c.getContext("2d"); x.scale(dpr, dpr);
  const cols = ["#FFC233", "#E8484F", "#2E8B57", "#3D7BD9", "#FF8FB1"];
  const P = Array.from({ length: big ? 130 : 55 }, () => ({
    x: innerWidth / 2 + (Math.random() - .5) * 80, y: innerHeight * .45, vx: (Math.random() - .5) * 9, vy: -Math.random() * 11 - 4,
    r: Math.random() * 6 + 4, a: Math.random() * 6, va: (Math.random() - .5) * .3, c: cols[(Math.random() * cols.length) | 0]
  }));
  const t0 = performance.now();
  (function frame(now) {
    const k = (now - t0) / 1600; x.clearRect(0, 0, innerWidth, innerHeight);
    P.forEach(p => { p.vy += .32; p.x += p.vx; p.y += p.vy; p.a += p.va; x.save(); x.translate(p.x, p.y); x.rotate(p.a); x.globalAlpha = Math.max(0, 1 - k); x.fillStyle = p.c; x.beginPath(); x.ellipse(0, 0, p.r, p.r * .55, 0, 0, Math.PI * 2); x.fill(); x.restore(); });
    if (k < 1) requestAnimationFrame(frame); else c.remove();
  })(t0);
}

/* ================= Rendu ================= */
function render() {
  const s = S.screen;
  if (s === "loading") app.innerHTML = `<div class="loading">${plantSVG(1)}</div>`;
  else if (s === "auth") renderAuth();
  else if (s === "pair") renderPair();
  else if (s === "onboard") renderOnboard();
  else if (s === "parent") renderParent();
  else if (s === "child") renderChild();
  else if (s === "error") app.innerHTML = `<main class="wrap"><div class="card center"><h2>${t("error.title")}</h2><p>${esc(S.err)}</p><button class="btn" data-act="reload">${t("btn.retry")}</button></div></main>`;
}

/* ---------- Langue et aide ---------- */
const guideHref = () => curLang() === "fr" ? PATHS.guide : `${PATHS.guide}${curLang()}/`;
const langBtn = () => `<button class="lang-btn" data-act="pickLang" aria-label="${t("lang.title")}">🌐</button>`;
const topButtons = (help = true) => `<div class="help-float">${langBtn()}${help ? `<a class="help" href="${guideHref()}" aria-label="${t("help")}">?</a>` : ""}</div>`;

/* ---------- Connexion ---------- */
let installEvt = null;
window.addEventListener("beforeinstallprompt", e => { e.preventDefault(); installEvt = e; if (S.screen === "auth" || (S.screen === "parent" && S.tab === "family")) render(); });
const installBtn = () => installEvt ? `<button class="btn ghost wide" data-act="install">${t("auth.install")}</button>` : "";
function renderAuth() {
  const m = S.authMode;
  app.innerHTML = `<main class="wrap auth">${topButtons()}
    <div class="auth-hero">${plantSVG(4, "#E8484F", "SoisFier")}<h1>SoisFier</h1><p>${t("auth.tagline")}</p></div>
    <div class="seg wide" role="tablist">
      <button role="tab" aria-selected="${m === "login"}" class="${m === "login" ? "on" : ""}" data-act="authMode" data-v="login">${t("auth.login")}</button>
      <button role="tab" aria-selected="${m === "signup"}" class="${m === "signup" ? "on" : ""}" data-act="authMode" data-v="signup">${t("auth.signup")}</button>
    </div>
    <form class="card" novalidate>
      ${m === "signup" ? `<label class="f">${t("auth.firstName")}<input id="a-name" autocomplete="given-name" maxlength="40"></label>` : ""}
      <label class="f">${t("auth.email")}<input id="a-email" type="email" autocomplete="email" inputmode="email" required></label>
      <label class="f">${t("auth.password")}<input id="a-pass" type="password" minlength="6" autocomplete="${m === "signup" ? "new-password" : "current-password"}" required></label>
      <button class="btn wide" data-act="${m === "signup" ? "signup" : "login"}">${m === "signup" ? t("auth.createAccount") : t("auth.connect")}</button>
      ${m === "login" ? `<p class="center"><button class="link" data-act="forgot">${t("auth.forgot")}</button></p>` : ""}
    </form>
    <div class="card alt"><p>${t("auth.childPhone")}</p><button class="btn ghost wide" data-act="goPair">${t("auth.haveCode")}</button></div>
    ${installBtn()}
  </main>`;
}
function renderPair() {
  app.innerHTML = `<main class="wrap auth">${topButtons(false)}<div class="auth-hero">${plantSVG(0)}<h1>${t("pair.title")}</h1><p>${t("pair.where")}</p></div>
    <form class="card" novalidate><label class="f">${t("pair.code")}<input id="p-code" class="pin" maxlength="6" autocomplete="off" autocapitalize="characters" spellcheck="false"></label>
    <button class="btn wide" data-act="pair">${t("pair.connect")}</button></form>
    <p class="center"><button class="link" data-act="toAuth">${t("btn.back")}</button></p></main>`;
}
function renderOnboard() {
  if (!S.wk) S.wk = detectWeek();
  app.innerHTML = `<main class="wrap auth">${topButtons()}<div class="auth-hero">${plantSVG(1)}<h1>${t("onboard.welcome")}</h1><p>${t("onboard.intro")}</p></div>
    <form class="card" novalidate><h2>${t("onboard.create")}</h2><label class="f">${t("onboard.familyName")}<input id="o-name" placeholder="${t("onboard.familyPlaceholder")}" maxlength="40"></label><label class="f">${t("onboard.iAm")}<select id="o-rel">${RELATIONS().map(r => `<option>${r}</option>`).join("")}</select></label>
    <p class="muted small"><span id="o-week">${esc(weekSummary(S.wk))}</span> <button type="button" class="link" data-act="editWeek" data-mode="onboard">${t("btn.edit")}</button></p>
    <button class="btn wide" data-act="createFamily">${t("btn.create")}</button></form>
    <form class="card" novalidate><h2>${t("onboard.join")}</h2><label class="f">${t("onboard.inviteCode")}<input id="o-code" class="pin" maxlength="6" autocapitalize="characters" autocomplete="off"></label>
    <button class="btn ghost wide" data-act="joinFamily">${t("onboard.joinBtn")}</button></form>
    <p class="center"><button class="link" data-act="logout">${t("btn.logout")}</button></p></main>`;
}

/* ---------- Membres ---------- */
const RELATIONS = () => t("relations");
const isParent = () => !S.me || S.me.role !== "helper";
