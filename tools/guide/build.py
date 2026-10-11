"""Assemble guide/<langue>/index.html à partir de content/<langue>.html et data/<langue>.json,
puis met à jour les liens de langue dans l'en-tête de tous les guides (français compris).
Usage : python3 build.py xx      (xx ≠ fr ; le guide français est rédigé à la main)
Repères dans content/<langue>.html : {{fig:NOM|LÉGENDE}} (image de guide/<langue>/img), {{figfr:NOM|LÉGENDE}} (image du guide français)."""
import re, html, os, json, sys, glob
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
G = f"{ROOT}/guide"

def langs():
    """Langues dont le guide existe : {code: nom}."""
    out = {}
    for f in sorted(glob.glob(f"{HERE}/data/*.json")):
        d = json.load(open(f, encoding="utf-8")); c = d["lang"]
        if os.path.exists(f"{G}/index.html" if c == "fr" else f"{G}/{c}/index.html") or c == LG: out[c] = (d["name"], d.get("rtl", False))
    return out

LANG_CSS = (".lang-menu{position:relative}.lang-menu>summary{list-style:none;cursor:pointer}.lang-menu>summary::-webkit-details-marker{display:none}"
            ".lang-pop{position:absolute;inset-inline-end:0;top:calc(100% + 6px);z-index:40;min-width:150px;display:flex;flex-direction:column;gap:2px;"
            "background:var(--paper);border-radius:14px;padding:6px;box-shadow:0 4px 14px rgba(0,0,0,.18)}"
            ".lang-pop a{padding:8px 12px;border-radius:10px;text-decoration:none;color:var(--earth)}.lang-pop a:hover{background:var(--leaf-l)}"
            ".lang-pop a[aria-current]{font-weight:700;color:var(--leaf-d)}")

def lang_links(cur):
    """Menu des langues du guide cur (une entrée par guide existant)."""
    pre = "" if cur == "fr" else "../"
    items = "".join(f'<a href="{pre}{"" if c == "fr" else c + "/"}" hreflang="{c}" lang="{c}"{' dir="rtl"' if r else ""}{' aria-current="page"' if c == cur else ""}>{html.escape(n)}</a>'
                    for c, (n, r) in langs().items())
    return f'<details class="lang-menu"><summary class="btn" aria-label="Language / Langue / اللغة">🌐 {cur.upper()}</summary><div class="lang-pop">{items}</div></details>\n  '

def patch_links(path, cur):
    s = open(path, encoding="utf-8").read()
    s = re.sub(r'(?:<a class="btn lang-link"[^>]*>[^<]*</a>\s*)+', "", s)
    s = re.sub(r'<details class="lang-menu">.*?</details>\s*', "", s, flags=re.S)
    s = re.sub(r'(\n  )(<a class="btn" href="\.\./)', lambda m: m.group(1) + lang_links(cur) + m.group(2), s, count=1)
    s = re.sub(r"\.lang-link\{font-size:\.9rem\}\n(@media \(max-width:900px\)\{\.bar\{gap:6px;padding-inline:10px\}\.bar \.lang-link\{padding:8px 10px\}\}\n)?", "", s)
    if ".lang-menu{" not in s: s = s.replace("</style>", LANG_CSS + "\n</style>", 1)
    s = s.replace("document.querySelectorAll(\"figure a\")", "document.querySelectorAll(\"figure a\")", 1)
    open(path, "w", encoding="utf-8").write(s)

def build():
    D = json.load(open(f"{HERE}/data/{LG}.json", encoding="utf-8")); U = D["ui"]
    css = open(f"{HERE}/content/_style_fr.css.txt", encoding="utf-8").read()
    rep = [("border-right:2px solid var(--line)}\n.toc ol", "border-inline-end:2px solid var(--line)}\n.toc ol"),
           (".toc ul a{padding-left:42px", ".toc ul a{padding-inline-start:42px"), ("th,td{text-align:left", "th,td{text-align:start"),
           ("ol,ul{padding-left:1.4em}", "ol,ul{padding-inline-start:1.4em}"), (".top-link{position:fixed;right:16px", ".top-link{position:fixed;inset-inline-end:16px"),
           ("env(safe-area-inset-top,0px));right:12px;z-index:41", "env(safe-area-inset-top,0px));inset-inline-end:12px;z-index:41"),
           ("top:0;left:0;bottom:0;width:min", "top:0;inset-inline-start:0;bottom:0;width:min"),
           ("transition:transform .2s ease;border-right:2px", "transition:transform .2s ease;border-inline-end:2px"),
           ("padding:18px 12px 40px 16px", "padding-block:18px 40px;padding-inline:16px 12px")]
    for a, b in rep: assert a in css, a; css = css.replace(a, b)
    if D.get("rtl"): css = css.replace("transform:translateX(-105%)", "transform:translateX(105%)")
    css = css.replace("</style>", ".note{background:var(--sun-l);border-radius:16px;padding:12px 16px;font-size:.93rem}\n</style>")
    body = open(f"{HERE}/content/{LG}.html", encoding="utf-8").read()
    def fig(m):
        fr, name, alt = m.group(1), m.group(2), m.group(3)
        src = ("../img/" if fr else "img/") + name + ".jpg"
        w, h = Image.open(f"{G}/img/{name}.jpg" if fr else f"{G}/{LG}/img/{name}.jpg").size
        return (f'<figure><a href="{src}" target="_blank" rel="noopener"><img src="{src}" alt="{html.escape(alt, quote=True)}" width="{w}" height="{h}" '
                f'loading="lazy" decoding="async"></a><figcaption>{html.escape(alt)}</figcaption></figure>')
    body, n = re.subn(r"\{\{fig(fr)?:(\w+)\|([^}]*)\}\}", fig, body)
    toc = []
    for sid, num, title, inner in re.findall(r'<section class="part" id="(\w+)">\s*<h2><span class="num">([^<]*)</span>\s*([^<]*)</h2>(.*?)</section>', body, re.S):
        subs = "".join(f'<li><a href="#{i}">{t}</a></li>' for i, t in re.findall(r'<h3 id="([^"]+)">([^<]*)</h3>', inner))
        toc.append(f'<li><a href="#{sid}" class="p"><span class="num">{num}</span>{title.strip()}</a><ul>{subs}</ul></li>')
    tail = (open(f"{HERE}/content/_tail_fr.html.txt", encoding="utf-8").read().replace('aria-label="Revenir en haut"', f'aria-label="{U["top"]}"')
            .replace('aria-label="Capture agrandie"', f'aria-label="{U["zoom"]}"').replace("✕ Fermer", f'✕ {U["close"]}'))
    head = f'''<!doctype html>
<html lang="{LG}" dir="{"rtl" if D.get("rtl") else "ltr"}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>{U["title"]}</title>
<meta name="description" content="{html.escape(U["description"], quote=True)}">
<meta name="theme-color" content="#2E8B57">
<link rel="icon" href="../../icon-192.png">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Atkinson+Hyperlegible:wght@400;700&family=Fredoka:wght@500;600&display=swap" rel="stylesheet">
{css}
</head>
<body>
<header class="bar">
  <button class="btn menu-btn" id="menu" aria-expanded="false" aria-controls="toc">☰ {U["toc"]}</button>
  <span class="logo" aria-hidden="true">🌻</span>
  <h1>{U["title"]}</h1>
  <a class="btn" href="../../" aria-label="{U["back"]}">{U["back_arrow"]}<span class="back-txt"> {U["back"]}</span></a>
</header>
<div class="scrim" id="scrim"></div>
<div class="layout">
  <nav class="toc" id="toc" aria-label="{U["toc"]}"><ol>{"".join(toc)}</ol></nav>
  <main id="haut">
'''
    os.makedirs(f"{G}/{LG}", exist_ok=True)
    open(f"{G}/{LG}/index.html", "w", encoding="utf-8").write(head + body + "\n  </main>\n</div>\n" + tail)
    left = re.findall(r"\{\{[^}]*\}\}", body)
    print(f"{LG} : {n} figures, {len(toc)} parties, repères restants : {left}")

if __name__ == "__main__":
    LG = sys.argv[1]; assert LG != "fr", "le guide français est rédigé à la main"
    build()
    for c in langs(): patch_links(f"{G}/index.html" if c == "fr" else f"{G}/{c}/index.html", c)
