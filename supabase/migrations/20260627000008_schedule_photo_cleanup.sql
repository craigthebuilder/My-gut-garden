-- Phase 2 follow-up: schedule the 5-day photo-retention sweep (Batch D).
-- `cleanup_expired_meal_photos()` (migration …000006) nulls `meals.photo_url`
-- once `photo_expires_at` (= captured_at + 5d, set by trigger) has passed, so the
-- app stops referencing/serving the image while ALL food data is kept.
--
-- NOTE: this removes the reference; reclaiming the underlying Storage bytes
-- (orphan GC) needs a scheduled Edge Function with the Storage API + service role,
-- which is a documented follow-up (pg_net/Edge), not wired here.

create extension if not exists pg_cron;

-- Idempotent: 3-arg cron.schedule upserts by jobname (pg_cron >= 1.4).
select cron.schedule(
  'cleanup-expired-meal-photos',
  '17 3 * * *',                                   -- daily at 03:17 UTC (low traffic)
  $$select public.cleanup_expired_meal_photos();$$
);
