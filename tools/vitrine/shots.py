"""Captures de la vitrine sur données fictives (outillage du guide), sans repères, dans un cadre de téléphone.
Usage : SF_LANG=xx python3 tools/vitrine/shots.py  ->  vitrine/img (fr) ou vitrine/xx/img.
Polices : SF_FONTS = dossier node_modules/@fontsource (npm i @fontsource/fredoka@5 @fontsource/atkinson-hyperlegible@5) ;
sans lui, police système (comme les captures du guide)."""
import asyncio, sys, base64, os, datetime
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "guide"))
import shots
shots.W, shots.H = 380, 780
from shots import Shots, LG
from PIL import Image
N = (os.environ.get("SF_FONTS") or "").rstrip("/") + "/"
F = {"fr500": N+"fredoka/files/fredoka-latin-500-normal.woff2", "fr600": N+"fredoka/files/fredoka-latin-600-normal.woff2",
     "at400": N+"atkinson-hyperlegible/files/atkinson-hyperlegible-latin-400-normal.woff2", "at700": N+"atkinson-hyperlegible/files/atkinson-hyperlegible-latin-700-normal.woff2"}
CSS = "".join(f"@font-face{{font-family:'{fam}';font-weight:{w};src:url(https://fonts.gstatic.com/{k}.woff2) format('woff2')}}"
              for k, fam, w in [("fr500","Fredoka",500),("fr600","Fredoka",600),("at400","Atkinson Hyperlegible",400),("at700","Atkinson Hyperlegible",700)])
orig = shots.route
async def route(r):
    u = r.request.url
    if "fonts.g" in u and not os.environ.get("SF_FONTS"): return await r.fulfill(body="", content_type="text/css")
    if "fonts.googleapis" in u: return await r.fulfill(body=CSS, content_type="text/css")
    if "fonts.gstatic" in u: return await r.fulfill(body=open(F[u.rsplit("/",1)[1].split(".")[0]],"rb").read(), content_type="font/woff2")
    return await orig(r)
shots.route = route
OUT = f"{ROOT}/vitrine/img" if LG == "fr" else f"{ROOT}/vitrine/{LG}/img"; os.makedirs(OUT, exist_ok=True)
FRAME = """<!doctype html><meta charset="utf-8"><style>body{margin:0}
.ph{width:300px;border:10px solid #232326;border-radius:30px;overflow:hidden;background:#000;display:inline-block}
.sb{height:26px;background:#2E8B57;color:#fff;display:flex;justify-content:space-between;align-items:center;padding:0 18px;font:600 12px system-ui,sans-serif}
.ph img{display:block;width:100%}.nav{height:34px;display:flex;justify-content:space-around;align-items:center;color:#fff;font:16px system-ui,sans-serif}
</style><div class="ph"><div class="sb"><span>9:41</span><span>▂▄▆ ▮</span></div><img src="data:image/png;base64,IMG"><div class="nav"><span>◁</span><span>○</span><span>□</span></div></div>"""
def d(n): return (datetime.date.today() + datetime.timedelta(days=n)).isoformat()
DONE = [{"child_id": "C1", "routine_id": r, "day": d(0), "stars": 1, "source": "child", "validated_at": d(0) + "T08:00:00Z", "validated_by": "U", "created_by": None} for r in ("R1", "R2", "R3", "R4")]
FLOWERS = """const g = S.cs.garden, yr = g.flowers.find(f => f.season === 'automne').garden_year;
  g.flowers = g.flowers.filter(f => f.season !== 'automne').concat([['cosmos-orange',3],['tournesol',2],['cosmos-rouge',3],['marguerite',3],['cosmos-orange',2]]
  .map(([sp, gr], i) => ({ id: 'fa' + i, species: sp, grade: gr, good_days: 10, active_days: 14, season: 'automne', garden_year: yr, period_start: g.today, period_end: g.today })));"""

async def main():
    async with Shots() as s:
        async def save(p, name):
            await p.evaluate("document.fonts.ready"); await p.wait_for_timeout(300)
            raw = f"/tmp/sf-vitrine-{LG}-{name}.png"; await p.screenshot(path=raw)
            ctx = await s.b.new_context(viewport={"width": 400, "height": 900}, device_scale_factor=440/320)
            q = await ctx.new_page(); await q.set_content(FRAME.replace("IMG", base64.b64encode(open(raw, "rb").read()).decode())); await q.wait_for_timeout(200)
            await q.locator(".ph").screenshot(path=raw + ".f.png", omit_background=True); await ctx.close()
            im = Image.open(raw + ".f.png"); bg = Image.new("RGB", im.size, (227, 241, 251)); bg.paste(im, mask=im.split()[3])
            bg.save(f"{OUT}/{name}.jpg", quality=84, optimize=True, progressive=True); print(name, bg.size, s.errs)
        p = await s.page(child=True)
        await s.act(p, FLOWERS + " A.ctab({ dataset: { tab: 'garden' } });", wait=500); await save(p, "jardin")
        await s.act(p, "A.ctab({ dataset: { tab: 'gifts' } }); A.cRedeem({ dataset: { id: 'W1' } }); closeSheet();"
                       "openSheet(`<h2>${t('kid.bravo')} ${S.cs.rewards[0].emoji}</h2><p>${t('kid.showParents', { title: S.cs.rewards[0].title })}</p><div class=\"sheet-actions\"><button class=\"btn\" data-act=\"closeSheet\">${t('kid.super')}</button></div>`); setTimeout(() => document.activeElement && document.activeElement.blur(), 50);", wait=600)
        await save(p, "recompense")
        p = await s.page(); await save(p, "aujourdhui")
        p = await s.page(ovr={"completions": DONE}); await save(p, "validation")
asyncio.run(main())
