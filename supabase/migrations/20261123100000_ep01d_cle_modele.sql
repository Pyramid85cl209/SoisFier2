-- EP-01 lot D : clé du modèle sur la routine et la récompense (ADR-58, DEC-23, correctif A2 de la campagne de tests).
-- Addition seule, compatible avec la v32 et la v33 (les migrations A, B et C sont déjà en base) : deux colonnes facultatives, aucune fonction ni politique changée.
-- Une routine ou une récompense ajoutée depuis un modèle porte la clé `k` du modèle (TPL_R, TPL_W de app/js/rules.js) : « déjà ajoutée » ne dépend plus de la langue de l'ajout.
-- À tester dans une transaction annulée : supabase/tests/ep01d_cle_modele_test.sql.

alter table public.routines add column if not exists template_key text;
alter table public.rewards  add column if not exists template_key text;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'routines_template_key_check') then
    alter table public.routines add constraint routines_template_key_check check (template_key is null or template_key ~ '^[a-zA-Z0-9_]{1,40}$');
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rewards_template_key_check') then
    alter table public.rewards add constraint rewards_template_key_check check (template_key is null or template_key ~ '^[a-zA-Z0-9_]{1,40}$');
  end if;
end $$;

-- Remplissage de l'existant : correspondance exacte du titre (minuscules, espaces de bord retirés) avec le texte du modèle en français, en arabe ou en anglais
-- (textes recopiés de app/i18n/fr.json, ar.json, en.json : tpl.r.* pour les routines, tpl.w.* pour les récompenses). Clé laissée vide si aucun modèle ou plusieurs modèles correspondent.
-- Une clé déjà écrite n'est jamais changée. Les déclencheurs de routines et de récompenses ne portent pas sur cette colonne (réglages historisés : jours, bonus, étoiles ; plafond des prix : écrit à chaque modification, prix déjà conformes).
-- Routines (textes tpl.r.*)
with tpl(k, lang, txt) as (values
    ('teethMorning', 'fr', 'Se brosser les dents (matin)'),
    ('teethMorning', 'ar', 'تنظيف الأسنان (صباحًا)'),
    ('teethMorning', 'en', 'Brush your teeth (morning)'),
    ('face', 'fr', 'Se laver le visage'),
    ('face', 'ar', 'غسل الوجه'),
    ('face', 'en', 'Wash your face'),
    ('hair', 'fr', 'Se coiffer'),
    ('hair', 'ar', 'تسريح الشعر'),
    ('hair', 'en', 'Brush your hair'),
    ('hands', 'fr', 'Se laver les mains'),
    ('hands', 'ar', 'غسل اليدين'),
    ('hands', 'en', 'Wash your hands'),
    ('bath', 'fr', 'Prendre son bain'),
    ('bath', 'ar', 'الاستحمام'),
    ('bath', 'en', 'Have a bath'),
    ('shower', 'fr', 'Prendre sa douche'),
    ('shower', 'ar', 'الاستحمام تحت الدُّش'),
    ('shower', 'en', 'Take a shower'),
    ('teethEvening', 'fr', 'Se brosser les dents (soir)'),
    ('teethEvening', 'ar', 'تنظيف الأسنان (مساءً)'),
    ('teethEvening', 'en', 'Brush your teeth (evening)'),
    ('toilet', 'fr', 'Aller aux toilettes avant le dodo'),
    ('toilet', 'ar', 'الذهاب إلى الحمّام قبل النوم'),
    ('toilet', 'en', 'Go to the toilet before bed'),
    ('bed', 'fr', 'Faire son lit'),
    ('bed', 'ar', 'ترتيب السرير'),
    ('bed', 'en', 'Make your bed'),
    ('dress', 'fr', 'S''habiller'),
    ('dress', 'ar', 'ارتداء الملابس'),
    ('dress', 'en', 'Get dressed'),
    ('breakfast', 'fr', 'Prendre son petit-déjeuner'),
    ('breakfast', 'ar', 'تناول الفطور'),
    ('breakfast', 'en', 'Eat breakfast'),
    ('shoes', 'fr', 'Mettre ses chaussures'),
    ('shoes', 'ar', 'لبس الحذاء'),
    ('shoes', 'en', 'Put your shoes on'),
    ('pyjamas', 'fr', 'Mettre son pyjama'),
    ('pyjamas', 'ar', 'لبس البيجامة'),
    ('pyjamas', 'en', 'Put your pyjamas on'),
    ('clothesTomorrow', 'fr', 'Préparer ses habits pour demain'),
    ('clothesTomorrow', 'ar', 'تجهيز ملابس الغد'),
    ('clothesTomorrow', 'en', 'Lay out clothes for tomorrow'),
    ('schoolbag', 'fr', 'Préparer son cartable'),
    ('schoolbag', 'ar', 'تجهيز الحقيبة المدرسية'),
    ('schoolbag', 'en', 'Pack your school bag'),
    ('homework', 'fr', 'Faire ses devoirs'),
    ('homework', 'ar', 'حلّ الواجبات'),
    ('homework', 'en', 'Do your homework'),
    ('read', 'fr', 'Lire un livre'),
    ('read', 'ar', 'قراءة كتاب'),
    ('read', 'en', 'Read a book'),
    ('setTable', 'fr', 'Mettre le couvert'),
    ('setTable', 'ar', 'تجهيز المائدة'),
    ('setTable', 'en', 'Set the table'),
    ('clearPlate', 'fr', 'Débarrasser son assiette'),
    ('clearPlate', 'ar', 'رفع الصحن'),
    ('clearPlate', 'en', 'Clear your plate'),
    ('toys', 'fr', 'Ranger ses jouets'),
    ('toys', 'ar', 'ترتيب الألعاب'),
    ('toys', 'en', 'Tidy away your toys'),
    ('plants', 'fr', 'Arroser les plantes'),
    ('plants', 'ar', 'سقي النباتات'),
    ('plants', 'en', 'Water the plants'),
    ('pet', 'fr', 'Nourrir l''animal'),
    ('pet', 'ar', 'إطعام الحيوان الأليف'),
    ('pet', 'en', 'Feed the pet'),
    ('tidyRoom', 'fr', 'Ranger sa chambre'),
    ('tidyRoom', 'ar', 'ترتيب الغرفة'),
    ('tidyRoom', 'en', 'Tidy your room'),
    ('laundry', 'fr', 'Mettre le linge sale au panier'),
    ('laundry', 'ar', 'وضع الملابس المتسخة في السلة'),
    ('laundry', 'en', 'Put dirty clothes in the basket'),
    ('hello', 'fr', 'Dire bonjour, merci et s''il te plaît'),
    ('hello', 'ar', 'قول مرحبًا وشكرًا ومن فضلك'),
    ('hello', 'en', 'Say hello, thank you and please'),
    ('calm', 'fr', 'Parler calmement'),
    ('calm', 'ar', 'التحدث بهدوء'),
    ('calm', 'en', 'Speak calmly'),
    ('listen', 'fr', 'Écouter la première fois'),
    ('listen', 'ar', 'الإصغاء من أول مرة'),
    ('listen', 'en', 'Listen the first time'),
    ('help', 'fr', 'Aider quelqu''un de la maison'),
    ('help', 'ar', 'مساعدة أحد أفراد البيت'),
    ('help', 'en', 'Help someone at home'),
    ('prayerMorning', 'fr', 'Moment de prière ou de recueillement (matin)'),
    ('prayerMorning', 'ar', 'لحظة صلاة أو تأمل (صباحًا)'),
    ('prayerMorning', 'en', 'A moment of prayer or reflection (morning)'),
    ('prayerEvening', 'fr', 'Moment de prière ou de recueillement (soir)'),
    ('prayerEvening', 'ar', 'لحظة صلاة أو تأمل (مساءً)'),
    ('prayerEvening', 'en', 'A moment of prayer or reflection (evening)'),
    ('inspire', 'fr', 'Lire ou écouter un texte qui m''inspire'),
    ('inspire', 'ar', 'قراءة أو سماع نص يُلهمني'),
    ('inspire', 'en', 'Read or listen to something that inspires me'),
    ('thanks', 'fr', 'Dire merci pour un moment de ma journée'),
    ('thanks', 'ar', 'قول شكرًا على لحظة من يومي'),
    ('thanks', 'en', 'Say thank you for a moment of my day'),
    ('invocation', 'fr', 'Faire une invocation'),
    ('invocation', 'ar', 'قول دعاء'),
    ('invocation', 'en', 'Say a short prayer (invocation)')
)
update public.routines r set template_key = m.k
from (select x.id, min(t.k) as k, count(distinct t.k) as n
      from public.routines x join tpl t on lower(btrim(x.title)) = lower(btrim(t.txt))
      where x.template_key is null group by x.id) m
where m.id = r.id and m.n = 1;

-- Récompenses (textes tpl.w.*)
with tpl(k, lang, txt) as (values
    ('story', 'fr', 'Une histoire de plus'),
    ('story', 'ar', 'قصة إضافية'),
    ('story', 'en', 'One more story'),
    ('music', 'fr', 'Choisir la musique en voiture'),
    ('music', 'ar', 'اختيار الموسيقى في السيارة'),
    ('music', 'en', 'Choose the music in the car'),
    ('sticker', 'fr', 'Un autocollant'),
    ('sticker', 'ar', 'ملصق'),
    ('sticker', 'en', 'A sticker'),
    ('game', 'fr', 'Une partie de jeu avec papa ou maman'),
    ('game', 'ar', 'لعبة مع بابا أو ماما'),
    ('game', 'en', 'A game with Mum or Dad'),
    ('dessert', 'fr', 'Choisir le dessert'),
    ('dessert', 'ar', 'اختيار الحلوى'),
    ('dessert', 'en', 'Choose dessert'),
    ('bubbleBath', 'fr', 'Bain moussant avec jouets'),
    ('bubbleBath', 'ar', 'حمّام برغوة وألعاب'),
    ('bubbleBath', 'en', 'Bubble bath with toys'),
    ('lateBed', 'fr', '15 minutes de coucher plus tard'),
    ('lateBed', 'ar', 'النوم بعد 15 دقيقة من الموعد'),
    ('lateBed', 'en', 'Go to bed 15 minutes later'),
    ('cartoon', 'fr', 'Un dessin animé en plus'),
    ('cartoon', 'ar', 'رسوم متحركة إضافية'),
    ('cartoon', 'en', 'One more cartoon'),
    ('art', 'fr', 'Atelier dessin ou peinture ensemble'),
    ('art', 'ar', 'ورشة رسم أو تلوين معًا'),
    ('art', 'en', 'Drawing or painting together'),
    ('cake', 'fr', 'Faire un gâteau ensemble'),
    ('cake', 'ar', 'صنع كعكة معًا'),
    ('cake', 'en', 'Bake a cake together'),
    ('dinner', 'fr', 'Choisir le repas du soir'),
    ('dinner', 'ar', 'اختيار وجبة العشاء'),
    ('dinner', 'en', 'Choose what''s for dinner'),
    ('hut', 'fr', 'Cabane dans le salon'),
    ('hut', 'ar', 'خيمة في غرفة الجلوس'),
    ('hut', 'en', 'A den in the living room'),
    ('movie', 'fr', 'Soirée film en famille'),
    ('movie', 'ar', 'سهرة فيلم عائلية'),
    ('movie', 'en', 'Family film night'),
    ('picnic', 'fr', 'Pique-nique au parc'),
    ('picnic', 'ar', 'نزهة في الحديقة العامة'),
    ('picnic', 'en', 'Picnic in the park'),
    ('library', 'fr', 'Sortie à la médiathèque avec goûter'),
    ('library', 'ar', 'زيارة المكتبة مع وجبة خفيفة'),
    ('library', 'en', 'Trip to the library with a snack'),
    ('pool', 'fr', 'Après-midi à la piscine'),
    ('pool', 'ar', 'بعد الظهر في المسبح'),
    ('pool', 'en', 'Afternoon at the swimming pool'),
    ('farm', 'fr', 'Visite d''une ferme pédagogique'),
    ('farm', 'ar', 'زيارة مزرعة تعليمية'),
    ('farm', 'en', 'Visit to a children''s farm'),
    ('toy', 'fr', 'Un jouet ou équipement choisi'),
    ('toy', 'ar', 'لعبة أو أداة يختارها الطفل'),
    ('toy', 'en', 'A toy or piece of kit of your choice'),
    ('themePark', 'fr', 'Journée parc d''attractions'),
    ('themePark', 'ar', 'يوم في مدينة الألعاب'),
    ('themePark', 'en', 'Day at a theme park'),
    ('myDay', 'fr', 'Une journée « c''est moi qui décide »'),
    ('myDay', 'ar', 'يوم «أنا من يقرّر»'),
    ('myDay', 'en', 'An “I''m in charge” day')
)
update public.rewards w set template_key = m.k
from (select x.id, min(t.k) as k, count(distinct t.k) as n
      from public.rewards x join tpl t on lower(btrim(x.title)) = lower(btrim(t.txt))
      where x.template_key is null group by x.id) m
where m.id = w.id and m.n = 1;
