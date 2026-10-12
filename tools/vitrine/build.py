"""Vitrine provisoire : génère vitrine/index.html (fr), vitrine/ar/index.html et vitrine/en/index.html.
Usage : python3 tools/vitrine/build.py   (textes ci-dessous ; captures : tools/vitrine/shots.py)."""
import os, html

HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
LANGS = ["fr", "ar", "en"]
NAMES = {"fr": "Français", "ar": "العربية", "en": "English"}

T = {
"fr": dict(
  title="SoisFier – Les routines des enfants, une étoile à la fois",
  desc="SoisFier aide les familles à installer les routines du quotidien : l'enfant coche, un adulte valide, les étoiles font pousser une fleur et s'échangent contre des récompenses.",
  beta="Bêta", lang_label="Langue", guide="Mode d'emploi", open="Ouvrir", open_long="Ouvrir l'application", how_btn="Comment ça marche",
  h1="Les routines des enfants, <span>une étoile à la fois.</span>",
  lead="Se brosser les dents, préparer son cartable, se coucher à l'heure : ton enfant coche ce qu'il a fait, un adulte valide, et ses efforts deviennent visibles. Des étoiles, une fleur qui pousse, des récompenses qu'il attend avec impatience.",
  hero_alt="L'onglet Mon jardin de l'enfant : la fleur en cours dans son pot, puis son parterre de saison",
  how_h="Comment ça marche", how_sub="Quatre étapes, du choix des routines à la récompense.",
  steps=[("📋", "Tu choisis les routines", "Des modèles prêts à l'emploi ou tes propres routines, avec le nombre d'étoiles de chacune."),
         ("✅", "Ton enfant coche", "Sur son propre téléphone, sans compte, ou sur le tien en mode enfant."),
         ("⭐", "Un adulte valide", "Chaque routine validée rapporte ses étoiles. Les bonnes journées font pousser une fleur."),
         ("🎁", "Il choisit sa récompense", "Les étoiles s'échangent contre des récompenses, petites ou grandes, à son rythme.")],
  shots=[("aujourdhui", "Les routines du jour", "L'écran Aujourd'hui du parent, avec les routines du jour"),
         ("validation", "Validées par un adulte", "Les routines cochées, validées par un parent"),
         ("recompense", "Une récompense gagnée", "L'enfant vient d'échanger ses étoiles contre une récompense")],
  why_h="Pourquoi ça marche", why_sub="Une motivation qui se voit, des règles simples et les mêmes pour tous les adultes.",
  why=[("🌻", "Il voit ses progrès", "Chaque bonne journée fait grandir sa fleur."),
       ("🐷", "Il apprend à patienter", "Ses étoiles s'épargnent pour des récompenses, petites ou grandes."),
       ("🤝", "Une seule voix", "Parents, grands-parents ou nounou suivent et valident les mêmes routines.")],
  rules=[("✔️", "Un adulte valide", "Une étoile ne compte qu'une fois validée. Par défaut, ce que l'enfant coche est validé à minuit s'il n'a pas été refusé."),
         ("💪", "Pas besoin d'être parfait", "Une bonne journée, c'est au moins 75 % des étoiles du jour."),
         ("🌷", "Une fleur par quinzaine", "Plus belle selon le nombre de bonnes journées. Les fleurs forment un parterre chaque saison et un jardin chaque année scolaire."),
         ("⚖️", "Des récompenses à sa mesure", "Leur prix suit le rythme de chaque enfant."),
         ("🏖️", "Les imprévus ne pénalisent pas", "Vacances ou maladie : on met en pause, ces jours sont neutres."),
         ("📱", "Pas de compte pour l'enfant", "Un code donné par un parent suffit pour connecter son téléphone.")],
  guide_h="Mode d'emploi", guide_p="Installation, routines, récompenses, côté enfant et réglages, pas à pas et en images.", guide_btn="Lire le mode d'emploi",
  contact_h="Contact", contact_p="Une adresse de contact arrive bientôt.", soon="À venir",
  footer="SoisFier · version bêta · captures sur données fictives"),
"ar": dict(
  title="SoisFier – أنشطة الأطفال اليومية، نجمة بعد نجمة",
  desc="يساعد SoisFier العائلات على ترسيخ الأنشطة اليومية: يحدّد الطفل ما أنجزه، ويؤكّده أحد الكبار، فتُنمّي النجوم زهرة وتُستبدل بمكافآت.",
  beta="تجريبي", lang_label="اللغة", guide="دليل الاستخدام", open="فتح", open_long="فتح التطبيق", how_btn="كيف يعمل",
  h1="أنشطة الأطفال اليومية، <span>نجمة بعد نجمة.</span>",
  lead="تنظيف الأسنان، تجهيز الحقيبة المدرسية، النوم في الموعد: يحدّد طفلكم ما أنجزه، ويؤكّده أحد الكبار، فتصبح جهوده مرئية: نجوم، وزهرة تنمو، ومكافآت ينتظرها بشوق.",
  hero_alt="تبويب «حديقتنا» لدى الطفل: الزهرة الحالية في أصيصها، ثم حوض الفصل",
  how_h="كيف يعمل", how_sub="أربع خطوات، من اختيار الأنشطة إلى المكافأة.",
  steps=[("📋", "تختارون الأنشطة", "نماذج جاهزة أو أنشطتكم الخاصة، مع عدد النجوم لكل منها."),
         ("✅", "يحدّد طفلكم ما أنجزه", "على هاتفه الخاص دون حساب، أو على هاتفكم في وضع الطفل."),
         ("⭐", "أحد الكبار يؤكّد", "كل نشاط مؤكَّد يمنح نجومه. والأيام الجيدة تُنمّي زهرة."),
         ("🎁", "يختار مكافأته", "تُستبدل النجوم بمكافآت صغيرة أو كبيرة، حسب وتيرته.")],
  shots=[("aujourdhui", "أنشطة اليوم", "شاشة «اليوم» لدى الوالدين، مع أنشطة اليوم"),
         ("validation", "مؤكَّدة من أحد الكبار", "الأنشطة المحدّدة بعد أن أكّدها أحد الوالدين"),
         ("recompense", "مكافأة مستحقّة", "الطفل استبدل نجومه للتوّ بمكافأة")],
  why_h="لماذا ينجح ذلك", why_sub="تحفيز مرئي، وقواعد بسيطة وموحّدة لجميع الكبار.",
  why=[("🌻", "يرى تقدّمه", "كل يوم جيد يُنمّي زهرته."),
       ("🐷", "يتعلّم الصبر والادّخار", "يدّخر نجومه لمكافآت صغيرة أو كبيرة."),
       ("🤝", "صوت واحد", "الوالدان والأجداد والمربّية يتابعون الأنشطة نفسها ويؤكّدونها.")],
  rules=[("✔️", "أحد الكبار يؤكّد", "لا تُحتسب النجمة إلا بعد تأكيدها. افتراضيًا، يُؤكَّد ما حدّده الطفل عند منتصف الليل إن لم يُرفض."),
         ("💪", "لا داعي للكمال", "اليوم الجيد هو 75% على الأقل من نجوم اليوم."),
         ("🌷", "زهرة لكل فترة من أسبوعين", "أجمل كلما زادت الأيام الجيدة. تشكّل الزهور حوضًا في كل فصل وحديقة في كل سنة دراسية."),
         ("⚖️", "مكافآت على مقاسه", "يتبع سعرها وتيرة كل طفل."),
         ("🏖️", "الطوارئ لا تُعاقَب", "عطلة أو مرض: نبرمج توقّفًا، فتكون تلك الأيام محايدة."),
         ("📱", "لا حساب للطفل", "يكفي رمز يعطيه أحد الوالدين لربط هاتفه.")],
  guide_h="دليل الاستخدام", guide_p="التثبيت، والأنشطة، والمكافآت، وجهة الطفل، والإعدادات، خطوة بخطوة وبالصور.", guide_btn="قراءة الدليل",
  contact_h="التواصل", contact_p="عنوان للتواصل قريبًا.", soon="قريبًا",
  footer="SoisFier · نسخة تجريبية · الصور ببيانات وهمية · هذه الترجمة العربية في مرحلة المراجعة"),
"en": dict(
  title="SoisFier – Children's routines, one star at a time",
  desc="SoisFier helps families build everyday routines: the child ticks them off, an adult approves, and the stars grow a flower and are exchanged for rewards.",
  beta="Beta", lang_label="Language", guide="User guide", open="Open", open_long="Open the app", how_btn="How it works",
  h1="Children's routines, <span>one star at a time.</span>",
  lead="Brushing teeth, packing the school bag, going to bed on time: your child ticks off what they've done, an adult approves it, and their efforts become visible. Stars, a growing flower, and rewards they look forward to.",
  hero_alt="The child's My garden tab: the current flower in its pot, then the seasonal flower bed",
  how_h="How it works", how_sub="Four steps, from choosing the routines to the reward.",
  steps=[("📋", "You choose the routines", "Ready-made templates or your own routines, each with its number of stars."),
         ("✅", "Your child ticks them off", "On their own phone, with no account, or on yours in child mode."),
         ("⭐", "An adult approves", "Each approved routine earns its stars. Good days make a flower grow."),
         ("🎁", "They choose their reward", "Stars are exchanged for rewards, big or small, at their own pace.")],
  shots=[("aujourdhui", "Today's routines", "The parent's Today screen, with the day's routines"),
         ("validation", "Approved by an adult", "Ticked routines, approved by a parent"),
         ("recompense", "A reward earned", "The child has just exchanged their stars for a reward")],
  why_h="Why it works", why_sub="Motivation they can see, and simple rules that are the same for every adult.",
  why=[("🌻", "They see their progress", "Every good day makes their flower grow."),
       ("🐷", "They learn patience", "They save their stars for rewards, big or small."),
       ("🤝", "One voice", "Parents, grandparents or a nanny follow and approve the same routines.")],
  rules=[("✔️", "An adult approves", "A star only counts once it is approved. By default, what the child ticks is approved at midnight unless it has been declined."),
         ("💪", "No need to be perfect", "A good day means at least 75% of the day's stars."),
         ("🌷", "One flower per fortnight", "More beautiful with each good day. The flowers make a flower bed each season and a garden each school year."),
         ("⚖️", "Rewards that fit the child", "Their price follows each child's pace."),
         ("🏖️", "The unexpected isn't penalised", "Holiday or illness: schedule a break, and those days are neutral."),
         ("📱", "No account for the child", "A code given by a parent is enough to connect their phone.")],
  guide_h="User guide", guide_p="Installation, routines, rewards, the child's side and settings, step by step with screenshots.", guide_btn="Read the user guide",
  contact_h="Contact", contact_p="A contact address is coming soon.", soon="Coming soon",
  footer="SoisFier · beta · screenshots use fictitious data · This English translation is being reviewed"),
}

CSS = open(os.path.join(HERE, "style.css"), encoding="utf-8").read()

def page(lg):
    t = T[lg]; up = "../" if lg == "fr" else "../../"          # racine du site (l'app)
    here = "" if lg == "fr" else "../"                          # dossier vitrine/
    img = "img/"
    guide = up + "guide/" + ("" if lg == "fr" else lg + "/")
    rtl = lg == "ar"
    def href(l): return here + ("" if l == "fr" else l + "/")
    alt = "\n".join(f'<link rel="alternate" hreflang="{l}" href="{href(l) or "./"}">' for l in LANGS if l != lg)
    menu = "".join(f'<a href="{href(l) or "./"}" hreflang="{l}" lang="{l}"{" dir=\"rtl\"" if l == "ar" else ""}{" aria-current=\"page\"" if l == lg else ""}>{NAMES[l]}</a>'
                   for l in ["ar", "en", "fr"])
    steps = "\n".join(f'        <li><div class="ico" aria-hidden="true">{e}</div><h3>{h}</h3><p>{p}</p></li>' for e, h, p in t["steps"])
    shots = "\n".join(f'        <figure><img class="phone" src="{img}{n}.jpg" alt="{html.escape(a)}" width="440" height="914" loading="lazy" decoding="async"><figcaption>{c}</figcaption></figure>' for n, c, a in t["shots"])
    why = "\n".join(f'        <div><div class="ico" aria-hidden="true">{e}</div><h3>{h}</h3><p>{p}</p></div>' for e, h, p in t["why"])
    rules = "\n".join(f'        <li><span aria-hidden="true">{e}</span><div><strong>{h}</strong>{p}</div></li>' for e, h, p in t["rules"])
    return f"""<!doctype html>
<html lang="{lg}" dir="{"rtl" if rtl else "ltr"}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>{html.escape(t["title"])}</title>
<meta name="description" content="{html.escape(t["desc"])}">
<meta name="robots" content="noindex, nofollow"><!-- vitrine provisoire : à retirer au passage au domaine -->
<meta name="theme-color" content="#2E8B57">
<link rel="icon" href="{up}icon-192.png">
{alt}
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Atkinson+Hyperlegible:wght@400;700&family=Fredoka:wght@500;600&display=swap" rel="stylesheet">
<!-- Généré par tools/vitrine/build.py : modifier les textes là-bas -->
<style>
{CSS}</style>
</head>
<body>
<header class="bar">
  <div class="wrap">
    <a class="brand" href="./"><img src="{up}icon-192.png" alt="" width="32" height="32">SoisFier <span class="pill">{t["beta"]}</span></a>
    <details class="lang-menu"><summary class="btn ghost sm" aria-label="Language / Langue / اللغة">🌐<span class="long">&nbsp;{lg.upper()}</span></summary><div class="lang-pop">{menu}</div></details>
    <a class="btn ghost sm" href="{guide}" aria-label="{t["guide"]}"><span class="long">{t["guide"]}</span><span class="short" aria-hidden="true">?</span></a>
    <a class="btn sm" href="{up}" aria-label="{t["open_long"]}"><span class="long">{t["open_long"]}</span><span class="short">{t["open"]}</span></a>
  </div>
</header>

<main>
  <div class="hero">
    <div class="wrap">
      <div>
        <h1>{t["h1"]}</h1>
        <p class="lead">{t["lead"]}</p>
        <div class="cta">
          <a class="btn" href="{up}">{t["open_long"]}</a>
          <a class="btn ghost" href="#comment">{t["how_btn"]}</a>
        </div>
      </div>
      <img class="phone" src="{img}jardin.jpg" alt="{html.escape(t["hero_alt"])}" width="440" height="914">
    </div>
  </div>

  <section id="comment">
    <div class="wrap">
      <h2>{t["how_h"]}</h2>
      <p class="sub">{t["how_sub"]}</p>
      <ol class="steps">
{steps}
      </ol>
      <div class="shots">
{shots}
      </div>
    </div>
  </section>

  <section id="pourquoi">
    <div class="wrap">
      <h2>{t["why_h"]}</h2>
      <p class="sub">{t["why_sub"]}</p>
      <div class="why">
{why}
      </div>
      <ul class="rules">
{rules}
      </ul>
    </div>
  </section>

  <section id="aide">
    <div class="wrap">
      <div class="end">
        <div>
          <h3>📖 {t["guide_h"]}</h3>
          <p>{t["guide_p"]}</p>
          <a class="btn ghost" href="{guide}">{t["guide_btn"]}</a>
        </div>
        <div>
          <h3>✉️ {t["contact_h"]}</h3>
          <p>{t["contact_p"]}</p>
          <span class="soon">{t["soon"]}</span>
        </div>
      </div>
    </div>
  </section>
</main>

<footer>{t["footer"]}</footer>
<script>
// Ferme le menu de langue au clic à l'extérieur
document.addEventListener("click", e => {{ const m = document.querySelector(".lang-menu"); if (m && m.open && !m.contains(e.target)) m.open = false; }});
</script>
</body>
</html>
"""

for lg in LANGS:
    out = os.path.join(ROOT, "vitrine", "" if lg == "fr" else lg, "index.html")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    open(out, "w", encoding="utf-8").write(page(lg)); print(out)
