"""Contrôle d'un guide : erreurs JS, images cassées, débordement horizontal, captures ordinateur / mobile / menu.
Usage : python3 check.py xx   (fr = guide/ ; sinon guide/xx/). Captures dans /tmp/sf-guide-raw/check-xx-*.png"""
import asyncio, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault("SF_LANG", sys.argv[1] if len(sys.argv) > 1 else "fr")
from shots import route, CHROME, LG
from playwright.async_api import async_playwright

async def main():
    pw = await async_playwright().start(); b = await pw.chromium.launch(executable_path=CHROME); ok = True
    path = "guide/" if LG == "fr" else f"guide/{LG}/"
    for w, h, name in [(1280, 800, "desk"), (390, 800, "mob")]:
        c = await b.new_context(viewport={"width": w, "height": h}); p = await c.new_page(); errs = []
        p.on("pageerror", lambda e: errs.append(str(e)))
        await p.route("**/*", route); await p.goto(f"http://app.test/{path}"); await p.wait_for_timeout(500)
        bad = await p.evaluate("async()=>{const r=[];for(const i of document.querySelectorAll('figure img')){i.loading='eager';await i.decode().catch(()=>r.push(i.getAttribute('src')))}return r}")
        ov = await p.evaluate("()=>document.documentElement.scrollWidth-innerWidth")
        print(name, "erreurs", errs, "images cassées", bad, "débordement", ov); ok = ok and not errs and not bad and ov <= 0
        await p.screenshot(path=f"/tmp/sf-guide-raw/check-{LG}-{name}.png")
        if name == "mob":
            await p.click("#menu"); await p.wait_for_timeout(300); await p.screenshot(path=f"/tmp/sf-guide-raw/check-{LG}-menu.png")
        await c.close()
    await b.close(); await pw.stop(); print("OK" if ok else "À CORRIGER")
asyncio.run(main())
