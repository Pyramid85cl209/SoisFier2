-- EP-09 thème C (3/3) : retraits des badges écrits par l'application (ADR-44, DT09-02). CONTIENT drop : ÉDITEUR SQL de Supabase (ADR-07),
-- après ep09c_badges_serveur, et SEULEMENT quand la nouvelle version de l'application est en ligne (l'ancienne appelle child_award_badges
-- et enregistre ses badges dans child_badges).
-- À tester dans une transaction annulée (supabase/tests/ep09c_badges_test.sql, cas finaux).
--
-- DT09-02  plus aucun membre n'enregistre un badge à la main : le serveur seul décide du mérite

drop function if exists public.child_award_badges(text, text[]);
drop policy if exists badges_insert on public.child_badges;
