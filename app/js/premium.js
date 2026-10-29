"use strict";
/* SoisFier : Offre gratuit / Premium : blocages et incitations */
/* ---------- Offre (gratuit / Premium) ----------
   families.plan : free, premium ou founder (Premium à vie). Le serveur bloque aussi (codes SF:premium_*).
   Plan inconnu (ancien cache) : traité comme Premium pour ne jamais bloquer à tort. */
const isPremium = () => S.screen === "child" ? S.cs?.premium !== false : (S.plan || "founder") !== "free";
// Canal : app Google Play (TWA, lancée avec ?src=play) ou web. Sert à choisir le paiement le plus favorable.
const CHANNEL = (() => { try {
  const u = new URLSearchParams(location.search);
  if (u.get("src") === "play" || /^android-app:\/\//.test(document.referrer)) store.set("channel", "play");
} catch {} return store.get("channel", "web"); })();
// Badges de la boucle principale, gratuits : routines faites, étoiles, régularité, fleurs
const FREE_BADGE = k => /^(first|r\d+|s\d+|st\d+|f\d+)$/.test(k);
const visibleBadges = () => isPremium() ? BADGES : BADGES.filter(b => FREE_BADGE(b.k));
const ptag = () => isPremium() ? "" : ` <span class="ptag">${t("premium.tag")}</span>`;
// Incitation : jamais côté enfant ; jamais pour une famille Premium ou fondatrice.
// Pour l'instant, renvoie vers la section Premium du guide (web comme Play : le paiement Play viendra plus tard).
const premiumHref = from => `${guideHref()}?from=${encodeURIComponent(from)}&ch=${CHANNEL}#premium`;
function upsell(key, extra = {}) {
  if (S.screen === "child") return;
  openSheet(`<div class="center"><div class="up-emo" aria-hidden="true">${t(`premium.${key}.emoji`)}</div><h2>${t(`premium.${key}.title`, extra)}</h2></div>
    <p>${t(`premium.${key}.text`, extra)}</p><p class="muted small">${t("premium.free")}</p>
    <div class="sheet-actions"><button class="btn ghost" data-act="closeSheet">${t("premium.later")}</button><a class="btn" href="${premiumHref(key)}">${t("premium.see")}</a></div>`);
}
const needPremium = (key, extra) => { if (isPremium()) return false; upsell(key, extra); return true; };
function memberLabel(uid) { const m = S.members.find(x => x.user_id === uid); return m ? (relLabel(m) || m.display_name || t("member.aParent")) : t("member.aMember"); }
function whoValidated(x) { if (!x.validated_at) return ""; return x.validated_by ? memberLabel(x.validated_by) : t("member.autoValidated"); }
// m : membre existant (ou null). Le choix proposé suit la clé ; enregistrer sans rien changer garde le lien d'origine (un « خالو » ne devient pas « Tonton »).
function relationField(m, idp = "rel", defKey = null) {
  const keys = RELATIONS(), k = m ? m.relation_key : defKey, custom = m && m.relation && !m.relation_key ? m.relation : "";
  const sel = k ? (keys.includes(k) ? k : keys.find(x => k.startsWith(x + "_") || x.startsWith(k + "_")) || "__autre") : custom ? "__autre" : "";
  return `<label class="f">${t("member.relation")}<select id="${idp}-sel" data-init="${sel}">${sel ? "" : `<option value="" selected></option>`}${keys.map(r => `<option value="${r}" ${r === sel ? "selected" : ""}>${esc(t("rel." + r))}</option>`).join("")}<option value="__autre" ${sel === "__autre" ? "selected" : ""}>${t("member.otherRel")}</option></select></label>
    <label class="f">${t("member.customLabel")}<input id="${idp}-txt" maxlength="40" placeholder="${t("member.customPlaceholder")}" value="${esc(custom)}" data-init="${esc(custom)}"></label>`;
}
// Renvoie { relation, relation_key } (libellé dans la langue de l'appareil, clé ou null), ou undefined si rien n'a changé (sauf force)
const readRelation = (idp = "rel", force = false) => {
  const s = $("#" + idp + "-sel"), x = $("#" + idp + "-txt"), txt = x.value.trim();
  if (!force && s.value === s.dataset.init && txt === (x.dataset.init || "")) return undefined;
  if (txt) return { relation: txt, relation_key: null };
  return s.value === "__autre" || !s.value ? { relation: null, relation_key: null } : { relation: t("rel." + s.value), relation_key: s.value };
};
