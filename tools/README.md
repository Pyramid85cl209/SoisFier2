# Outils (non déployés)

Exclus du site par `deploy.yml`. Nécessitent Python 3, Playwright (Chromium), Pillow, openpyxl, Node.

- `guide/` : captures du mode d'emploi par langue.
  - `data/<langue>.json` : textes fictifs (famille, enfant…), semaine, fuseau, légendes des captures.
  - `stub.js` : faux client Supabase ; `shots.py` : capture et cadres ; `scenes.py` : toutes les scènes (`SF_LANG=xx python3 scenes.py [noms]`).
  - Les trois guides (`guide/index.html`, `guide/en/index.html`, `guide/ar/index.html`) sont édités directement (EP-09) ; il n'y a plus de sources ni d'assemblage. Le style (`guide/guide.css`) et le script (sommaire, recherche, ancres, visionneuse : `guide/guide.js`) sont communs aux trois pages.
  - `check.py xx` : contrôle du guide (erreurs, images, débordement).
- `i18n/` : `REGLES.md` (règles de traduction), `check.py xx` (contrôle de `app/i18n/xx.json`), `review.py` (fichier de validation xlsx),
  `work/<langue>/` (fichiers de travail : `serveur.json` pour les astuces et rappels, `progression.md`).
- `vitrine/` : site vitrine provisoire (`vitrine/`, `vitrine/ar/`, `vitrine/en/`).
  - `build.py` : textes des trois langues et gabarit commun ; `style.css` : styles ; `python3 tools/vitrine/build.py` régénère les pages.
  - `shots.py` : captures sur données fictives (outillage du guide), `SF_LANG=xx python3 tools/vitrine/shots.py` ; polices via `SF_FONTS`.
