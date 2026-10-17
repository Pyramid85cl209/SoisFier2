"""Contrôle d'un fichier de traduction app/i18n/xx.json par rapport à app/i18n/fr.json.
Vérifie : clés manquantes ou en trop, variables {x} identiques, formes de pluriel complètes (Intl.PluralRules via node),
textes restés identiques au français (à confirmer), présence de lang.xx dans toutes les langues.
Usage : python3 tools/i18n/check.py xx"""
import json, re, sys, subprocess, os, glob
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
LG = sys.argv[1]
fr = json.load(open(f"{ROOT}/app/i18n/fr.json", encoding="utf-8")); xx = json.load(open(f"{ROOT}/app/i18n/{LG}.json", encoding="utf-8"))
PL = {"zero", "one", "two", "few", "many", "other"}
def cats(l): return set(json.loads(subprocess.run(["node", "-e", f"console.log(JSON.stringify(new Intl.PluralRules('{l}').resolvedOptions().pluralCategories))"], capture_output=True, text=True).stdout))
def leaves(d, p=""):
    """Feuilles ; un objet dont toutes les clés sont des catégories de pluriel est une feuille plurielle."""
    out = {}
    for k, v in d.items():
        q = f"{p}.{k}" if p else k
        if isinstance(v, dict) and v and set(v) <= PL: out[q] = v
        elif isinstance(v, dict): out.update(leaves(v, q))
        else: out[q] = v
    return out
F, X = leaves(fr), leaves(xx); need = cats(LG); pb = 0
def vars_(v): return sorted(set(re.findall(r"\{\w+\}", json.dumps(v, ensure_ascii=False))))
for k in sorted(set(F) - set(X)): print("MANQUANTE", k); pb += 1
for k in sorted(set(X) - set(F)): print("EN TROP", k); pb += 1
for k in sorted(set(F) & set(X)):
    f, x = F[k], X[k]
    if isinstance(f, dict):
        if not isinstance(x, dict): print("PLURIEL ATTENDU", k); pb += 1; continue
        miss = need - set(x)
        if miss - {"zero"}: print("PLURIEL INCOMPLET", k, sorted(miss)); pb += 1
        elif miss: print("sans forme zero (repli sur other, à confirmer)", k)
        for c, v in x.items():
            if set(re.findall(r"\{\w+\}", v)) - set(vars_(f)): print("VARIABLE INCONNUE", k, c); pb += 1
    else:
        if isinstance(x, dict) and set(x) <= PL: x = x.get("other", "")
        if isinstance(f, list):
            if not isinstance(x, list) or len(x) != len(f): print("LISTE DE TAILLE DIFFÉRENTE", k); pb += 1
            continue
        if vars_(f) != vars_(x): print("VARIABLES DIFFÉRENTES", k, vars_(f), vars_(x)); pb += 1
        if isinstance(f, str) and f == x and len(f) > 3 and re.search(r"[a-zà-ÿ]{4}", f): print("IDENTIQUE AU FRANÇAIS (à confirmer)", k)
for f in glob.glob(f"{ROOT}/app/i18n/*.json"):
    if LG not in json.load(open(f, encoding="utf-8")).get("lang", {}): print("lang." + LG, "absent de", os.path.basename(f)); pb += 1
print(f"{len(X)} textes, catégories de pluriel {sorted(need)}, {pb} problème(s)")
sys.exit(1 if pb else 0)
