-- =====================================================================
-- Fence 1 (2026-08-13): de-claim the four District 3-4 guild names for
-- launch. The originals (Mood Regulators / Estrogen Regulators /
-- Mitochondria Boosters / Tumor Preventors) read as health/disease
-- claims — the sharpest ("Tumor Preventors") is a cancer-prevention
-- claim under FDA/FTC and App Review scrutiny. No visible qualifier tag
-- renders (owner, 2026-07-02), so names must stand unqualified.
-- internal_name keys are unchanged; claim_risk stays true as the
-- RD-review ledger. Mirrors data/guilds.csv.
-- =====================================================================

update guilds set
  display_name  = 'The Messengers',
  function_copy = 'Makers of tryptophan and indole compounds — signal molecules on the gut–brain axis, one of the liveliest frontiers in microbiome research.',
  substantiation = '[renamed 2026-08-13 from "The Mood Regulators" — name de-claimed for launch] RD-REVIEW-REQUIRED: gut-brain axis is a real and active research field, but a direct food→mood causal claim is unproven in humans. Copy stays associational; never imply the app treats mood.'
where internal_name = 'mood_regulators';

update guilds set
  display_name  = 'The Alchemists',
  function_copy = 'A rare crew — roughly 1 in 3 people host them — that transmutes soy isoflavones into equol, a compound researchers study with growing interest.',
  substantiation = '[renamed 2026-08-13 from "The Estrogen Regulators" — name de-claimed for launch] RD-REVIEW-REQUIRED: equol-producer status is a real metabotype confirmed only by a urine test after a soy challenge, not by tracking intake. Phytoestrogen health effects are emerging, not established. No therapeutic claim.'
where internal_name = 'estrogen_regulators';

update guilds set
  display_name  = 'The Spark Tenders',
  function_copy = 'Urolithin makers: they transform ellagitannins from pomegranate, walnuts and berries into compounds under active study for cellular energy.',
  substantiation = '[renamed 2026-08-13 from "The Mitochondria Boosters" — name de-claimed for launch] RD-REVIEW-REQUIRED: urolithin-A benefits rest on early human trials and supplement studies, not whole-food outcomes. Producer status is a metabotype, not guaranteed by intake. No therapeutic claim.'
where internal_name = 'mitochondria_boosters';

update guilds set
  display_name  = 'The Lignan Weavers',
  function_copy = 'They weave plant lignans from flax, sesame and rye into enterolignans — one of the most-studied food-to-compound transformations in the gut.',
  substantiation = '[renamed 2026-08-13 from "The Tumor Preventors" — cancer-adjacent name removed for launch; FDA/FTC + app-review scrutiny] RD-REVIEW-REQUIRED: enterolignan evidence is associational only; keep all outcome language out of copy.'
where internal_name = 'tumor_preventors';
