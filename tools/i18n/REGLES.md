# Règles de traduction SoisFier

Source : le français (`i18n/fr.json`, `guide/index.html`). Ces règles s'appliquent à toute nouvelle langue.

## Registre et genre
- **Textes destinés à l'enfant** (clés `kid`, `ctab`, `bloom`, `timer`, rappels enfant) :
  - si, dans la langue cible, la phrase à la 1re personne du singulier ou la 2e personne change selon le sexe de l'enfant (arabe, hébreu…), écrire à la **1re personne du pluriel** (« nous ») : elle ne marque pas le genre ;
  - sinon, garder la personne du français (« je » / « tu »).
- **Textes destinés aux parents** : forme de politesse de la langue (« vous »), en évitant les accords de genre quand la langue le permet.
- Pas de formulation genrée sur l'enfant ou le parent (« prêt/prête ») : reformuler.

## Forme
- Chiffres occidentaux (0-9) et calendrier grégorien, quelle que soit la langue (`-u-ca-gregory-nu-latn`).
- Ne pas traduire : `{variables}`, émojis, « SoisFier », codes `SF:…`.
- Pluriels : fournir **toutes** les formes de `Intl.PluralRules(langue)` pour chaque clé plurielle du français ; ajouter un pluriel quand la langue en a besoin même si le français n'en a pas (comme l'arabe pour les compteurs).
- Boutons et onglets courts : un onglet tient en 12 caractères environ ; vérifier à l'écran (captures).
- Ponctuation et guillemets de la langue cible (« » en français, “ ” en anglais, « » ou ” en arabe…).

## Vocabulaire figé (garder le même terme partout)
| Français | Sens |
|---|---|
| routine | tâche récurrente de l'enfant (en arabe : نشاط, « activité ») |
| routine exceptionnelle | tâche ponctuelle, sur une période |
| bonus | routine facultative, compte en plus |
| étoile | point gagné par une routine validée |
| étoile cassée / malus | étoile retirée pour un écart immédiat (jamais pour une routine oubliée) |
| valider / validation | confirmation par un adulte |
| quinzaine | période de 14 jours qui fait pousser une fleur |
| fleur, parterre, jardin | fleur = quinzaine, parterre = saison, jardin = année scolaire |
| défi chrono | minuteur d'une routine |
| récompense, événement | ce que l'on achète avec les étoiles ; événement = récompense datée |
| mode enfant, code parent | |

## Adaptation culturelle
- Liste des relations (`relations`) : garder les liens courants dans la culture cible (ex. retrait de parrain/marraine en arabe).
- Exemples du guide : prénoms fictifs neutres (« Enfant 1 »), fuseau et premier jour de semaine du pays principal de la langue.
- Astuces : adapter les exemples, garder le sens ; l'astuce n° 12 réserve l'étoile cassée aux écarts immédiats.

## Ce qui reste hors traduction (bêta)
- E-mails d'authentification Supabase : en anglais pour toutes les langues.

## Langues bloquées
- Langues dont l'écriture n'est pas couverte par les polices de l'application et du système sur Android/iOS courants (ex. géorgien) : refuser l'ajout.
