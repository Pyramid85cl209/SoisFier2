-- Test de la migration ep01d_cle_modele (EP-01 lot D, ADR-58, correctif A2), à coller dans l'éditeur SQL de Supabase : le fichier contient la migration D seule (A, B et C sont déjà en base), puis les cas (il se lance seul).
-- Tout se passe dans une transaction annulée : famille, enfant, routines et récompenses fictives ; rien n'est conservé. Résultat : une seule ligne d'erreur « RESULT: … ».
-- Attendu (dans l'ordre) :
--   D0.remplies : nombre de routines et de récompenses de la base qui reçoivent une clé par le remplissage (mesure, pas un seuil) ;
--   D1.routine_fr=bed D2.routine_en=bed D3.routine_ar=teethMorning D4.casse_espaces=bed D5.titre_libre=null ;
--   D6.recompense_fr=story D7.recompense_en=story D8.recompense_ar=story D9.recompense_libre=null ;
--   D10.cle_deja_la=garde (clé existante jamais changée) D11.ambigu=null D12.relance=0 (le remplissage rejoué ne change rien) ;
--   D13.format_refuse=ok (clé « mauvaise cle » et clé de 41 caractères refusées, routine et récompense) D14.sans_cle=ok (insertion de la v32, sans la colonne) D15.avec_cle=ok ;
--   D16.autres_colonnes=ok (titre, étoiles, jours, prix inchangés par le remplissage).
-- Lancé jusqu'ici sur une réplique locale du schéma (PostgreSQL 16), pas sur la base de production.
begin;
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

do $t$
declare fid uuid; c1 uuid; res text := ''; n_r bigint; n_w bigint; t_r bigint; t_w bigint; rid uuid; wid uuid; v text;
  tpl_fill text := $f$ with tpl(k, lang, txt) as (values ('a', 'fr', 'Un titre'), ('b', 'en', 'un titre '))
    update pg_temp.amb x set template_key = m.k from (select y.id, min(t.k) as k, count(distinct t.k) as n from pg_temp.amb y join tpl t on lower(btrim(y.title)) = lower(btrim(t.txt)) where y.template_key is null group by y.id) m where m.id = x.id and m.n = 1 $f$;
begin
  -- D0 : le remplissage a déjà eu lieu sur les lignes de la base (migration au-dessus) : combien en ont reçu une clé
  select count(*) filter (where template_key is not null), count(*) into n_r, t_r from public.routines;
  select count(*) filter (where template_key is not null), count(*) into n_w, t_w from public.rewards;
  res := res || ' D0.remplies=routines:' || coalesce(n_r, 0) || '/' || coalesce(t_r, 0) || ',recompenses:' || coalesce(n_w, 0) || '/' || coalesce(t_w, 0);

  insert into public.families(name, plan) values ('Famille test EP-01D', 'premium') returning id into fid;
  insert into public.children(family_id, name) values (fid, 'Enfant 1') returning id into c1;
  -- Lignes écrites avant la migration (sans clé), puis remplies par la même instruction que la migration : on rejoue donc le remplissage après les avoir créées
  insert into public.routines(family_id, child_id, title, moment, stars, days) values
    (fid, c1, 'Faire son lit', 'matin', 2, '{1,2,3}'), (fid, c1, 'Make your bed', 'matin', 1, '{1,2,3,4,5,6,7}'),
    (fid, c1, 'تنظيف الأسنان (صباحًا)', 'matin', 1, '{1,2,3,4,5,6,7}'), (fid, c1, '  fAire SON lit ', 'matin', 1, '{1,2,3,4,5,6,7}'),
    (fid, c1, 'Mon titre libre', 'matin', 1, '{1,2,3,4,5,6,7}');
  insert into public.routines(family_id, child_id, title, moment, template_key) values (fid, c1, 'Se coiffer', 'matin', 'maCle') returning id into rid;
  insert into public.rewards(family_id, title, cost, costs) values (fid, 'Une histoire de plus', 10, '{}'), (fid, 'One more story', 10, '{}'), (fid, 'قصة إضافية', 10, '{}'), (fid, 'Ma récompense libre', 10, '{}');
  insert into public.rewards(family_id, title, cost, costs, template_key) values (fid, 'Une musique', 10, '{}', 'autreCle') returning id into wid;
  -- Rejeu du remplissage de la migration sur ces lignes (la migration a déjà tourné avant leur création)
  execute $fill$
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
  $fill$;
  select coalesce(template_key, 'null') into v from public.routines where family_id = fid and title = 'Faire son lit';
  res := res || ' D1.routine_fr=' || coalesce(v, '?');
  select coalesce(template_key, 'null') into v from public.routines where family_id = fid and title = 'Make your bed'; res := res || ' D2.routine_en=' || coalesce(v, '?');
  select coalesce(template_key, 'null') into v from public.routines where family_id = fid and title = 'تنظيف الأسنان (صباحًا)'; res := res || ' D3.routine_ar=' || coalesce(v, '?');
  select coalesce(template_key, 'null') into v from public.routines where family_id = fid and title = '  fAire SON lit '; res := res || ' D4.casse_espaces=' || coalesce(v, '?');
  select coalesce(template_key, 'null') into v from public.routines where family_id = fid and title = 'Mon titre libre'; res := res || ' D5.titre_libre=' || coalesce(v, '?');
  select coalesce(template_key, 'null') into v from public.rewards where family_id = fid and title = 'Une histoire de plus'; res := res || ' D6.recompense_fr=' || coalesce(v, '?');
  select coalesce(template_key, 'null') into v from public.rewards where family_id = fid and title = 'One more story'; res := res || ' D7.recompense_en=' || coalesce(v, '?');
  select coalesce(template_key, 'null') into v from public.rewards where family_id = fid and title = 'قصة إضافية'; res := res || ' D8.recompense_ar=' || coalesce(v, '?');
  select coalesce(template_key, 'null') into v from public.rewards where family_id = fid and title = 'Ma récompense libre'; res := res || ' D9.recompense_libre=' || coalesce(v, '?');
  -- D10 : une clé déjà écrite n'est jamais changée (même si le titre est celui d'un autre modèle)
  select case when (select template_key from public.routines where id = rid) = 'maCle' and (select template_key from public.rewards where id = wid) = 'autreCle' then 'garde' else 'change' end into v;
  res := res || ' D10.cle_deja_la=' || coalesce(v, '?');
  -- D11 : deux modèles pour le même titre : clé laissée vide (même instruction sur une table temporaire ; aucun titre des dictionnaires n'est dans ce cas)
  create temporary table amb(id int, title text, template_key text) on commit drop;
  insert into pg_temp.amb values (1, 'Un titre', null), (2, 'Autre', null);
  execute tpl_fill;
  select coalesce(template_key, 'null') into v from pg_temp.amb where id = 1; res := res || ' D11.ambigu=' || coalesce(v, '?');
  -- D12 : le remplissage rejoué ne change aucune ligne
  select count(*) into n_r from public.routines where family_id = fid and template_key is not null;
  execute $fill$
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
  $fill$;
  res := res || ' D12.relance=' || coalesce((select count(*) from public.routines where family_id = fid and template_key is not null) - n_r, -1);
  -- D13 : format de la clé
  begin update public.routines set template_key = 'mauvaise cle' where id = rid; v := 'accepte'; exception when check_violation then v := 'refuse'; end;
  begin update public.routines set template_key = repeat('a', 41) where id = rid; v := v || '/accepte'; exception when check_violation then v := v || '/refuse'; end;
  begin update public.rewards set template_key = 'mauvaise cle' where id = wid; v := v || '/accepte'; exception when check_violation then v := v || '/refuse'; end;
  begin update public.rewards set template_key = repeat('a', 41) where id = wid; v := v || '/accepte'; exception when check_violation then v := v || '/refuse'; end;
  res := res || ' D13.format_refuse=' || case when v = 'refuse/refuse/refuse/refuse' then 'ok' else v end;
  -- D14, D15 : insertion sans la colonne (v32) et avec la colonne (v33 après l'application de la correction)
  begin insert into public.routines(family_id, child_id, title, moment) values (fid, c1, 'Ancienne version', 'matin'); insert into public.rewards(family_id, title, cost, costs) values (fid, 'Ancienne récompense', 5, '{}'); v := 'ok';
  exception when others then v := left(sqlerrm, 60); end; res := res || ' D14.sans_cle=' || coalesce(v, '?');
  begin insert into public.routines(family_id, child_id, title, moment, template_key) values (fid, c1, 'Nouvelle version', 'matin', 'face'); insert into public.rewards(family_id, title, cost, costs, template_key) values (fid, 'Nouvelle récompense', 5, '{}', 'story'); v := 'ok';
  exception when others then v := left(sqlerrm, 60); end; res := res || ' D15.avec_cle=' || coalesce(v, '?');
  -- D16 : le remplissage ne touche à aucune autre colonne
  select case when (select stars from public.routines where family_id = fid and title = 'Faire son lit') = 2 and (select days from public.routines where family_id = fid and title = 'Faire son lit') = '{1,2,3}'
    and (select cost from public.rewards where family_id = fid and title = 'Une histoire de plus') = 10 then 'ok' else 'modifie' end into v;
  res := res || ' D16.autres_colonnes=' || coalesce(v, '?');
  raise exception 'RESULT:%', coalesce(res, 'nul');
end $t$;
