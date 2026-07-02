-- =====================================================================
-- 20260702000007_success_stories_singlemode.sql — retire the two-mode
-- 'Thrive user'/'Survive user' attributions + reintro-flavored stories
-- (owner sweep, 2026-07-02). Representative composites, verified=false,
-- wellness-only (SPEC §2/§6). Extracted from the regenerated seed.
-- (Supersedes 20260702000006, which was generated from the stale CSV;
-- that version list entry is repaired below.)
-- =====================================================================

-- ---- success_stories — delete+insert (idempotent). Truthful + representative;
--      no cherry-picked medical claims (SPEC §2). verified=false until real quote.
delete from success_stories;
insert into success_stories (text, attribution, verified) values
  ('Eating across more colors each week made hitting 30 plants feel like collecting, not a chore.', 'Early tester (representative)', false),
  ('I never knew how few different plants I was eating until the weekly count showed me. Now I hit thirty most weeks.', 'Early tester (representative)', false),
  ('The garden blooming when I kept feeding the same crews made the science click in a way a chart never did.', 'Early tester (representative)', false),
  ('The quiet heads-up that one food kept showing up on my rough days helped me spot a pattern I had missed for years.', 'Early tester (representative)', false),
  ('Snapping a photo instead of weighing and typing meant I actually kept logging past week one.', 'Early tester (representative)', false),
  ('Watching my energy trend up as my plant count grew was the nudge that kept me going.', 'Early tester (representative)', false);
