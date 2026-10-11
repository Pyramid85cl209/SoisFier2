"""Captures du mode d'emploi : écrans de l'app sur données fictives, repères numérotés, cadres de téléphone.
Langue : variable SF_LANG (défaut ar). Textes fictifs et légendes : data/<langue>.json."""
import asyncio, json, os, base64, sys
from playwright.async_api import async_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
LG = os.environ.get("SF_LANG", "ar")
D = json.load(open(f"{HERE}/data/{LG}.json", encoding="utf-8"))
OUT = f"{ROOT}/guide/img" if LG == "fr" else f"{ROOT}/guide/{LG}/img"; os.makedirs(OUT, exist_ok=True)
RAW = f"/tmp/sf-guide-raw/{LG}"; os.makedirs(RAW, exist_ok=True)
STUB = open(f"{HERE}/stub.js", encoding="utf-8").read()
import glob
CHROME = os.environ.get("SF_CHROME") or (sorted(glob.glob("/opt/pw-browsers/chromium-*/chrome-linux/chrome")) or [None])[-1]
SESSION = {"user": {"id": "U", "email": "parent@example.com", "user_metadata": {"display_name": D["member"]}}}
W, H = 360, 740

def C(name, i):
    """Légende n° i de l'image name (vide si absente)."""
    caps = D.get("captions", {}).get(name) or []
    return caps[i] if i < len(caps) else ""

def fixtures():
    tr = json.load(open(f"{ROOT}/i18n/{LG}.json", encoding="utf-8"))
    R, Wd, P, X, places = tr["tpl"]["r"], tr["tpl"]["w"], tr["tpl"]["p"], tr["tpl"]["x"], tr["places"]
    def routine(i, key, e, m, stars=1, days=(1, 2, 3, 4, 5, 6, 7), place=None, tm=None, bonus=False):
        return dict(id=f"R{i}", family_id="F", child_id="C1", title=R[key], emoji=e, moment=m, stars=stars, days=list(days), is_bonus=bonus,
                    timer_minutes=tm, place=places[place] if place is not None else None, kind="regular", active=True, created_at="2026-09-01T08:00:00Z", position=i)
    work = D["work_days"]
    routines = [routine(1, "bed", "🛏️", "matin", place=0), routine(2, "dress", "👕", "matin", place=0), routine(3, "breakfast", "🥣", "matin", place=2),
        routine(4, "teethMorning", "🪥", "matin", place=1, tm=2), routine(5, "schoolbag", "🎒", "matin", days=work, place=4),
        routine(6, "setTable", "🍽️", "midi", stars=2, place=2), routine(7, "toys", "🧸", "journee", stars=2, place=0, tm=10),
        routine(8, "homework", "✏️", "journee", stars=2, days=work, place=0), routine(9, "read", "📚", "journee", place=3, bonus=True),
        routine(10, "pyjamas", "🌙", "soir", place=0, tm=5), routine(11, "teethEvening", "🪥", "soir", place=1, tm=2), routine(12, "laundry", "🧺", "soir", place=1)]
    return json.dumps({"routines": routines, "X": X, "W": Wd, "P": P}, ensure_ascii=False)
FX = fixtures()

async def route(r):
    u = r.request.url
    if "supabase.min.js" in u: return await r.fulfill(body=STUB, content_type="application/javascript")
    if "fonts.g" in u: return await r.fulfill(body="", content_type="text/css")
    path = u.split("://", 1)[1].split("/", 1)[1].split("?")[0].split("#")[0] or "index.html"
    f = os.path.join(ROOT, path)
    if os.path.isdir(f): f = os.path.join(f, "index.html")
    if not os.path.exists(f): return await r.fulfill(status=404, body="")
    body = open(f, "rb").read()
    if path == "index.html":
        body = body.decode().replace("__SUPABASE_URL__", "https://x.supabase.co").replace("__SUPABASE_KEY__", "k").encode()
    ct = "text/html" if f.endswith(".html") else "application/json" if f.endswith(".json") else "application/javascript"
    await r.fulfill(body=body, content_type=ct)

class Shots:
    async def __aenter__(self):
        self.pw = await async_playwright().start()
        self.b = await self.pw.chromium.launch(executable_path=CHROME)
        return self
    async def __aexit__(self, *a):
        await self.b.close(); await self.pw.stop()

    async def page(self, session=True, child=False, ovr=None, rpc=None, h=H, js=""):
        ctx = await self.b.new_context(viewport={"width": W, "height": h}, device_scale_factor=2, locale=D["locale"], timezone_id=D["tz"])
        p = await ctx.new_page()
        self.errs = []
        p.on("pageerror", lambda e: self.errs.append(str(e)))
        await p.route("**/*", route)
        init = (f"localStorage.clear(); localStorage.setItem('sf:lang', JSON.stringify('{LG}')); window.__FXJSON = {FX}; window.__L = {json.dumps(D, ensure_ascii=False)};"
                f"window.__SESSION = {json.dumps(session and SESSION or None)}; window.__OVR = {json.dumps(ovr or {}, ensure_ascii=False)};"
                f"window.__RPC = {rpc or '{}'};"
                "navigator.serviceWorker && (navigator.serviceWorker.register = () => Promise.resolve());"
                "window.print = () => {}; navigator.vibrate = () => true;")
        if child: init += "localStorage.setItem('sf:childToken', JSON.stringify('tok')); localStorage.setItem('sf:lastEarned', '140'); localStorage.setItem('sf:seenFlowers', '5');"
        await p.add_init_script(init + js)
        await p.goto("http://app.test/index.html")
        await p.wait_for_timeout(600)
        if child:
            await p.wait_for_timeout(1900)
            await p.evaluate("() => { document.querySelectorAll('#confetti').forEach(e => e.remove()); const t = document.querySelector('#toast'); t.className = ''; }")
        await p.evaluate("() => { const s = document.createElement('style'); s.textContent = '#toast{transition:none} .bump,.hero-plant .sway{animation:none!important}'; document.head.appendChild(s); }")
        return p

    async def act(self, p, js, wait=250):
        await p.evaluate(f"(async () => {{ {js} }})()")
        await p.wait_for_timeout(wait)

    async def shot(self, p, name, marks=(), full=False, sheet=False, clip_to=None):
        """marks : liste de (sélecteur CSS, numéro[, index]) ; repère posé côté fin de ligne (à gauche en arabe)."""
        js = """(marks) => {
          document.querySelectorAll('.gmark').forEach(e => e.remove());
          const host = document.querySelector('dialog[open] .sheet-in') || document.body;
          for (const [sel, n, idx] of marks) {
            const els = [...document.querySelectorAll(sel)].filter(e => e.getClientRects().length);
            const el = els[idx || 0]; if (!el) { console.warn('repère introuvable', sel); continue; }
            const r = el.getBoundingClientRect();
            const m = document.createElement('div'); m.className = 'gmark'; m.textContent = n;
            const inDlg = !!el.closest('dialog[open]');
            const base = inDlg ? host.getBoundingClientRect() : { left: -scrollX, top: -scrollY };
            const sx = inDlg ? host.scrollLeft : 0, sy = inDlg ? host.scrollTop : 0;
            const small = r.width < 48;
            const x = (small ? r.left + r.width / 2 - 11 : Math.max(4, r.left - 26)) - base.left + sx;
            const y = (small ? r.bottom + 2 : r.top + r.height / 2 - 11) - base.top + sy;
            Object.assign(m.style, { position: 'absolute', left: x + 'px', top: y + 'px', width: '22px', height: '22px', borderRadius: '50%',
              background: '#E8484F', color: '#fff', font: '700 13px/22px sans-serif', textAlign: 'center', zIndex: 99, boxShadow: '0 0 0 2px #fff', direction: 'ltr' });
            if (inDlg) { host.style.position = 'relative'; host.appendChild(m); } else document.body.appendChild(m);
          }
        }"""
        await p.evaluate(js, [list(m) + ([0] if len(m) == 2 else []) for m in marks])
        await p.wait_for_timeout(120)
        path = f"{RAW}/{name}.png"
        if sheet:
            # fenêtre en entier : on agrandit la fenêtre à la hauteur de son contenu
            h = await p.evaluate("() => Math.ceil(document.querySelector('dialog[open] .sheet-in').scrollHeight) + 60")
            await p.set_viewport_size({"width": W, "height": max(H, h)})
            await p.evaluate("() => { const d = document.querySelector('dialog[open]'); d.style.maxHeight = 'none'; d.querySelector('.sheet-in').style.maxHeight = 'none'; }")
            await p.wait_for_timeout(150)
            await p.screenshot(path=path)
            await p.set_viewport_size({"width": W, "height": H})
        else:
            if full: await p.evaluate("() => { const t = document.querySelector('.tabbar'); if (t) t.style.position = 'static'; document.querySelector('.wrap') && (document.querySelector('.wrap').style.paddingBottom = '12px'); }")
            await p.screenshot(path=path, full_page=full)
        return path

    async def compose(self, out, items, width=None):
        """items : liste de (png, légende). Cadres de téléphone côte à côte, légende sous chaque téléphone."""
        cards = []
        for png, cap in items:
            b64 = base64.b64encode(open(png, "rb").read()).decode()
            cards.append(f'<figure><div class="ph"><div class="sb"><span>9:41</span><span>●●● ▮</span></div><img src="data:image/png;base64,{b64}"></div>'
                         + (f'<figcaption>{cap}</figcaption>' if cap else '') + '</figure>')
        html = f"""<!doctype html><html lang="{LG}" dir="{"rtl" if D.get("rtl") else "ltr"}"><meta charset="utf-8"><style>
          body{{margin:0;background:#E3F1FB;font:600 17px system-ui,sans-serif;color:#4A2E1F}}
          .row{{display:inline-flex;gap:26px;padding:22px 26px;align-items:flex-start}}
          figure{{margin:0;display:flex;flex-direction:column;align-items:center;gap:12px}}
          .ph{{width:300px;border:10px solid #1d1d1f;border-radius:30px;overflow:hidden;background:#000;box-shadow:0 4px 14px rgba(0,0,0,.18)}}
          .sb{{height:22px;background:#E3F1FB;display:flex;justify-content:space-between;align-items:center;padding:0 14px;font:600 11px sans-serif;color:#333;direction:ltr}}
          .ph img{{display:block;width:100%}}
          figcaption{{font-size:16px;max-width:300px;text-align:center}}
        </style><div class="row">{''.join(cards)}</div></html>"""
        ctx = await self.b.new_context(viewport={"width": 1600, "height": 900}, device_scale_factor=2)
        p = await ctx.new_page(); await p.set_content(html); await p.wait_for_timeout(200)
        el = p.locator(".row"); tmp = f"{RAW}/_c.png"
        await el.screenshot(path=tmp); await ctx.close()
        from PIL import Image
        im = Image.open(tmp).convert("RGB")
        target = width or (660 if len(items) == 1 else 1270 if len(items) == 2 else 1400)
        if im.width > target: im = im.resize((target, round(im.height * target / im.width)), Image.LANCZOS)
        im.save(f"{OUT}/{out}.jpg", quality=86, optimize=True, progressive=True)
        return im.size
