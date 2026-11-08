-- Langue en : déclaration et astuces (ajouts seulement)
insert into public.languages(code, name, rtl, status) values ('en', 'English', false, 'review') on conflict (code) do nothing;
insert into public.tips(text, locale)
select t, 'en' from (values
  ('Praise the effort rather than the result: “You took the time to tidy up properly” motivates more than “You''re so good”.'),
  ('Three to five routines per time of day are enough. Any more and children lose interest.'),
  ('Let your child choose the order of their routines when possible: they feel in charge.'),
  ('Choose shared rewards (one more story, picking the film) over things: they strengthen your bond.'),
  ('A forgotten routine isn''t a failure. Tomorrow is a new day, with no blame.'),
  ('Lead by example: making your bed at the same time as your child is already halfway there.'),
  ('Describe what you see instead of judging: “I can see your shoes are put away!”'),
  ('For the youngest, one routine = one action. “Brush your teeth” rather than “Get ready”.'),
  ('Change a reward when it''s no longer exciting. Ask your child what they would enjoy.'),
  ('The timer turns a chore into a challenge. Use it for routines that drag on.'),
  ('In the evening, take two minutes to look at the plant together and talk about the day.'),
  ('Keep broken stars for immediate slips, never for a forgotten routine: the plant always stays a positive space.'),
  ('Add a bonus routine for little challenges: it gives stars with no pressure.'),
  ('Announce transitions in advance: “In five minutes, it''s bath time.”'),
  ('When a routine has been mastered for weeks, remove it and celebrate: your child has grown!')
) v(t)
where not exists (select 1 from public.tips where locale = 'en');
