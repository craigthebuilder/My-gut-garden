-- Phase 3 spine (2/3), Batch B: rainbow + phytochemical EDUCATION DEPTH.
--
-- 🔒 RD-REVIEW-REQUIRED (Fence 8, see FENCES.md): every deficiency_copy / what_it_does
-- string below is fenced, health-adjacent placeholder copy. Build the machinery now;
-- a registered dietitian validates the wording before launch. Gain-framed and
-- non-clinical per DESIGN "Writing"; never a diagnosis, never "you are deficient".

-- 1) Per-color "what going short could mean" (Batch B: deficiency depth on each color)
alter table colors add column deficiency_copy text;          -- RD-REVIEW-REQUIRED

update colors set deficiency_copy = 'Going light on reds can mean less lycopene and ellagic acid, polyphenols linked to heart and circulation and to feeding mucus-barrier crews in your gut.' where id = 'red';
update colors set deficiency_copy = 'Few orange foods means less alpha- and beta-carotene, the raw material your body turns into vitamin A for eyes, skin and immune signalling.' where id = 'orange';
update colors set deficiency_copy = 'Skip the yellows and you may miss lutein, zeaxanthin and a broad flavonoid mix that act as everyday antioxidants, with lutein concentrating in the eye.' where id = 'yellow';
update colors set deficiency_copy = 'Short on greens can mean less folate for methylation and fewer glucosinolates and chlorophyll from leafy and cruciferous plants.' where id = 'green';
update colors set deficiency_copy = 'Few blue and purple foods means less anthocyanin reaching the colon, where these deep-pigment polyphenols help feed barrier-keeping bacteria like Akkermansia.' where id = 'blue_purple';
update colors set deficiency_copy = 'Going without alliums and other white and brown plants means less organosulfur and prebiotic fiber, the fuel your Base Layer bifidobacteria rely on.' where id = 'white_brown';

-- 2) Phytochemical CATEGORIES (Batch B: category -> list -> compound hierarchy).
-- One row per phyto_class enum value; the field guide opens here, then drills in.
create table phyto_classes (
  id              phyto_class primary key,
  title           text not null,
  description     text not null,        -- RD-REVIEW-REQUIRED
  deficiency_copy text,                 -- RD-REVIEW-REQUIRED
  claim_risk      boolean not null default true
);

insert into phyto_classes (id, title, description, deficiency_copy) values
 ('carotenoid',   'Carotenoids',           'Fat-soluble orange, red and yellow pigments; some convert to vitamin A, others act as antioxidants that concentrate in the eye.', 'Low carotenoid intake can mean less vitamin-A raw material and less of the lutein and zeaxanthin that protect the eye.'),
 ('polyphenol',   'Polyphenols',           'The largest plant-compound family; many reach the colon intact and feed barrier-keeping bacteria while acting as antioxidants.', 'Few polyphenols means less of the colon-reaching fuel that helps barrier bacteria thrive.'),
 ('organosulfur', 'Organosulfur compounds','Sulfur-rich compounds from alliums and crucifers, released when you chop or chew them.', 'Skipping alliums and crucifers cuts the sulfur compounds tied to detox-enzyme and gut-signalling support.'),
 ('terpene',      'Terpenes',              'Aromatic compounds behind many herb and citrus scents, studied for antioxidant and signalling roles.', 'Going without aromatic herbs and citrus-peel oils means fewer of these aromatic antioxidants.'),
 ('phytosterol',  'Phytosterols',          'Plant cousins of cholesterol that compete with it for absorption in the gut.', 'Low phytosterol intake removes a plant compound studied for blocking some cholesterol absorption.'),
 ('saponin',      'Saponins',              'Soap-like compounds from legumes and some roots, studied for cholesterol-binding and immune signalling.', 'Few legumes means fewer saponins, compounds studied for binding cholesterol in the gut.'),
 ('alkaloid',     'Alkaloids',             'Nitrogen-containing compounds like the pungent piperine and capsaicin that can boost absorption and metabolism signalling.', 'Without pungent spices you miss alkaloids like piperine that can help you absorb other compounds.'),
 ('chlorophyll',  'Chlorophyll',           'The green pigment of leaves, studied for binding certain compounds as it passes through the gut.', 'Few leafy greens means little chlorophyll, the green pigment studied for its passage through the gut.'),
 ('betalain',     'Betalains',             'Red-violet pigments unique to beets and chard, distinct antioxidants from anthocyanins.', 'Skipping beets and chard means missing betalains, a red-violet antioxidant found almost nowhere else.');

-- 3) Per-compound "what it does" (Batch B: drill into a single phytochemical).
alter table phytochemicals add column what_it_does text;     -- RD-REVIEW-REQUIRED

update phytochemicals set what_it_does = 'An orange carotenoid your body converts to vitamin A for vision, skin and immune signalling.' where name = 'beta_carotene';
update phytochemicals set what_it_does = 'A carotenoid alongside beta-carotene that also yields some vitamin A.' where name = 'alpha_carotene';
update phytochemicals set what_it_does = 'The red carotenoid of tomatoes and watermelon, studied for heart and circulation support.' where name = 'lycopene';
update phytochemicals set what_it_does = 'A carotenoid that concentrates in the retina and is tied to eye protection.' where name = 'lutein';
update phytochemicals set what_it_does = 'Pairs with lutein in the macula of the eye as a protective antioxidant.' where name = 'zeaxanthin';
update phytochemicals set what_it_does = 'An orange carotenoid that can convert to vitamin A and is studied for bone and joint support.' where name = 'beta_cryptoxanthin';
update phytochemicals set what_it_does = 'Deep blue-purple polyphenols that reach the colon and feed barrier-keeping bacteria.' where name = 'anthocyanin';
update phytochemicals set what_it_does = 'A widespread flavonoid studied for antioxidant and histamine-steadying effects.' where name = 'quercetin';
update phytochemicals set what_it_does = 'A flavonoid from leafy greens and tea with antioxidant activity.' where name = 'kaempferol';
update phytochemicals set what_it_does = 'A green-tea flavanol studied for metabolism and vascular support.' where name = 'catechin';
update phytochemicals set what_it_does = 'The major green-tea catechin (EGCG), heavily studied as an antioxidant.' where name = 'epigallocatechin_gallate';
update phytochemicals set what_it_does = 'A polyphenol from berries and pomegranate studied for cell-protective effects.' where name = 'ellagic_acid';
update phytochemicals set what_it_does = 'A grape-skin polyphenol studied for vascular and longevity signalling.' where name = 'resveratrol';
update phytochemicals set what_it_does = 'A citrus flavonoid studied for blood-vessel and circulation support.' where name = 'hesperidin';
update phytochemicals set what_it_does = 'A grapefruit and citrus flavonoid with antioxidant activity.' where name = 'naringenin';
update phytochemicals set what_it_does = 'The yellow polyphenol of turmeric, studied for calming inflammatory signalling.' where name = 'curcumin';
update phytochemicals set what_it_does = 'A coffee and fruit polyphenol studied for blood-sugar and antioxidant effects.' where name = 'chlorogenic_acid';
update phytochemicals set what_it_does = 'A large pomegranate polyphenol gut bacteria break down into urolithins.' where name = 'punicalagin';
update phytochemicals set what_it_does = 'A soy isoflavone that acts as a mild phytoestrogen.' where name = 'genistein';
update phytochemicals set what_it_does = 'A flaxseed lignan gut bacteria convert into enterolactone.' where name = 'secoisolariciresinol';
update phytochemicals set what_it_does = 'The sulfur compound released when garlic is crushed, studied for antimicrobial effects.' where name = 'allicin';
update phytochemicals set what_it_does = 'A broccoli-sprout compound that switches on your own antioxidant defences.' where name = 'sulforaphane';
update phytochemicals set what_it_does = 'Cruciferous precursors that chewing converts into protective isothiocyanates.' where name = 'glucosinolate';
update phytochemicals set what_it_does = 'An aged-garlic sulfur compound studied for circulation support.' where name = 's_allyl_cysteine';
update phytochemicals set what_it_does = 'The citrus-peel terpene studied for antioxidant and digestive-soothing roles.' where name = 'limonene';
update phytochemicals set what_it_does = 'A rosemary and sage terpene with strong antioxidant activity.' where name = 'carnosic_acid';
update phytochemicals set what_it_does = 'The most common phytosterol, studied for blocking some cholesterol absorption.' where name = 'beta_sitosterol';
update phytochemicals set what_it_does = 'A soy saponin studied for binding cholesterol and bile in the gut.' where name = 'soyasaponin';
update phytochemicals set what_it_does = 'The pungent alkaloid of black pepper that boosts absorption of other compounds.' where name = 'piperine';
update phytochemicals set what_it_does = 'The heat compound of chillies, studied for metabolism and pain-signalling effects.' where name = 'capsaicin';
update phytochemicals set what_it_does = 'The green leaf pigment studied for binding certain compounds in the gut.' where name = 'chlorophyll';
update phytochemicals set what_it_does = 'The red-violet pigment of beets, a betalain antioxidant.' where name = 'betanin';

-- RLS + grants: reference tables (read = authenticated, write = service_role)
alter table phyto_classes enable row level security;
create policy phyto_classes_read on phyto_classes for select to authenticated using (true);
grant select on phyto_classes to authenticated;
grant all    on phyto_classes to service_role;
