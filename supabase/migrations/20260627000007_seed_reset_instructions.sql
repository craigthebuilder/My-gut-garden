-- Phase 2 spine (7/7), reset instruction placeholders. RD-REVIEW-REQUIRED (Fence 6):
-- the real elimination food list, reintroduction sequence, and durations are clinical
-- content and must be authored/validated by a registered dietitian before launch.
-- Copy here is intentionally generic and relief-framed (no "carnivore", no condition).

insert into reset_instructions (phase, sort_order, instruction_copy, food_suggestions, claim_risk) values
 ('reset',                0, 'RD-REVIEW-REQUIRED placeholder: give your gut a break, keep things very low-residue for now.', '{}', true),
 ('reintroduction_phase', 0, 'RD-REVIEW-REQUIRED placeholder: as you feel better, add gentle low-residue foods.', '{cooked vegetables,white rice}', true),
 ('graduated',            0, 'RD-REVIEW-REQUIRED placeholder: you are eating plenty of fiber, ready to move to Thrive.', '{}', true);
