-- =====================================================================
-- Keep-alive (2026-08-13): the free tier pauses after ~7 days without
-- API activity, and a paused backend takes the whole app down (it
-- happened today). pg_cron internal queries do NOT count as activity,
-- but an HTTP request to our own PostgREST endpoint does — so a daily
-- pg_net self-ping keeps the project awake with no external
-- dependency. The anon key is the same publishable key shipped in the
-- app binary. Remove this job once the project moves to the Pro plan
-- (which never pauses).
-- =====================================================================

create extension if not exists pg_net;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'supabase-keepalive') then
    perform cron.unschedule('supabase-keepalive');
  end if;
end $$;

select cron.schedule(
  'supabase-keepalive',
  '17 9 * * *',  -- daily, 09:17 UTC
  $$
  select net.http_get(
    url := 'https://bdzfjflfkvzxeyojfbkk.supabase.co/rest/v1/plants?select=id&limit=1',
    headers := '{"apikey": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJkemZqZmxma3Z6eGV5b2pmYmtrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODIzOTIxMTMsImV4cCI6MjA5Nzk2ODExM30.bMo7uqEtimBrJ2Ij7oeg-ekrTuBPQlpDGqe6eiN6fPI"}'::jsonb
  )
  $$
);
