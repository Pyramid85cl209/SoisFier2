"use strict";
/* SoisFier : Configuration Supabase (injectée au déploiement) et chemins du site */
/* ================= Configuration ================= */
const CFG = {
  url: "__SUPABASE_URL__",   // injecté au déploiement depuis le secret GitHub SUPABASE_URL
  key: "__SUPABASE_KEY__"    // injecté au déploiement depuis le secret GitHub SUPABASE_KEY
};
const CFG_OK = !CFG.url.startsWith("__") && !CFG.key.startsWith("__");
let sb = null;
try { if (!CFG_OK) throw new Error("config"); sb = window.supabase.createClient(CFG.url, CFG.key, { auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true } }); }
catch (e) { console.warn("Supabase indisponible", e); }
// Chemins du site, relatifs à l'app. Aujourd'hui l'app est servie à la racine ; au passage au domaine, elle ira dans /app/ et ces chemins deviendront « ../guide/ » et « ../ ».
const PATHS = { guide: "guide/", vitrine: "vitrine/" };
