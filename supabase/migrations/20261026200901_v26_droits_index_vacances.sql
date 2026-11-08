-- v26 (point 18 de l'analyse) : appliquée par le connecteur le 26 octobre 2026 (version 20261026200901)
-- Fonctions parent du Mode vacances réservées aux comptes connectés (contrôle Parent interne inchangé)
revoke execute on function public.holiday_create(uuid, text, date, date, uuid) from public, anon;
revoke execute on function public.holiday_copy(uuid, uuid) from public, anon;
-- Index des liens enfant + période et enfant + famille du Mode vacances
create index if not exists holiday_overrides_period_child_idx on public.holiday_overrides (period_id, child_id);
create index if not exists holiday_periods_child_family_idx on public.holiday_periods (child_id, family_id);
