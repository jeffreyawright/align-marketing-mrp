# Phase 2 (deferred): ordinal upgrade for the funnel question set

**Status:** not started. Deferred out of the funnel binary-recode session
(2026-08-15) that added `country_offtrack`, `democracy_importance`,
`gov_few_interests`, `officials_dont_care`, `no_say` as binary fits. Do not
start this without a fresh session scoped to it.

## Scope, one line

Switch the engine from K binary cuts per question to a **cumulative (ordered)
logit** per question — category probabilities sum to 1 by construction, in
every cell and after poststratification.

## What it touches

- `python/fit.py`: cell probability becomes a K-vector instead of a scalar;
  per-category per-draw poststratification; per-category lookup columns;
  reliability tiers need rethinking per-category rather than as a single
  `ci_width` cut.
- `R/run_marketing_mrp.R`: mirrored via `brms::cumulative()`.
- `R/process_anes_2024.R`: the recode simplifies — drop `positive`/`negative`
  cut points, keep the factor levels in correct substantive order (already
  true for every question's `codes` vector).

## The open question this phase has to answer

A proportional-odds check, run before committing to the ordinal engine: does
per-category variation across cells reflect genuine personalization signal, or
is it just a finer framing of one latent dimension the binary cut already
captured? That check decides whether the ordinal upgrade is worth the
per-category machinery above, not just whether it's technically feasible.

## Sizing

Bounded engine change, not a rearchitecture. Compute is minutes (same fit
sizes as the binary models — ~4,900 rows, GPU poststrat under a second per
question). The cost is in the per-category plumbing through `fit.py`'s lookup
builder and the app's consumption of it, not in fit time.
