-- =====================================================================
-- Guild bloom history (consolidation). The §13 district-unlock gates need
-- "has this guild EVER bloomed", but guild_state only stored the *current*
-- bloom_state. The MealIngestion coordinator sets this flag when a feeding
-- crosses into Blooming (GuildFeedingOutcome.crossedIntoBlooming). Additive.
-- =====================================================================

alter table guild_state add column has_ever_bloomed boolean not null default false;
