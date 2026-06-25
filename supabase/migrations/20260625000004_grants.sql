-- =====================================================================
-- Table privileges for the Supabase API roles. RLS (20260625000002_rls.sql)
-- still governs WHICH ROWS each role sees; these GRANTs govern whether the
-- role may touch the table at all. Tables created by migrations don't always
-- inherit the project's default privileges, so we set them explicitly here.
--   service_role : full access + BYPASSRLS (used by the recognize Edge Function
--                  for the food-attribute join across all reference tables)
--   authenticated: SELECT/INSERT/UPDATE/DELETE, then narrowed by RLS to own rows
--   anon         : SELECT only (RLS reference policies are `to authenticated`,
--                  so anon still sees nothing — accounts are required, SPEC §3)
-- =====================================================================

grant usage on schema public to anon, authenticated, service_role;

grant select on all tables in schema public to anon;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant all privileges on all tables in schema public to service_role;

-- Keep future tables in this schema consistent.
alter default privileges in schema public grant select on tables to anon;
alter default privileges in schema public grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema public grant all on tables to service_role;
