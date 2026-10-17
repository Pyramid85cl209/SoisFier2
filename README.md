# SoisFier

Application familiale de routines pour enfants : étoiles validées par les parents, récompenses calibrées, jardin (une fleur par quinzaine, un parterre par saison, un jardin par an), sorties près de chez soi, rappels sur Android.

- Interface : PWA dans `app/` publiée sur GitHub Pages par la GitHub Action `deploy.yml`, avec le guide (`guide/`) et la vitrine (`vitrine/`).
- Organisation de `app/` :
  - `index.html` : page unique (structure) ; `css/app.css` : styles ; `sw.js` : service worker ; `manifest.webmanifest` et icônes ; `i18n/<langue>.json` : textes.
  - `js/` : scripts classiques chargés dans l'ordre de `index.html` (ils partagent `S`, l'état, et `A`, les actions) : `config` (Supabase, chemins du site), `core` (outils, langues, dates), `garden` (dessins), `rules` (routines dues, Mode vacances, badges, prix), `ui` (feuilles, rendu, connexion), `premium`, `parent`, `child`, `data` (chargements), `forms` (impression, formulaires), `actions`, `holidays`, `actions-parent`, `actions-family`, `boot`.
- Site publié : le contenu de `app/` est servi à la racine ; `guide/` et `vitrine/` à côté. Au passage au domaine : vitrine à la racine et app dans `/app/` (workflow et `PATHS` dans `app/js/config.js`).
- Données : projet Supabase « SoisFier ».

## Configuration (une seule fois)

1. Settings > Environments > `github-pages` : secrets `SUPABASE_URL` et `SUPABASE_KEY` (clé **anon** ou **publishable**, jamais `service_role`).
2. Settings > Pages > Source : **GitHub Actions**.
3. Pousser sur `main` : l'Action injecte les secrets et publie le site.
4. Supabase > Authentication > URL Configuration : mettre l'adresse GitHub Pages dans « Site URL » et « Redirect URLs ».

Le fichier `app/js/config.js` du dépôt contient des marqueurs `__SUPABASE_URL__` et `__SUPABASE_KEY__` : ouverte telle quelle, l'app affiche « Configuration manquante ».

## Mise à jour

Remplacer les fichiers et pousser. Si l'ancienne version reste affichée, incrémenter `CACHE` dans `app/sw.js`. Un nouveau fichier JS ou CSS doit aussi être ajouté à `CORE` dans `app/sw.js` (hors ligne).
