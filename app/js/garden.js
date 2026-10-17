"use strict";
/* SoisFier : Jardin : dessins (SVG) */
/* ================= Jardin : dessins ================= */
const GC = { leaf: "#66B84C", leafD: "#3F8C35", stem: "#4F9B3B", soil: "#6B4430", soilD: "#523222", yel: "#FFCB2E", yelD: "#F0A30F", ctr: "#7A4A22", ctrD: "#5A3416", cheek: "#F59A9A", ink: "#3B2418" };
const SP = {
  "tournesol": { k: "sun", pe: "#FFCB2E", pd: "#F0A30F", ct: "#7A4A22" },
  "marguerite": { k: "sun", pe: "#FFFFFF", pd: "#EEF0F5", ct: "#FFCB2E", np: 14 },
  "cosmos-rose": { k: "cosmos", pe: "#FF8FB1", pd: "#F06A97" },
  "cosmos-orange": { k: "cosmos", pe: "#F28C28", pd: "#D86F10" },
  "cosmos-rouge": { k: "cosmos", pe: "#E0474C", pd: "#BE3036" },
  "tulipe-rose": { k: "tulip", pe: "#F0607A", pd: "#C93E5A" },
  "tulipe-jaune": { k: "tulip", pe: "#FFCB2E", pd: "#E0A400" },
  "tulipe-violette": { k: "tulip", pe: "#B07CE0", pd: "#8A55C0" },
  "tulipe-rouge": { k: "tulip", pe: "#E0474C", pd: "#BE3036" },
  "hellebore": { k: "hell", pe: "#FFFFFF", pd: "#F3E6EE" }
};
const SEASON_SP = { printemps: ["tulipe-rose", "marguerite", "tulipe-jaune", "tulipe-violette"], ete: ["tournesol", "cosmos-rose", "marguerite", "tournesol"],
  automne: ["cosmos-orange", "tournesol", "cosmos-rouge", "marguerite"], hiver: ["hellebore", "tulipe-rouge", "hellebore", "marguerite"] };
const spName = k => t("garden.species." + k);
const SEASON_NAME = new Proxy({}, { get: (_, k) => t("garden.seasonOf." + String(k)) });   // « du printemps », « de l'été »…
const GRADE_NAME = new Proxy([], { get: (_, i) => /^\d+$/.test(String(i)) ? t("garden.grade")[+i] : undefined });
const STAGE_NAME = new Proxy([], { get: (_, i) => /^\d+$/.test(String(i)) ? t("garden.stage")[+i] : undefined });
function shade(hex, f) { const n = parseInt(hex.slice(1), 16); const c = [n >> 16, (n >> 8) & 255, n & 255].map(v => Math.max(0, Math.min(255, Math.round(f < 0 ? v * (1 + f) : v + (255 - v) * f)))); return "#" + c.map(v => v.toString(16).padStart(2, "0")).join(""); }
const leafG = (x, y, a, s = 1) => `<g transform="translate(${x} ${y}) rotate(${a}) scale(${s})"><path d="M0 0 C 8 -12, 27 -13, 36 0 C 27 11, 8 12, 0 0 Z" fill="${GC.leaf}" stroke="${GC.leafD}" stroke-width="1.6" stroke-linejoin="round"/><path d="M3 0 Q 18 -1.5 31 0" stroke="${GC.leafD}" stroke-width="1.3" fill="none" stroke-linecap="round"/></g>`;
const stemG = (h, w = 5, x = 100, y = 140) => `<path d="M${x} ${y} C ${x - 4} ${y - h * .4}, ${x + 4} ${y - h * .72}, ${x} ${y - h}" stroke="${GC.stem}" stroke-width="${w}" fill="none" stroke-linecap="round"/>`;
const sparkG = (x, y, s) => `<path transform="translate(${x} ${y}) scale(${s})" d="M0 -10 Q2 -2 10 0 Q2 2 0 10 Q-2 2 -10 0 Q-2 -2 0 -10 Z" fill="${GC.yel}"/>`;
const beeG = (x, y, s = 1) => `<g transform="translate(${x} ${y}) scale(${s})"><ellipse cx="-3" cy="-9" rx="6" ry="4" fill="#E4F2FF" stroke="#9AB8D8"/><ellipse cx="4" cy="-9" rx="6" ry="4" fill="#E4F2FF" stroke="#9AB8D8"/><ellipse rx="9" ry="7" fill="${GC.yel}"/><path d="M-3 -6 L-3 6 M2 -6.5 L2 6.5" stroke="#2A170C" stroke-width="2.4"/><circle cx="8" cy="-1" r="1.4" fill="#2A170C"/></g>`;
function faceG(k) {
  const ch = `<circle cx="77" cy="186" r="5.5" fill="${GC.cheek}" opacity=".8"/><circle cx="123" cy="186" r="5.5" fill="${GC.cheek}" opacity=".8"/>`;
  if (k === "sleep") return ch + `<path d="M82 177 q5 4 10 0 M108 177 q5 4 10 0" stroke="${GC.ink}" stroke-width="2.6" fill="none" stroke-linecap="round"/><path d="M96 189 q4 2 8 0" stroke="${GC.ink}" stroke-width="2.4" fill="none" stroke-linecap="round"/><text x="130" y="128" font-family="sans-serif" font-size="15" font-weight="bold" fill="#9AA9C4">z</text><text x="140" y="114" font-family="sans-serif" font-size="20" font-weight="bold" fill="#9AA9C4">z</text>`;
  if (k === "joy") return ch + `<path d="M82 179 q5 -7 10 0 M108 179 q5 -7 10 0" stroke="${GC.ink}" stroke-width="2.8" fill="none" stroke-linecap="round"/><path d="M91 185 q9 12 18 0 Z" fill="#9B3434" stroke="${GC.ink}" stroke-width="2" stroke-linejoin="round"/>`;
  return ch + `<ellipse cx="87" cy="177" rx="3.2" ry="4.2" fill="${GC.ink}"/><ellipse cx="113" cy="177" rx="3.2" ry="4.2" fill="${GC.ink}"/><circle cx="88.2" cy="175.5" r="1.2" fill="#fff"/><circle cx="114.2" cy="175.5" r="1.2" fill="#fff"/><path d="M93 186 q7 6 14 0" stroke="${GC.ink}" stroke-width="2.6" fill="none" stroke-linecap="round"/>`;
}
function potG(k, color = "#E58358") {
  const d = shade(color, -.16), l = shade(color, .35);
  return `<path d="M60 150 L140 150 L131 208 Q130 215 123 215 L77 215 Q70 215 69 208 Z" fill="${color}"/><path d="M118 150 L140 150 L131 208 Q130 215 123 215 L114 215 Z" fill="${d}" opacity=".55"/><rect x="51" y="137" width="98" height="21" rx="9" fill="${d}"/><rect x="58" y="141" width="44" height="5" rx="2.5" fill="${l}"/><ellipse cx="100" cy="139" rx="43" ry="6.5" fill="${GC.soil}"/><circle cx="84" cy="139" r="1.6" fill="${GC.soilD}"/><circle cx="113" cy="140" r="1.6" fill="${GC.soilD}"/><circle cx="124" cy="138" r="1.3" fill="${GC.soilD}"/>${faceG(k)}`;
}
function headG(key, cx, cy, r, open = 1, smile = false) {
  const sp = SP[key] || SP.tournesol; let p = "";
  if (sp.k === "sun") {
    const n = sp.np || 16;
    for (let k = 0; k < n; k++) p += `<ellipse cx="${cx}" cy="${(cy - r * (.6 + .85 * open)).toFixed(1)}" rx="${(r * .38).toFixed(1)}" ry="${(r * .85 * open).toFixed(1)}" fill="${k % 2 ? sp.pd : sp.pe}" ${sp.pe === "#FFFFFF" ? 'stroke="#E2E4EA" stroke-width=".8"' : ""} transform="rotate(${k * 360 / n} ${cx} ${cy})"/>`;
    p += `<circle cx="${cx}" cy="${cy}" r="${r}" fill="${sp.ct}"/>`;
    if (sp.ct !== GC.yel) p += `<circle cx="${cx}" cy="${cy}" r="${(r * .72).toFixed(1)}" fill="none" stroke="${GC.ctrD}" stroke-width="1.4" stroke-dasharray="2 3"/>`;
  } else if (sp.k === "cosmos" || sp.k === "hell") {
    const n = sp.k === "cosmos" ? 8 : 5, rx = sp.k === "cosmos" ? r * .62 : r * .82;
    for (let k = 0; k < n; k++) p += `<ellipse cx="${cx}" cy="${(cy - r * (.45 + .75 * open)).toFixed(1)}" rx="${rx.toFixed(1)}" ry="${(r * .95 * open).toFixed(1)}" fill="${k % 2 ? sp.pd : sp.pe}" ${sp.k === "hell" ? 'stroke="#D9C2D0" stroke-width="1"' : ""} transform="rotate(${k * 360 / n} ${cx} ${cy})"/>`;
    p += sp.k === "hell" ? `<circle cx="${cx}" cy="${cy}" r="${(r * .5).toFixed(1)}" fill="#C9D86B"/><circle cx="${cx}" cy="${cy}" r="${(r * .25).toFixed(1)}" fill="${GC.yel}"/>` : `<circle cx="${cx}" cy="${cy}" r="${(r * .5).toFixed(1)}" fill="${GC.yel}"/>`;
  } else {
    const s = r / 11, w = 11 * s * (.55 + .45 * open);
    p += `<path d="M${cx - w} ${cy - 14 * s} Q${cx - w} ${cy + 10 * s} ${cx} ${cy + 12 * s} Q${cx + w} ${cy + 10 * s} ${cx + w} ${cy - 14 * s} L${cx + w * .45} ${cy - 6 * s} L${cx} ${cy - 18 * s} L${cx - w * .45} ${cy - 6 * s} Z" fill="${sp.pe}" stroke="${sp.pd}" stroke-width="1.8" stroke-linejoin="round"/>`;
  }
  if (smile) p += `<ellipse cx="${cx - r * .35}" cy="${cy - r * .15}" rx="2.4" ry="3.2" fill="#2A170C"/><ellipse cx="${cx + r * .35}" cy="${cy - r * .15}" rx="2.4" ry="3.2" fill="#2A170C"/><path d="M${cx - r * .35} ${cy + r * .25} q${r * .35} ${r * .4} ${r * .7} 0" stroke="#2A170C" stroke-width="2.2" fill="none" stroke-linecap="round"/>`;
  return p;
}
const budG = (x, y, rx, ry) => `<ellipse cx="${x}" cy="${y}" rx="${rx}" ry="${ry}" fill="${GC.leaf}" stroke="${GC.leafD}" stroke-width="1.7"/><path d="M${x - rx * .7} ${y - ry * .3} L${x} ${y + ry * .7} L${x + rx * .7} ${y - ry * .3}" stroke="${GC.leafD}" stroke-width="1.5" fill="none" stroke-linejoin="round"/>`;
function tipsG(key, x, y, s) { const c = (SP[key] || SP.tournesol).pe; let g = ""; for (let k = -2; k <= 2; k++) g += `<ellipse cx="${x + k * 6 * s}" cy="${y - 14 * s}" rx="${4 * s}" ry="${9 * s}" fill="${c}" stroke="${c === "#FFFFFF" ? "#D9DCE4" : "none"}" transform="rotate(${k * 18} ${x} ${y})"/>`; return g + budG(x, y, 13 * s, 12 * s); }
/* Une étape (0 à 13) de la fleur en pot */
function stageArt(st, key = "tournesol", color = "#E58358", final = null) {
  st = Math.max(0, Math.min(13, st | 0)); let g = "";
  if (st === 0) return potG("sleep", color);
  if (st === 1) return potG("smile", color) + `<ellipse cx="100" cy="137" rx="17" ry="5" fill="${GC.soilD}"/><g transform="translate(103 128) rotate(-25)"><ellipse rx="7" ry="11" fill="#3B2C25"/><path d="M-3.2 -8 L-3.2 8 M0 -10.5 L0 10.5 M3.2 -8 L3.2 8" stroke="#EDE3D6" stroke-width="1.2"/></g>`;
  if (st === 2) return stemG(26, 4.5) + `<ellipse cx="88" cy="113" rx="12" ry="7" fill="${GC.leaf}" stroke="${GC.leafD}" stroke-width="1.6" transform="rotate(-25 88 113)"/><ellipse cx="112" cy="113" rx="12" ry="7" fill="${GC.leaf}" stroke="${GC.leafD}" stroke-width="1.6" transform="rotate(25 112 113)"/>` + potG("smile", color);
  const H = { 3: 40, 4: 52, 5: 64, 6: 78, 7: 90, 8: 96, 9: 100, 10: 102, 11: 104, 12: 106, 13: 106 }[st], ty = 140 - H;
  const side = st >= 8, sy = 140 - H * .55, sx = 58, sty = sy - 10;
  if (side) g += `<path d="M100 ${sy} Q 76 ${sy + 2} ${sx} ${sty}" stroke="${GC.stem}" stroke-width="4" fill="none" stroke-linecap="round"/>`;
  g += stemG(H, st >= 7 ? 6 : 5);
  if (st === 3) g += leafG(100, 140 - H * .5, 205, .85) + leafG(100, 140 - H * .56, -25, .85);
  if (st === 4) g += leafG(100, 140 - H * .45, 205, 1) + leafG(100, 140 - H * .5, -25, 1);
  if (st === 5) g += leafG(100, 140 - H * .3, 202, 1.05) + leafG(100, 140 - H * .34, -22, 1.05) + leafG(100, 140 - H * .62, 208, .8) + leafG(100, 140 - H * .66, -28, .8);
  if (st >= 6) { g += leafG(100, 140 - H * .2, 200, 1.12) + leafG(100, 140 - H * .24, -20, 1.12) + leafG(100, 140 - H * .44, -26, .95);
    g += side ? leafG(100, 140 - H * .72, -30, .72) : leafG(100, 140 - H * .47, 206, .95) + leafG(100, 140 - H * .68, -30, .75); }
  if (st >= 3 && st <= 6) g += `<ellipse cx="100" cy="${ty - 3}" rx="4.5" ry="7" fill="${GC.leaf}" stroke="${GC.leafD}" stroke-width="1.4"/>`;
  if (st === 7) g += budG(100, ty - 7, 7, 9);
  if (st === 8) g += budG(100, ty - 8, 8.5, 11) + budG(sx, sty - 5, 5, 7);
  if (st === 9) g += budG(100, ty - 10, 11, 14) + budG(sx, sty - 6, 6.5, 8.5);
  if (st === 10) g += tipsG(key, 100, ty - 7, 1) + budG(sx, sty - 7, 7, 9);
  if (st === 11) g += headG(key, 100, ty - 12, 12, .5) + tipsG(key, sx, sty - 6, .6);
  if (st === 12) g += headG(key, 100, ty - 14, 15) + headG(key, sx, sty - 8, 7, .5);
  if (st === 13) {
    const gr = final == null ? 3 : final;
    if (gr === 0) g += tipsG(key, 100, ty - 7, 1.05) + budG(sx, sty - 7, 7, 9);
    else { const R = [0, 10, 14, 16][gr]; g += headG(key, 100, ty - 14, R, 1, SP[key]?.k === "sun") + headG(key, sx, sty - 9, gr >= 2 ? 8 : 6, gr >= 2 ? 1 : .6); }
    if (gr === 3) g += sparkG(150, 6, 1) + sparkG(160, 62, .65) + sparkG(40, -10, .7) + beeG(152, 104);
  }
  return g + potG(st >= 12 ? "joy" : "smile", color);
}
function stageSVG(st, key, color, label, final) { return `<svg viewBox="0 -48 200 268" role="img" aria-label="${esc(label || STAGE_NAME[Math.max(0, Math.min(13, st | 0))])}"><g class="sway">${stageArt(st, key, color, final)}</g></svg>`; }
/* Compatibilité : petites illustrations des écrans d'accueil */
function plantSVG(level, color = "#E58358", label) { return stageSVG([0, 2, 5, 7, 12, 13][Math.max(0, Math.min(5, level | 0))], "tournesol", color, label || t("garden.plant")); }
const miniLogo = () => `<svg viewBox="0 -48 200 268" aria-hidden="true">${stageArt(13, "tournesol", "#E8484F")}</svg>`;

/* Fleur plantée dans un parterre */
function bedFlower(x, y, f) {
  const gr = f.grade, h = [70, 95, 118, 140][gr], sc = [1, 1.15, 1.45, 1.75][gr], t = y - h;
  let g = `<path d="M${x} ${y} C ${x - 4} ${y - h * .4}, ${x + 4} ${y - h * .7}, ${x} ${t}" stroke="${GC.stem}" stroke-width="${gr ? 5 : 4}" fill="none" stroke-linecap="round"/>` + leafG(x, y - h * .3, 203, gr ? .95 : .75) + leafG(x, y - h * .45, -25, gr ? .95 : .75);
  g += gr === 0 ? `<g transform="translate(${x} ${t}) scale(.75) translate(${-x} ${-t})">${tipsG(f.species, x, t - 2, 1)}</g>` : headG(f.species, x, t - 4, 7 * sc);
  if (gr === 3) g += sparkG(x + 22, t - 28, .5);
  return g;
}
const SCENE = {
  printemps: { sky: "#E4F3FF", grass: "#A6DB84", grassD: "#86C463", border: "#C9C2B8",
    deco: () => { const fly = (x, y, c) => `<g transform="translate(${x} ${y})"><ellipse cx="-6" cy="-3" rx="7" ry="9" fill="${c}" transform="rotate(-25 -6 -3)"/><ellipse cx="6" cy="-3" rx="7" ry="9" fill="${c}" transform="rotate(25 6 -3)"/><ellipse cx="-5" cy="7" rx="4.5" ry="5" fill="${c}"/><ellipse cx="5" cy="7" rx="4.5" ry="5" fill="${c}"/><rect x="-1.5" y="-8" width="3" height="18" rx="1.5" fill="#4A2E1F"/></g>`; return fly(60, 40, "#7FB8F0") + fly(470, 36, "#FF9EC2") + fly(552, 92, "#FFCB2E"); } },
  ete: { sky: "#DDEFFF", grass: "#9BD07A", grassD: "#7DBB5C", border: "#C9C2B8",
    deco: () => `<circle cx="540" cy="58" r="28" fill="${GC.yel}"/>` + Array.from({ length: 10 }, (_, k) => `<rect x="538" y="8" width="4" height="13" rx="2" fill="${GC.yel}" transform="rotate(${k * 36} 540 58)"/>`).join("") + beeG(50, 40) + beeG(330, 34, .8) },
  automne: { sky: "#FFF2E2", grass: "#C7C67A", grassD: "#A9A85C", border: "#A8865E",
    deco: () => { const lf = (x, y, a, c) => `<g transform="translate(${x} ${y}) rotate(${a})"><path d="M0 -12 C 9 -8 9 6 0 12 C -9 6 -9 -8 0 -12 Z" fill="${c}"/><path d="M0 -12 L0 12" stroke="#7A3E10" stroke-width="1"/></g>`; return lf(60, 50, 30, "#E8862A") + lf(150, 90, -40, "#C9442A") + lf(470, 60, 60, "#E8B12A") + lf(552, 110, -20, "#E8862A") + lf(360, 34, 15, "#C9442A") + `<g transform="translate(566 268)"><rect x="-4" y="-10" width="8" height="12" rx="3" fill="#F3E3C8"/><path d="M-14 -8 Q0 -26 14 -8 Z" fill="#D8462E"/><circle cx="-5" cy="-14" r="2" fill="#fff"/><circle cx="5" cy="-12" r="1.6" fill="#fff"/></g>`; } },
  hiver: { sky: "#EDF2FA", grass: "#F6F8FC", grassD: "#DDE5F1", border: "#C9C2B8", snow: true,
    deco: () => { const fl = (x, y, s) => `<g transform="translate(${x} ${y}) scale(${s})" stroke="#A9BEDD" stroke-width="2.4" stroke-linecap="round"><path d="M0 -10 L0 10 M-8.7 -5 L8.7 5 M-8.7 5 L8.7 -5"/></g>`; return fl(60, 50, 1) + fl(160, 100, .7) + fl(460, 40, 1.1) + fl(550, 110, .8) + fl(330, 30, .7) + fl(250, 70, .6); } }
};
function parterreArt(season, flowers, growing) {
  const s = SCENE[season] || SCENE.ete; let g = `<rect width="600" height="330" fill="${s.sky}"/>${s.deco()}<rect y="190" width="600" height="140" fill="${s.grass}"/><rect y="190" width="600" height="6" fill="${s.grassD}"/><rect x="50" y="222" width="500" height="76" rx="38" fill="${GC.soil}"/>`;
  const list = flowers.slice(0, 8), n = Math.max(6, list.length + (growing ? 1 : 0)), step = 440 / Math.max(1, n - 1);
  const slots = list.map((f, i) => ({ f, i })).concat(growing ? [{ grow: true, i: list.length }] : []);
  const order = slots.slice().sort((a, b) => (a.i % 2) - (b.i % 2));
  order.forEach(o => { const x = 80 + o.i * step, y = o.i % 2 ? 286 : 262;
    if (o.grow) g += `<g transform="translate(${x} ${y - 8})"><ellipse rx="16" ry="6" fill="${GC.soilD}"/><path d="M0 -2 q-2 -14 6 -18" stroke="${GC.leaf}" stroke-width="3" fill="none" stroke-linecap="round"/><ellipse cx="7" cy="-19" rx="6" ry="3.5" fill="${GC.leaf}" transform="rotate(-30 7 -19)"/></g>`;
    else g += bedFlower(x, y, o.f); });
  for (let k = 0; k < 16; k++) { const x = 56 + k * 32.5; g += `<ellipse cx="${x}" cy="${k % 2 ? 300 : 298}" rx="15" ry="8" fill="${s.border}"/>`; if (s.snow) g += `<ellipse cx="${x}" cy="${k % 2 ? 294 : 292}" rx="12" ry="4.5" fill="#FFFFFF"/>`; }
  return g;
}
const parterreSVG = (season, flowers, growing, label) => `<svg viewBox="0 0 600 330" role="img" aria-label="${esc(label || t("garden.bed"))}">${parterreArt(season, flowers, growing)}</svg>`;
const YEAR_ORDER = ["automne", "hiver", "printemps", "ete"];
function gardenSVG(name, year, flowers, cur) {
  let g = `<rect width="1300" height="900" fill="#BFE3A3"/><rect width="1300" height="120" fill="#DDEFFF"/>`;
  for (let k = 0; k < 27; k++) { const x = 10 + k * 48; g += `<path d="M${x} 150 L${x} 108 L${x + 12} 96 L${x + 24} 108 L${x + 24} 150 Z" fill="#E9C99A" stroke="#B88A55" stroke-width="2"/>`; }
  g += `<rect y="118" width="1300" height="10" fill="#C9A26E"/><rect y="138" width="1300" height="10" fill="#C9A26E"/><rect x="610" y="150" width="80" height="750" fill="#E8D3AE"/><rect y="505" width="1300" height="60" fill="#E8D3AE"/>`;
  YEAR_ORDER.forEach((se, i) => { const x = i % 2 ? 710 : 20, y = i < 2 ? 165 : 580, fl = flowers.filter(f => f.season === se);
    g += `<g transform="translate(${x},${y}) scale(.95)"><clipPath id="gy${year}${i}"><rect width="600" height="330" rx="28"/></clipPath><g clip-path="url(#gy${year}${i})">${fl.length || (cur && cur.season === se) ? parterreArt(se, fl, cur && cur.season === se) : `<rect width="600" height="330" fill="#E9F1E3"/><text x="300" y="175" text-anchor="middle" font-family="sans-serif" font-size="30" fill="#8FA585">${esc(t("garden.bedOf", { season: SEASON_NAME[se] }))}</text>`}</g></g>`; });
  g += `<g transform="translate(650 42)"><rect x="-290" y="-30" width="580" height="64" rx="14" fill="#8A5A34"/><rect x="-282" y="-23" width="564" height="50" rx="10" fill="#B07A4C"/><text x="0" y="12" text-anchor="middle" font-family="sans-serif" font-size="28" font-weight="bold" fill="#FFF6E6">${esc(t("garden.gardenOfYear", { name, year }))}</text></g>`;
  return `<svg viewBox="0 0 1300 900" role="img" aria-label="${esc(t("garden.gardenYear", { year }))}">${g}</svg>`;
}
/* Quinzaine en cours */
function gardenNow(gd) {
  if (!gd) return null;
  const t = gd.today, days = gd.days || [], good = days.filter(d => d.good).length;
  const dayIdx = Math.round((parseISO(t) - parseISO(gd.period_start)) / 864e5) + 1;
  const pausedToday = (gd.pauses || []).some(p => p.start_day <= t && p.end_day >= t);
  const prior = (gd.flowers || []).filter(f => f.season === seasonOfISO(gd.period_end) && f.garden_year === gardenYearOfISO(gd.period_end)).length;
  const list = SEASON_SP[seasonOfISO(gd.period_end)], species = list[prior % list.length];
  const len = gd.period_len || 14;
  // Croissance adaptée à la durée : une première fleur plus courte pousse plus vite
  return { good, dayIdx, len, stage: Math.min(12, Math.floor(good * 14 / len)), species, pausedToday, end: gd.period_end, days, waiting: dayIdx < 1, start: gd.period_start };
}
function seasonOfISO(s) { const md = s.slice(5, 7) + s.slice(8, 10); return md >= "0320" && md < "0621" ? "printemps" : md >= "0621" && md < "0923" ? "ete" : md >= "0923" && md < "1221" ? "automne" : "hiver"; }
function gardenYearOfISO(s) { const y = +s.slice(0, 4), md = s.slice(5, 7) + s.slice(8, 10); return md >= "0923" ? `${y}-${y + 1}` : `${y - 1}-${y}`; }
function dots14(gd) {
  const map = Object.fromEntries((gd.days || []).map(d => [d.day, d])); let h = "";
  for (let i = 0; i < (gd.period_len || 14); i++) { const day = addDays(gd.period_start, i), d = map[day];
    const cls = day > gd.today ? "future" : !d ? "future" : (d.paused || d.due === 0) ? "neutral" : d.good ? "good" : day === gd.today ? "today" : "miss";
    h += `<span class="d14 ${cls} ${day === gd.today ? "today" : ""}" title="${fmtDay(day)}"></span>`; }
  return `<div class="days14" aria-label="${t("garden.fortnightDays")}">${h}</div>`;
}
const fmtLong = s => parseISO(s).toLocaleDateString(loc(), { weekday: "long", day: "numeric", month: "long" });
