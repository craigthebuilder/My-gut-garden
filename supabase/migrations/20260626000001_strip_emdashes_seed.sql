-- Strip em dashes (U+2014) from served seed copy so the live DB matches the
-- cleaned /data CSVs (Phase 2, Batch A copy pass). The replacement mirrors the
-- CSV sweep: "—" -> ", ". Idempotent: a no-op on rows with no em dash, so it is
-- safe to re-run. Only prose `text` columns are touched (tag/array columns and
-- canonical names never carry em dashes).

update guilds set
  function_copy  = replace(function_copy,  '—', ', '),
  feeds_copy     = replace(feeds_copy,     '—', ', '),
  substantiation = replace(substantiation, '—', ', '),
  display_name   = replace(display_name,   '—', ', ');

update curiosity_facts set
  fact_text = replace(fact_text, '—', ', ');

update success_stories set
  text        = replace(text,        '—', ', '),
  attribution = replace(attribution, '—', ', ');

update colors set
  meaning_copy      = replace(meaning_copy,      '—', ', '),
  what_it_does_copy = replace(what_it_does_copy, '—', ', ');

update fibers set
  notes = replace(notes, '—', ', ');

update fodmap_profiles set
  serving_size_desc = replace(serving_size_desc, '—', ', ');

update districts set
  name = replace(name, '—', ', ');

update plants set
  scientific_name = replace(scientific_name, '—', ', '),
  plant_family    = replace(plant_family,    '—', ', ');
