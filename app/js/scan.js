"use strict";
/* SoisFier : Scanner une feuille (EP-13 V2, F04-09, R04-11, ADR-29).
   Le Parent photographie la feuille imprimée (caméra arrière dans l'application, ou « Choisir une photo » sans capture) ;
   tout est lu sur le téléphone, rien n'est envoyé ni écrit (DEC-03, CA13) :
   1. QR (BarcodeDetector s'il existe, sinon jsQR) : format 2 (texte en base 32) ; un texte qui n'est pas au format 2 est relu
      sur la même image par jsQR, qui rend les octets exacts (format 1, feuilles imprimées depuis la v30) ;
   2. empreintes comparées à la famille ouverte et à ses enfants (crypto.subtle) : l'enfant est celui du repère ;
   3. redressement par les 4 carrés d'angle (homographie), lignes du tableau retrouvées par projection ;
   4. part d'encre de chaque case, seuil calibré sur la feuille : coché, vide ou incertain ;
   5. la grille de report.js s'ouvre pré-remplie ; la photo (image, canevas) est oubliée.
   Feuille sur deux pages, sans repère, d'une autre famille ou illisible : « Feuille non reconnue. » (CA8, DEC-15). */
const SCAN = { stream: null, busy: false };

/* ---------- Bibliothèque jsQR : chargée à la première lecture seulement (dans CORE, donc disponible hors ligne) ---------- */
let jsqrLoad = null;
function loadJsQR() {
  if (typeof jsQR === "function") return Promise.resolve();
  return jsqrLoad || (jsqrLoad = new Promise((ok, ko) => {
    const s = document.createElement("script"); s.src = "vendor/jsqr.min.js";
    s.onload = () => ok(); s.onerror = () => { jsqrLoad = null; ko(new Error("jsqr")); };
    document.head.appendChild(s);
  }));
}

/* ---------- Repère : texte ou octets → contenu ---------- */
const B32 = "0123456789ABCDEFGHIJKLMNOPQRSTUV";
function scanB32(text) {
  const out = []; let acc = 0, bits = 0;
  for (const ch of text) { acc = (acc << 5) | B32.indexOf(ch); bits += 5; if (bits >= 8) { bits -= 8; out.push((acc >> bits) & 255); acc &= (1 << bits) - 1; } }
  return out;
}
// Octets du repère (formats 1 et 2) : format, famille (6), enfant (4), sens et langue, premier jour, nombre de lignes, lignes (4 chacune)
function scanParse(bytes) {
  if (!bytes || bytes.length < 14 || (bytes[0] !== 1 && bytes[0] !== 2)) return null;
  const n = bytes[13];
  if (bytes.length < 14 + 4 * n || bytes[12] < 1 || bytes[12] > 7) return null;
  const lines = []; for (let i = 0; i < n; i++) lines.push(bytes.slice(14 + 4 * i, 18 + 4 * i));
  return { format: bytes[0], family: bytes.slice(1, 7), child: bytes.slice(7, 11), rtl: !!(bytes[11] & 128), start: bytes[12], lines };
}
const scanIsF2 = s => typeof s === "string" && /^[0-9A-V]{23,}$/.test(s);
const sameBytes = (a, b) => a.length === b.length && a.every((v, i) => v === b[i]);

/* ---------- Image ---------- */
// Copie réduite de l'image dans un canevas (côté le plus long : 1600 px) ; renvoie le canevas et ses pixels
function scanCanvas(src, w, h) {
  const k = Math.min(1, 1600 / Math.max(w, h)), cw = Math.round(w * k), ch = Math.round(h * k);
  const cv = document.createElement("canvas"); cv.width = cw; cv.height = ch;
  const cx = cv.getContext("2d", { willReadFrequently: true }); cx.drawImage(src, 0, 0, cw, ch);
  return { cv, img: cx.getImageData(0, 0, cw, ch) };
}
function lumOf(img) {
  const d = img.data, L = new Float32Array(img.width * img.height);
  for (let i = 0, j = 0; j < L.length; i += 4, j++) L[j] = 0.299 * d[i] + 0.587 * d[i + 1] + 0.114 * d[i + 2];
  return L;
}
// Seuil local (moyenne d'une fenêtre carrée, image intégrale) : 1 = foncé
function binarize(L, w, h, win, k) {
  const I = new Float64Array((w + 1) * (h + 1));
  for (let y = 0; y < h; y++) { let row = 0; for (let x = 0; x < w; x++) { row += L[y * w + x]; I[(y + 1) * (w + 1) + x + 1] = I[y * (w + 1) + x + 1] + row; } }
  const B = new Uint8Array(w * h), r = Math.max(2, win >> 1);
  for (let y = 0; y < h; y++) {
    const y0 = Math.max(0, y - r), y1 = Math.min(h, y + r + 1);
    for (let x = 0; x < w; x++) {
      const x0 = Math.max(0, x - r), x1 = Math.min(w, x + r + 1);
      const m = (I[y1 * (w + 1) + x1] - I[y0 * (w + 1) + x1] - I[y1 * (w + 1) + x0] + I[y0 * (w + 1) + x0]) / ((x1 - x0) * (y1 - y0));
      B[y * w + x] = L[y * w + x] < m * k ? 1 : 0;
    }
  }
  return B;
}

/* ---------- QR ---------- */
async function scanQR(cv, img) {
  let text = null, corners = null;
  if ("BarcodeDetector" in window) {
    try {
      const codes = await new BarcodeDetector({ formats: ["qr_code"] }).detect(cv);
      if (codes[0]) { text = codes[0].rawValue; corners = codes[0].cornerPoints; }
    } catch (e) { /* lecture native indisponible : jsQR */ }
  }
  if (scanIsF2(text)) return { bytes: scanB32(text), corners };
  // Pas de lecture native, rien de lu, ou texte qui n'est pas au format 2 (octets du format 1 perdus) : jsQR sur la même image
  await loadJsQR();
  const r = jsQR(img.data, img.width, img.height, { inversionAttempts: "dontInvert" });
  if (!r) return null;
  const l = r.location;
  return { bytes: scanIsF2(r.data) ? scanB32(r.data) : [...r.binaryData], corners: [l.topLeftCorner, l.topRightCorner, l.bottomRightCorner, l.bottomLeftCorner] };
}

/* ---------- Carrés d'angle ---------- */
// Taches pleines et compactes de la taille attendue d'un carré (5 mm ; le QR imprimé fait 28 mm, environ 24 mm sans marge)
function scanSquares(L, w, h, qr) {
  const qc = qr.reduce((a, p) => ({ x: a.x + p.x / 4, y: a.y + p.y / 4 }), { x: 0, y: 0 });
  const qside = (Math.hypot(qr[1].x - qr[0].x, qr[1].y - qr[0].y) + Math.hypot(qr[2].x - qr[1].x, qr[2].y - qr[1].y)) / 2;
  const sq = qside * 5 / 24.2, area = sq * sq;
  const B = binarize(L, w, h, Math.max(15, Math.round(sq * 3)), 0.7), lab = new Int32Array(w * h), out = [], stack = [];
  const qx0 = Math.min(...qr.map(p => p.x)) - qside * 0.05, qx1 = Math.max(...qr.map(p => p.x)) + qside * 0.05;   // motifs du QR seulement : un carré d'angle peut être juste sous le QR
  const qy0 = Math.min(...qr.map(p => p.y)) - qside * 0.05, qy1 = Math.max(...qr.map(p => p.y)) + qside * 0.05;
  let id = 0;
  for (let s = 0; s < w * h; s++) {
    if (!B[s] || lab[s]) continue;
    id++; lab[s] = id; stack.push(s);
    let n = 0, sx = 0, sy = 0, sxx = 0, syy = 0, big = false;
    while (stack.length) {
      const p = stack.pop(), x = p % w, y = (p - x) / w;
      n++; sx += x; sy += y; sxx += x * x; syy += y * y;
      if (n > area * 4) big = true;
      if (x > 0 && B[p - 1] && !lab[p - 1]) { lab[p - 1] = id; stack.push(p - 1); }
      if (x < w - 1 && B[p + 1] && !lab[p + 1]) { lab[p + 1] = id; stack.push(p + 1); }
      if (y > 0 && B[p - w] && !lab[p - w]) { lab[p - w] = id; stack.push(p - w); }
      if (y < h - 1 && B[p + w] && !lab[p + w]) { lab[p + w] = id; stack.push(p + w); }
    }
    if (big || n < area * 0.3 || n > area * 2.8) continue;
    const cx = sx / n, cy = sy / n, inertia = (sxx / n - cx * cx) + (syy / n - cy * cy), compact = inertia / n;   // 1/6 pour un carré plein
    if (compact < 0.14 || compact > 0.21) continue;
    if (cx > qx0 && cx < qx1 && cy > qy0 && cy < qy1) continue;   // motifs du QR
    out.push({ x: cx, y: cy, n });
  }
  if (out.length < 4) return null;
  // Les 4 taches qui forment le plus grand quadrilatère convexe (au plus 14 candidates, les plus proches de la taille attendue)
  const cand = out.sort((a, b) => Math.abs(a.n - area) - Math.abs(b.n - area)).slice(0, 14);
  let best = null, bestA = 0;
  for (let a = 0; a < cand.length; a++) for (let b = a + 1; b < cand.length; b++) for (let c = b + 1; c < cand.length; c++) for (let d = c + 1; d < cand.length; d++) {
    const four = [cand[a], cand[b], cand[c], cand[d]], ns = four.map(p => p.n);
    if (Math.max(...ns) > Math.min(...ns) * 2) continue;   // les 4 carrés imprimés ont la même taille
    const q = scanOrder(four), A = scanArea(q);
    if (A > bestA && scanConvex(q)) { bestA = A; best = q; }
  }
  if (!best || bestA < qside * qside * 4) return null;
  // Le bord du haut est le plus proche du QR : on tourne l'ordre pour commencer en haut à gauche
  let top = 0, dmin = Infinity;
  for (let i = 0; i < 4; i++) { const p = best[i], q = best[(i + 1) % 4], d = Math.hypot((p.x + q.x) / 2 - qc.x, (p.y + q.y) / 2 - qc.y); if (d < dmin) { dmin = d; top = i; } }
  return [0, 1, 2, 3].map(i => best[(top + i) % 4]);   // haut gauche, haut droite, bas droite, bas gauche (sens horaire à l'écran)
}
function scanOrder(ps) { const c = ps.reduce((a, p) => ({ x: a.x + p.x / 4, y: a.y + p.y / 4 }), { x: 0, y: 0 }); return ps.slice().sort((p, q) => Math.atan2(p.y - c.y, p.x - c.x) - Math.atan2(q.y - c.y, q.x - c.x)); }
function scanArea(q) { let A = 0; for (let i = 0; i < 4; i++) { const p = q[i], r = q[(i + 1) % 4]; A += p.x * r.y - r.x * p.y; } return Math.abs(A) / 2; }
function scanConvex(q) { let s = 0; for (let i = 0; i < 4; i++) { const a = q[i], b = q[(i + 1) % 4], c = q[(i + 2) % 4], z = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x); if (z === 0) return false; if (s && Math.sign(z) !== s) return false; s = Math.sign(z); } return true; }

/* ---------- Redressement ---------- */
// Homographie qui envoie (0,0) (W,0) (W,H) (0,H) sur les 4 carrés de la photo
function homography(dst, W, H) {
  const src = [[0, 0], [W, 0], [W, H], [0, H]], M = [], v = [];
  for (let i = 0; i < 4; i++) {
    const [x, y] = src[i], { x: u, y: w } = dst[i];
    M.push([x, y, 1, 0, 0, 0, -u * x, -u * y]); v.push(u);
    M.push([0, 0, 0, x, y, 1, -w * x, -w * y]); v.push(w);
  }
  for (let c = 0; c < 8; c++) {   // élimination de Gauss avec pivot partiel
    let p = c; for (let r = c + 1; r < 8; r++) if (Math.abs(M[r][c]) > Math.abs(M[p][c])) p = r;
    [M[c], M[p]] = [M[p], M[c]]; [v[c], v[p]] = [v[p], v[c]];
    for (let r = 0; r < 8; r++) if (r !== c) { const f = M[r][c] / M[c][c]; for (let k = c; k < 8; k++) M[r][k] -= f * M[c][k]; v[r] -= f * v[c]; }
  }
  const h = v.map((x, i) => x / M[i][i]);
  return (x, y) => { const z = h[6] * x + h[7] * y + 1; return [(h[0] * x + h[1] * y + h[2]) / z, (h[3] * x + h[4] * y + h[5]) / z]; };
}
function rectify(img, q) {
  const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);
  const W = 1000, H = Math.round(W * (dist(q[0], q[3]) + dist(q[1], q[2])) / (dist(q[0], q[1]) + dist(q[3], q[2])));
  if (H < 60 || H > 6000) return null;
  const f = homography(q, W, H), d = img.data, iw = img.width, ih = img.height;
  const R = new Uint8ClampedArray(W * H * 3), L = new Float32Array(W * H);
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const [u, v] = f(x + 0.5, y + 0.5), ix = Math.min(iw - 1, Math.max(0, Math.round(u))), iy = Math.min(ih - 1, Math.max(0, Math.round(v))), s = (iy * iw + ix) * 4, o = y * W + x;
    R[o * 3] = d[s]; R[o * 3 + 1] = d[s + 1]; R[o * 3 + 2] = d[s + 2];
    L[o] = 0.299 * d[s] + 0.587 * d[s + 1] + 0.114 * d[s + 2];
  }
  return { W, H, R, L };
}

/* ---------- Tableau ---------- */
// Positions des traits : pics d'une projection au-dessus d'un seuil, regroupés
function peaks(P, thr) {
  const out = []; let s = -1;
  for (let i = 0; i <= P.length; i++) {
    const on = i < P.length && P[i] >= thr;
    if (on && s < 0) s = i;
    if (!on && s >= 0) { out.push((s + i - 1) / 2); s = -1; }
  }
  return out.reduce((a, p) => (a.length && p - a[a.length - 1] < 6 ? (a[a.length - 1] = (a[a.length - 1] + p) / 2, a) : (a.push(p), a)), []);
}
// Somme de deux voisins (un trait fin, flou ou légèrement penché, s'étale sur 2 ou 3 pixels)
function smooth(P) { return P.map((_, i) => (P[i - 1] || 0) + P[i] + (P[i + 1] || 0)); }
// Projection des longs traits : pixels foncés comptés seulement dans les suites d'au moins minRun pixels (trous de 2 px tolérés),
// pour ignorer le texte et les coches
function runs(B, W, H, horiz, a0, a1, b0, b1, minRun) {
  const P = new Array(horiz ? H : W).fill(0);
  for (let a = a0; a < a1; a++) {
    let run = 0, gap = 0;
    const flush = () => { if (run >= minRun) P[a] += run; run = 0; gap = 0; };
    for (let b = b0; b < b1; b++) {
      const on = horiz ? B[a * W + b] : B[b * W + a];
      if (on) { run += 1 + gap; gap = 0; } else if (run && gap < 2) gap++; else flush();
    }
    flush();
  }
  return P;
}
function scanGrid(R, nLines) {
  const { W, H, L } = R, B = binarize(L, W, H, 31, 0.8);
  const hy = peaks(smooth(runs(B, W, H, true, 0, H, 0, W, 60)), W * 0.94 * 0.7);
  if (hy.length < 3) return null;
  const y0 = Math.round(hy[0]), y1 = Math.round(hy[hy.length - 1]);
  const vx = peaks(smooth(runs(B, W, H, false, 0, W, y0, y1 + 1, 25)), (y1 - y0) * 0.45);
  if (vx.length !== 9) return null;
  const widths = vx.slice(1).map((x, i) => x - vx[i]), name = widths.indexOf(Math.max(...widths));
  if (name !== 0 && name !== 7) return null;
  const days = widths.filter((_, i) => i !== name), dw = days.reduce((a, b) => a + b, 0) / 7;
  if (days.some(x => Math.abs(x - dw) > dw * 0.35)) return null;
  // Lignes de routine : celles où les traits verticaux des jours traversent la bande (les lignes de moment sont fusionnées)
  const inner = vx.slice(1, 8), rows = [];
  for (let i = 1; i < hy.length - 1; i++) {
    const a = hy[i], b = hy[i + 1], ya = Math.round(a + (b - a) * 0.25), yb = Math.round(a + (b - a) * 0.75);
    let hit = 0, tot = 0;
    for (const x of inner) for (let y = ya; y <= yb; y++) { tot++; for (let dx = -2; dx <= 2; dx++) if (B[y * W + Math.round(x) + dx]) { hit++; break; } }
    if (tot && hit / tot > 0.6) rows.push([a, b]);
  }
  if (rows.length !== nLines) return null;
  return { vx, rows, rtl: name === 7 };
}
// Part d'encre de chaque case (disque central du rond), seuil calibré sur la feuille ; « on », « off » ou « unsure »
function scanCells(R, G) {
  const { W, L, R: px } = R, cells = [], all = [];
  const dayCols = G.rtl ? [6, 5, 4, 3, 2, 1, 0] : [1, 2, 3, 4, 5, 6, 7];   // colonne physique de chaque jour, dans l'ordre imprimé
  for (const [a, b] of G.rows) for (const c of dayCols) {
    const x0 = G.vx[c] + 3, x1 = G.vx[c + 1] - 3, y0 = a + 3, y1 = b - 3, cx = (x0 + x1) / 2, cy = (y0 + y1) / 2, r = 0.26 * Math.min(x1 - x0, y1 - y0);
    const lums = []; for (let y = Math.round(y0); y < y1; y += 2) for (let x = Math.round(x0); x < x1; x += 2) lums.push(L[y * W + x]);
    lums.sort((p, q) => p - q);
    const ref = Math.max(40, lums[Math.floor(lums.length * 0.9)] || 255), s = [];
    let bright = 0;
    for (let y = Math.round(cy - r); y <= cy + r; y++) for (let x = Math.round(cx - r); x <= cx + r; x++) {
      if ((x - cx) ** 2 + (y - cy) ** 2 > r * r) continue;
      const o = y * W + x, mx = Math.max(px[o * 3], px[o * 3 + 1], px[o * 3 + 2]), mn = Math.min(px[o * 3], px[o * 3 + 1], px[o * 3 + 2]);
      const v = Math.max(0, 1 - L[o] / ref, (mx - mn) / 255 * 0.9);
      s.push(v); all.push(v); if (L[o] >= 250) bright++;
    }
    cells.push({ s, glare: s.length && bright / s.length > 0.25 && ref < 245 });
  }
  all.sort((p, q) => p - q);
  const dmax = all[Math.floor(all.length * 0.97)] || 0, k = Math.min(0.4, Math.max(0.2, dmax * 0.45));
  // Encre franche (au-dessus de k) : cochée dès 8 % du disque ; trace plus claire (au-dessus de k / 2 : crayon, feutre presque sec) :
  // incertaine ; trace d'effaçage (gris très clair) : sous k / 2, ignorée
  return cells.map(c => {
    const n = c.s.length || 1, f = c.s.filter(v => v > k).length / n, f2 = c.s.filter(v => v > k / 2).length / n;
    if (f >= 0.08) return "on";
    return c.glare || f > 0.025 || f2 >= 0.04 ? "unsure" : "off";
  });
}

/* ---------- Lecture complète ---------- */
// Renvoie { childId, marks: Map(routine → Set(jour)), unsure: Set(« routine|jour »), stopped: [n° de ligne], glare } ou null (non reconnue)
async function scanRead(src, w, h) {
  const { cv, img } = scanCanvas(src, w, h);
  const q = await scanQR(cv, img); if (!q || !q.corners) return null;
  const m = scanParse(q.bytes); if (!m || !(window.crypto && crypto.subtle)) return null;
  if (!sameBytes(m.family, await sheetHash(S.family.id, 6))) return null;
  let child = null;
  for (const c of S.children) if (sameBytes(m.child, await sheetHash(c.id, 4))) child = c;
  if (!child) return null;
  const L = lumOf(img), corners = scanSquares(L, img.width, img.height, q.corners); if (!corners) return null;
  const R = rectify(img, corners); if (!R) return null;
  const G = scanGrid(R, m.lines.length); if (!G || G.rtl !== m.rtl) return null;
  const states = scanCells(R, G);
  const own = await Promise.all(S.routines.filter(r => r.child_id === child.id && !isOneoff(r)).map(async r => ({ id: r.id, h: await sheetHash(r.id, 4) })));
  const order = Array.from({ length: 7 }, (_, i) => ((m.start - 1 + i) % 7) + 1);   // jours dans l'ordre imprimé (premier jour du repère)
  const marks = new Map(), unsure = new Set(), stopped = [];
  m.lines.forEach((hsh, i) => {
    const r = own.find(o => sameBytes(o.h, hsh));
    if (!r) { stopped.push(i + 1); return; }   // routine arrêtée (ou supprimée) depuis l'impression : ignorée et signalée (CA15)
    order.forEach((dow, j) => {
      const st = states[i * 7 + j];
      if (st === "on") { if (!marks.has(r.id)) marks.set(r.id, new Set()); marks.get(r.id).add(dow); }
      if (st === "unsure") unsure.add(r.id + "|" + dow);
    });
  });
  if (window.__scanDebug) window.__scanDebug({ format: m.format, states, rows: G.rows.length });
  return { childId: child.id, marks, unsure, stopped };
}

/* ---------- Écran ---------- */
function scanStop() { if (SCAN.stream) { SCAN.stream.getTracks().forEach(tr => tr.stop()); SCAN.stream = null; } }
dlg.addEventListener("close", scanStop);
function scanSay(msg) { const s = $("#sc-status", dlg); if (s) s.textContent = msg; }

// Bouton « 📷 Scanner une feuille » (Routines, Parent) : incitation Premium en gratuit, rien n'est lu (CA1)
A.scanSheet = async () => {
  if (needPremium("report")) return;
  SCAN.busy = false;
  openSheet(`<h2 id="sc-title" tabindex="-1">${t("scan.title")}</h2>
    <p class="muted small">${t("scan.help")}</p>
    <div class="sc-view"><video id="sc-video" playsinline muted aria-hidden="true"></video><div class="sc-guide" aria-hidden="true"></div></div>
    <p id="sc-status" class="sc-status" role="status" aria-live="polite"></p>
    <div class="sheet-actions sc-actions">
      <label class="btn ghost sc-file">${t("scan.choose")}<input type="file" id="sc-file" accept="image/*" class="vh"></label>
      <button class="btn" id="sc-shoot" data-act="scanShoot" disabled>📸 ${t("scan.shoot")}</button>
    </div>
    <p class="sc-links"><button class="link" data-act="reportWeek">${t("scan.manual")}</button> · <button class="link" data-act="closeSheet">${t("btn.cancel")}</button></p>`);
  $("#sc-file", dlg).addEventListener("change", scanFile);
  const h = $("#sc-title", dlg); if (h) h.focus();
  await scanCamera();
};
async function scanCamera() {
  scanStop();
  const v = $("#sc-video", dlg), go = $("#sc-shoot", dlg);
  const none = () => { $(".sc-view", dlg).hidden = true; go.hidden = true; scanSay(t("scan.noCamera")); };   // secours : « Choisir une photo »
  if (!(navigator.mediaDevices && navigator.mediaDevices.getUserMedia)) return none();
  try {
    SCAN.stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: { ideal: "environment" }, width: { ideal: 1920 }, height: { ideal: 1080 } }, audio: false });
    if (!dlg.open || !v.isConnected) return scanStop();
    v.srcObject = SCAN.stream; await v.play();
    go.disabled = false; scanSay(t("scan.aim"));
  } catch (e) { scanStop(); if (dlg.open && v.isConnected) none(); }
}
A.scanShoot = async () => {
  const v = $("#sc-video", dlg); if (!v || !v.videoWidth || SCAN.busy) return;
  const cv = document.createElement("canvas"); cv.width = v.videoWidth; cv.height = v.videoHeight;
  cv.getContext("2d").drawImage(v, 0, 0);
  await scanRun(cv, cv.width, cv.height);
};
async function scanFile(e) {
  const f = e.target.files && e.target.files[0]; e.target.value = "";
  if (!f || SCAN.busy) return;
  let bmp = null;
  try { bmp = await createImageBitmap(f, { imageOrientation: "from-image" }); }
  catch (err) { try { bmp = await createImageBitmap(f); } catch (e2) { return scanSay(t("scan.unknown")); } }
  await scanRun(bmp, bmp.width, bmp.height);
  if (bmp.close) bmp.close();
}
async function scanRun(src, w, h) {
  SCAN.busy = true; scanSay(t("scan.reading"));
  const go = $("#sc-shoot", dlg); if (go) go.disabled = true;
  let res = null;
  try { res = await scanRead(src, w, h); } catch (e) { console.error(e); res = null; }
  SCAN.busy = false;
  if (!res) { scanSay(t("scan.unknown")); if (go) go.disabled = !SCAN.stream; return; }
  scanStop();
  repOpen(res.childId, res);   // la photo n'est plus référencée : le navigateur l'oublie (CA13)
  toast(t("scan.ok"));
}
