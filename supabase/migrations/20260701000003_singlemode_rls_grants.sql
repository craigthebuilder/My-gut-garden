-- =====================================================================
-- Single-mode pivot — RLS + grants for the new tables.
-- Reuses the dynamic-loop patterns from 20260625000002_rls.sql and the
-- explicit grants from …0004_grants.sql (default privileges already cover
-- new tables; explicit grants are kept for parity + clarity).
-- =====================================================================

-- ---- Reference / content [seed]: read for authenticated, write = service_role
do $$
declare t text;
begin
  foreach t in array array['worlds', 'recipes', 'tutorial_steps']
  loop
    execute format('alter table public.%I enable row level security;', t);
    execute format(
      'create policy %I on public.%I for select to authenticated using (true);',
      t || '_read', t
    );
  end loop;
end $$;

-- ---- Per-user tables keyed directly on user_id: owner-only.
-- (check_in_prefs' PK is user_id; check_in_entries carries a direct user_id so
-- no parent-join policy is needed.)
do $$
declare t text;
begin
  foreach t in array array[
    'food_flags', 'user_worlds', 'tutorial_state',
    'check_in_prefs', 'check_ins', 'check_in_entries'
  ]
  loop
    execute format('alter table public.%I enable row level security;', t);
    execute format(
      'create policy %I on public.%I for all to authenticated '
      || 'using (user_id = (select auth.uid())) '
      || 'with check (user_id = (select auth.uid()));',
      t || '_owner', t
    );
  end loop;
end $$;

-- ---- Grants (parity with …0004_grants.sql)
grant select on public.worlds, public.recipes, public.tutorial_steps to anon, authenticated;
grant select, insert, update, delete on
  public.food_flags, public.user_worlds, public.tutorial_state,
  public.check_in_prefs, public.check_ins, public.check_in_entries to authenticated;
grant all on
  public.worlds, public.recipes, public.tutorial_steps,
  public.food_flags, public.user_worlds, public.tutorial_state,
  public.check_in_prefs, public.check_ins, public.check_in_entries to service_role;
