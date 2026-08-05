# Migration notes — internal

**Not a client document.** This records how this repository relates to the
`demographai-platform` repo it was extracted from. It exists to make prior
results reconcilable and to stop resolved defects from being reintroduced.

**Delete this file when:** all three marketing questions have been fit and
reconciled here, and nobody needs to compare against the platform's outputs
again. Nothing in `README.md`, `docs/methodology.md`, or the code depends on it.

---

## Provenance

Extracted from `demographai-platform/r-scoring`:

| Platform source | Became |
|---|---|
| `process_anes_2024.R` | `R/process_anes_2024.R` |
| `utils.R` | `R/utils.R` |
| `run_marketing_mrp.R` | `R/run_marketing_mrp.R` (retargeted — see below) |
| `run_marketing_mrp_jax.py` | `python/fit.py` |
| `data/cleaned_survey_data/country_track.csv` | port validation target |
| `data/census_tables/synthetic_frames_combined.rds` | imported to `data/frames/` |
| `mister_p.R` | **deliberately not ported** |

`mister_p.R` was the only dependency preventing the R fitting script from
running. `python/fit.py` already poststratifies per draw with the vintage guard,
so porting it would have created a second poststratification implementation
needing its own correctness maintenance.

## Port validation

`R/process_anes_2024.R` reproduces the platform's shipped
`country_track.csv` **byte-identically on all 4,841 shared respondents**, across
every demographic and outcome field, with zero rows added.

The only intentional difference is 60 dropped rows. Those respondents have a
missing congressional district, and the platform's `paste0(state, "-", cd)`
turned them into the literal string `"XX-NA"` — which survives an `is.na()`
filter and entered the model as 44 phantom districts. `format_cd()` in
`R/utils.R` keeps them `NA`.

This was a one-time check and is not re-runnable without the platform repo.
Ongoing drift detection is handled by `tests/verify_cleaned.sh`, which has no
external dependency.

`country_track` remains in `data/cleaned/` as the artifact of this comparison.
It is not one of the three marketing questions — at a 38.9-point partisan gap it
is close to a proxy for party ID. See `docs/methodology.md` §2.

## Defects found in the platform code

Fixed here; check any other consumer of the same sources.

- **`hispanic < 7` reads refusals as Hispanic.** The origin item is informative
  only for codes 1–6; negative missing codes are all `< 7`. Present in both the R
  and Python implementations. Latent in practice — all 28 affected respondents
  fail other completeness filters — but corrupts a category declared invariant.
- **`paste0()` on a missing district** produces `"ST-NA"`, which survives an
  `is.na()` filter. 60 rows, 44 phantom districts, in the shipped cleaned data.
- **Poststratification over stacked ACS vintages.** The frame holds both 2022
  (222,560 cells / 256.5M) and 2024 (187,193 / 340.8M). The platform script
  aggregated over both, weighting by a 597M "population" — roughly twice the
  adult total. **Every poststratified estimate it produced carries this.**
- **Draws collapsed to a posterior mean before writing cells**, making
  district-level credible intervals unrecoverable from its outputs.
- **Region mapping tested only row 0** (`df_clean['state'].iloc[0] in
  state_to_region`). If that one row's state failed to match, `region` stayed
  numeric for the entire dataset.
- **Undefined `mapping` object.** The policy-recoding and battery-aggregation
  loops referenced `mapping$variable` etc., which the script never defines — it
  came from `.RData` or an interactive session, so the script could not run cold.
  Not carried over; neither block fed these questions.
- Hardcoded `setwd()` calls and an unused `Hmisc` import. Not carried over.

## Reconciling with prior platform fits

`demographai-platform/models/marketing/` holds outputs for `facts`,
`gov_cares`, and `country_track` — arviz summaries plus ~33MB of poststratified
cell predictions each.

| Platform outcome | Relationship to this repo |
|---|---|
| `facts` | **Identical coding** to `basic_facts` (`1,2,3 → 0`; `4,5 → 1`). Directly comparable. |
| `country_track` | **Exact complement.** Platform coded `1 = Wrong track`; this repo codes `1 = Right direction`. Flip before comparing. |
| `gov_cares` | **Not comparable by flipping.** It cut V241235 as "Not much" = 1 vs "A good deal"/"Some" = 0, deliberately targeting the cynical/alienated. `election_efficacy` cuts the same item as "A good deal" = 1 vs "Some"/"Not much" = 0. Different cut points, not inverses — "Some" sits on the 0 side of both. |

Fitted variance components from the platform runs, which independently
corroborate the near-zero geographic clustering reported in
`docs/methodology.md` §7:

| σ (logit scale) | country_track | facts | gov_cares |
|---|---|---|---|
| state | 0.169 | **0.050** | 0.122 |
| region | 0.272 | 0.074 | 0.113 |
| educ | 0.801 | 0.886 | 0.696 |
| age_group | 0.457 | 0.246 | 0.411 |
| sex | 0.658 ±0.83 | 1.085 ±0.99 | 0.868 ±0.97 |

Geography is 5–17× smaller than demography.

**Validation result.** `python/fit.py` on `basic_facts` matches the platform's
`facts` fit on all 87 parameters to within 0.195 posterior standard deviations —
despite training on a slightly different row set (4,923 platform rows against
4,857 here, since the platform never required a non-missing district and carried
the `hispanic` defect).

Note this is a same-library comparison: bambi against bambi. It establishes that
the data plumbing is faithful, not that the model specification is right. The
independent check is `R/run_marketing_mrp.R --fit`, which fits the same
specification through brms/Stan — see `docs/methodology.md` §8.

## Architectural changes from the platform design

- The original plan had a hand-written NumPyro model, posterior draws exported
  to R, and poststratification in R (`models.py`, `export_posteriors.py`,
  `poststratify.R`). Superseded: `python/fit.py` fits and poststratifies in one
  place, so those files were never built.
- `python/fit.py` reads `data/cleaned/*.csv` rather than re-deriving
  demographics from the raw ANES file. The platform's Python script carried its
  own copy of every recode, which is how it acquired an independent instance of
  the `hispanic < 7` defect. One recode, in R, is the contract.
- `R/run_marketing_mrp.R` was retargeted from a second production pipeline to a
  specification artifact and cross-implementation check.
