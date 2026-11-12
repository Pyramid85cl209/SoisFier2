/* Mode d'emploi SoisFier : script commun aux trois guides (fr, en, ar). EP-09 thème G. */
(() => {
  const $ = (s, r = document) => r.querySelector(s), $$ = (s, r = document) => [...r.querySelectorAll(s)];
  const toc = $("#toc"), menu = $("#menu"), scrim = $("#scrim");
  const setOpen = o => { toc.classList.toggle("open", o); scrim.classList.toggle("open", o); menu.setAttribute("aria-expanded", o); };
  menu.addEventListener("click", () => setOpen(!toc.classList.contains("open")));
  scrim.addEventListener("click", () => setOpen(false));

  // ---- Aller à une ancre : la page se met en place (images chargées) avant et après le saut (DT14-11)
  let manual = false;
  ["wheel", "touchmove", "keydown"].forEach(ev => addEventListener(ev, () => { manual = true; }, { passive: true }));
  const place = id => { const el = document.getElementById(id); if (el) el.scrollIntoView({ block: "start", behavior: "instant" }); return el; };
  const go = (id, push) => {
    if (!document.getElementById(id)) return false;
    manual = false; place(id);
    if (push && location.hash !== "#" + id) history.pushState(null, "", "#" + id);
    const again = () => { if (!manual) place(id); };
    [150, 500, 1200].forEach(ms => setTimeout(again, ms));
    return true;
  };
  addEventListener("load", () => { if (location.hash.length > 1) { manual = false; place(decodeURIComponent(location.hash.slice(1))); setTimeout(() => { if (!manual) place(decodeURIComponent(location.hash.slice(1))); }, 400); } });
  addEventListener("hashchange", () => { if (location.hash.length > 1) go(decodeURIComponent(location.hash.slice(1)), false); });
  document.addEventListener("click", e => {
    const a = e.target.closest('a[href^="#"]'); if (!a || a.getAttribute("href").length < 2) return;
    const id = decodeURIComponent(a.getAttribute("href").slice(1));
    if (go(id, true)) { e.preventDefault(); setOpen(false); }
  });

  // ---- Sommaire : parties repliables
  const parts = $$("ol > li", toc).filter(li => li.querySelector(":scope > ul"));
  const pinned = new Set(), lab = { open: toc.dataset.open, close: toc.dataset.close };
  parts.forEach(li => {
    const a = $(":scope > a.p", li), ul = $(":scope > ul", li), row = document.createElement("div");
    const b = document.createElement("button"); b.type = "button"; b.className = "tog";
    row.className = "row"; li.insertBefore(row, a); row.append(a, b);
    li._ul = ul; li._btn = b; li._name = a.textContent.trim();
    b.addEventListener("click", () => { const o = ul.hidden; o ? pinned.add(li) : pinned.delete(li); show(li, o); });
  });
  const show = (li, o) => { li._ul.hidden = !o; li._btn.setAttribute("aria-expanded", o); li._btn.setAttribute("aria-label", (o ? lab.close : lab.open) + " : " + li._name); };
  let activePart = null;
  const syncToc = () => parts.forEach(li => show(li, pinned.has(li) || li === activePart));

  // ---- Sommaire actif
  const links = $$("a", toc).filter(a => a.hash), byId = new Map(links.map(a => [a.hash.slice(1), a]));
  const targets = $$("section.part, main h3[id]");
  let current = null;
  const mark = id => {
    if (id === current) return; current = id;
    links.forEach(a => a.classList.remove("on"));
    const a = byId.get(id); if (!a) return; a.classList.add("on");
    const li = a.closest("ol > li"); if (li) { li.querySelector("a.p").classList.add("on"); activePart = li; syncToc(); }
    if (!toc.classList.contains("open")) a.scrollIntoView({ block: "nearest" });
  };
  const upd = () => { const vis = targets.filter(t => t.getBoundingClientRect().top < 120); if (vis.length) mark(vis[vis.length - 1].id); else mark(targets[0].id); };
  addEventListener("scroll", upd, { passive: true }); upd(); syncToc();

  // ---- Recherche (fr, en, ar) : normalisation sans accents ni voyelles brèves
  const norm = s => s.normalize("NFD").replace(/\p{M}/gu, "").replace(/ـ/g, "")
    .replace(/[ٱ]/g, "ا").replace(/ى/g, "ي").replace(/ة/g, "ه")
    .replace(/[٠-٩]/g, d => d.charCodeAt(0) - 0x660).replace(/[’‘]/g, "'").replace(/œ/g, "oe").toLowerCase();
  let index = null;
  const build = () => {
    index = []; let part = "";
    $$("main section.part").forEach(sec => {
      const h2 = $("h2", sec); part = h2.textContent.replace(/\s+/g, " ").trim();
      let cur = { id: sec.id, title: part, part: "", text: "" }; index.push(cur);
      [...sec.children].forEach(el => {
        if (el.tagName === "H3" && el.id) { cur = { id: el.id, title: el.textContent.trim(), part, text: "" }; index.push(cur); }
        else if (el !== h2) cur.text += " " + el.textContent;
      });
    });
    index.forEach(e => { e.nt = norm(e.title); e.nx = norm(e.text); });
  };
  const q = $("#gq"), stat = $("#gstat"), list = $("#gres");
  const run = () => {
    const words = norm(q.value).split(/\s+/).filter(Boolean);
    list.textContent = "";
    if (!words.length) { stat.textContent = ""; return; }
    if (!index) build();
    const hits = index.map(e => {
      let sc = 0;
      for (const w of words) { const t = e.nt.includes(w), x = e.nx.includes(w); if (!t && !x) return null; sc += (t ? 5 : 0) + (x ? 1 : 0); }
      return { e, sc };
    }).filter(Boolean).sort((a, b) => b.sc - a.sc).slice(0, 20);
    if (!hits.length) { stat.textContent = toc.dataset.none; return; }
    stat.textContent = hits.length === 1 ? toc.dataset.one : toc.dataset.many.replace("{n}", hits.length);
    hits.forEach(({ e }) => {
      const li = document.createElement("li"), a = document.createElement("a"), s = document.createElement("small");
      a.href = "#" + e.id; a.textContent = e.title; s.textContent = e.part && e.part !== e.title ? e.part : "";
      a.append(s); li.append(a); list.append(li);
    });
  };
  q.addEventListener("input", run);
  q.addEventListener("keydown", e => { if (e.key === "Escape") { q.value = ""; run(); e.stopPropagation(); } });

  // ---- Visionneuse
  const v = $("#viewer"), vi = v.querySelector("img");
  $$("figure a").forEach(a => a.addEventListener("click", e => {
    e.preventDefault(); const t = a.querySelector("img"), r = t.naturalWidth / t.naturalHeight || 1;
    const w = Math.min(t.naturalWidth || 1400, Math.max(innerWidth - 24, (innerHeight - 90) * r));
    vi.style.width = w + "px"; vi.src = a.href; vi.alt = t.alt; v.classList.add("open"); v.scrollTo(0, 0);
  }));
  const close = () => v.classList.remove("open");
  $("#vclose").addEventListener("click", close);
  v.addEventListener("click", e => { if (e.target === v) close(); });
  addEventListener("keydown", e => { if (e.key === "Escape") { close(); setOpen(false); } });
})();
