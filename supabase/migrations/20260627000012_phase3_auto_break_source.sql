-- Phase 3 (Batch E): allow the reset auto-track to author a suspect.
-- During an active reset, eating a high-residue food + then logging unwell
-- auto-adds that food to "Checking" with a calm, removable note. It is NOT a
-- pattern-engine SUGGESTION (added_by='system') and NOT a user tap ('user'); it
-- gets its own source so the UI can show the "added automatically" note and the
-- user can remove it. Still never an exclusion, never an accumulating meter.
alter table food_suspects drop constraint if exists food_suspects_added_by_check;
alter table food_suspects add constraint food_suspects_added_by_check
  check (added_by in ('user', 'system', 'auto_reset_break'));
