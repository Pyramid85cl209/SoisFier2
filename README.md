# SoisFier

Application familiale de routines pour enfants : étoiles validées par les parents, récompenses calibrées, jardin (une fleur par quinzaine, un parterre par saison, un jardin par an), sorties près de chez soi, rappels sur Android.

- Interface : PWA (`index.html`, `sw.js`, `manifest.webmanifest`) publiée sur GitHub Pages par la GitHub Action `deploy.yml`.
- Données : projet Supabase « SoisFier ».

## Configuration (une seule fois)

1. Settings > Environments > `github-pages` : secrets `SUPABASE_URL` et `SUPABASE_KEY` (clé **anon** ou **publishable**, jamais `service_role`).
2. Settings > Pages > Source : **GitHub Actions**.
3. Pousser sur `main` : l'Action injecte les secrets et publie le site.
4. Supabase > Authentication > URL Configuration : mettre l'adresse GitHub Pages dans « Site URL » et « Redirect URLs ».

Le fichier `index.html` du dépôt contient des marqueurs `__SUPABASE_URL__` et `__SUPABASE_KEY__` : ouvert tel quel, il affiche « Configuration manquante ».

## Mise à jour

Remplacer les fichiers et pousser. Si l'ancienne version reste affichée, incrémenter `CACHE` dans `sw.js`.
