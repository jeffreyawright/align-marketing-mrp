# align-marketing-mrp

R + Python project for MRP (multilevel regression and poststratification) modeling of three ANES 2024 survey questions selected for the MOVE marketing funnel. GPU-accelerated Bayesian inference via JAX/NumPyro on an RTX 4070 SUPER.

## What this does

Fits three hierarchical Bayesian models to ANES 2024 survey data, poststratifies predictions onto an ACS-derived population frame, and outputs congressional-district-level estimates of public opinion for marketing targeting.

## The three questions

Selected for **cross-partisan appeal**: a marketing funnel needs items that land with both the left and the right, so partisan gap is a selection criterion, not an afterthought.

| # | Short name | ANES variable | Question text | Binary coding |
|---|-----------|---------------|---------------|---------------|
| 1 | basic_facts | V241327 (`DEMNORMS_DEMFACTS`) | "How important is it that people agree on basic facts even if they disagree politically?" | 1 = Very/Extremely important, 0 = Moderately important or below |
| 2 | election_efficacy | V241235 (`RESPONS_ELECTCARE`) | "How much do you feel that having elections makes the government pay attention to what the people think?" | 1 = A good deal, 0 = Some / Not much |
| 3 | congress_approval | V241127 (`CONGAPP_CONGJOB`) | "Do you approve or disapprove of the way the U.S. Congress has been handling its job?" | 1 = Approve, 0 = Disapprove |

All three share the same model specification — only the outcome variable changes.

**`election_efficacy` measures external political efficacy** (is the system responsive to people like me), *not* diffuse support for democracy as a system. The ANES stem is `RESPONS_` for responsiveness. Treat it as a mobilization variable — it maps disengaged-but-reachable density — rather than an opinion measure. It is PRE-wave, so it is anchored to the pre-November-2024 context; external efficacy carries a known winner–loser gap and will shift after a change in power.

### Why these three, and what was dropped

Measured on the cleaned files, unweighted (design weights `V240107a` not applied); relative comparisons are robust to that, absolute levels less so.

| question | n | % positive | Dem | Ind | Rep | **D–R gap** | demographic range |
|---|---|---|---|---|---|---|---|
| basic_facts | 4857 | 74.7 | 80.5 | 55.4 | 71.4 | 9.2 | 22.5 |
| election_efficacy | 4871 | 29.5 | 36.4 | 15.6 | 23.9 | 12.4 | 24.4 |
| congress_approval | 4787 | 17.6 | 19.8 | 17.6 | 15.2 | **4.6** | 22.1 |
| ~~country_track~~ (dropped) | 4841 | 24.8 | 44.2 | 12.7 | 5.2 | **38.9** | 22.0 |
| ~~democracy_importance~~ (dropped) | 4038 | 93.0 | 97.3 | 79.0 | 89.9 | 7.4 | 8.8 |

- **`country_track` was dropped** as a marketing question: at a 38.9-point Dem–Rep gap it is close to a partisanship proxy in 2024, the opposite of cross-spectrum appeal. It is retained in the pipeline as a **validation fixture** only (see below).
- **`democracy_importance` was dropped**: POST-wave (loses ~500 respondents to `-6 No post interview`), ceiling-bound at 93% positive, and only an 8.8-point demographic range — little variance for the model to work with.
- **Independents invert the story.** On every democratic-norms item, pure Independents score *below both* partisan groups (basic_facts 55.4 vs 80.5/71.4). "Cross-partisan" here means *appeals to committed partisans of both stripes*; the disengaged middle is the outlier. If the funnel targets persuadable independents, these items describe the group least likely to respond to that framing.

### Two traps

**Scale direction is not consistent across ANES importance items.**

```
V241327 ASCENDS   1 = Not important at all  ... 5 = Extremely important
V242180 DESCENDS  1 = Extremely important   ... 5 = Not at all important
```

Never reuse one Likert rule across importance items without checking the codebook — a shared rule gets one of them exactly backwards.

**Cross-partisan appeal and targeting value pull against each other.** The property that makes an item bipartisan — everyone agrees — is the same property that kills its variance. `basic_facts` cut at top-two-vs-bottom-two is 93.1% positive with only a 3.2-point partisan gap: maximally bipartisan, useless for discriminating districts. The cut used here (Moderately important scores as non-endorsement) trades some of that neutrality for usable variance: 74.7% positive, 9.2-point gap. "Moderately important" is a lukewarm answer on an importance scale, not a neutral midpoint. Every response label is retained in the CSVs, so an alternative cut needs no reprocessing.

### What to expect from the district estimates

State-level intraclass correlation is ≈0 for all five items tested (method-of-moments, indistinguishable from zero). **None of these opinions cluster geographically beyond sampling noise.** Consequences:

- The `(1 | state)` and `(1 | cd)` intercepts will shrink almost entirely toward zero. That is the model working correctly, not a fitting failure — don't chase it with reparameterization.
- District estimates will be driven almost entirely by **demographic composition** through poststratification. The output is a demographic-composition map, not a discovery of regional pockets. Two districts with similar age/race/education profiles will get near-identical estimates.
- The "demographic range" column above is the best predictor of how much spread to expect across districts.

### The validation fixture

`country_track` is still processed to `data/cleaned/country_track.csv`, tagged `validation` rather than `marketing`. It is the regression anchor for the port from the platform repo: its output is **byte-identical on all 4841 shared respondents** to the platform's `data/cleaned_survey_data/country_track.csv`, across every demographic and outcome field.

The only intentional difference is 60 rows dropped. Those rows have a missing congressional district, and the platform's `paste0(state, "-", cd)` turned them into the literal string `"XX-NA"`, which survives an `is.na()` filter and enters the model as 44 phantom districts. `format_cd()` in `R/utils.R` keeps them NA.

Re-run the diff after any change to the recode. Delete `VALIDATION_QUESTIONS` in `R/process_anes_2024.R` to drop it.

## Tech stack

- **R:** Data processing, ACS frame construction, poststratification aggregation, output generation
- **Python (JAX/NumPyro):** GPU-accelerated MCMC inference (NUTS sampler)
- **Hardware:** Skidrow — Ryzen 9 7900, RTX 4070 SUPER (CUDA), Antigravity IDE

## Project structure

```
align-marketing-mrp/
├── CLAUDE.md
├── R/
│   ├── process_anes_2024.R       # [built] ANES cleaning + recoding -> data/cleaned/
│   ├── utils.R                   # [built] canonical categories, CD formatting, frame std.
│   ├── run_marketing_mrp.R       # [built] Stan spec artifact + brms cross-check
│   ├── build_poststrat_frame.R   # [todo] ACS poststratification frame construction
│   └── poststratify.R            # [todo] aggregate posteriors onto frame, output estimates
├── python/
│   ├── requirements.txt          # [built] jax[cuda12], numpyro, bambi, arviz, pyreadr
│   └── fit.py                    # [built] fit on GPU + poststratify -> data/estimates/
├── data/
│   ├── raw/                      # ANES 2024 source data (gitignored)
│   ├── cleaned/                  # recoded survey data
│   ├── frames/                   # ACS poststratification frames
│   └── estimates/                # final CD-level poststratified estimates (output)
├── models/                       # fitted model artifacts (gitignored)
├── docs/
│   ├── README.md                 # ANES reference material to import (PDFs gitignored)
│   └── methodology.md            # model specification, prior choices, diagnostics
└── .gitignore
```

## Invariant demographic categories

These categories are canonical across all ALIGN projects. Survey recode and ACS frame must use these exact definitions.

**Age groups:**
```r
cut(age, breaks = c(17, 24, 29, 34, 39, 44, 49, 54, 59, 64, 69, 74, 79, Inf),
    labels = c("18-24","25-29","30-34","35-39","40-44","45-49",
               "50-54","55-59","60-64","65-69","70-74","75-79","80 plus"))
```

**Gender:** male, female (modeled as `sex` in MRP formula)

**Race/ethnicity:** White (non-Hispanic), Hispanic, Black (nh), Asian (nh), Other (nh)

**Education:** HS or less, Some College, BA/BS, Postgrad

**Geography:**
- `census_division`: West, South, Midwest, Northeast, DC
- `state`: all 50 states + DC, ordered by state FIPS
- `CD`: congressional districts as "ST-XX" (e.g., "TX-32"). At-large as "ST-00".

## NumPyro model specification

Each question is a binary outcome (support/oppose) modeled as:

**Use non-centered parameterization.** The geographic variance components in this
project are near zero (see below), and a centered `Normal(0, sigma)` on a group
effect whose `sigma` approaches zero produces Neal's funnel — divergences and
collapsed ESS that no amount of `target_accept` fully fixes.

```python
def mrp_model(age, sex, race, edu, state, cd, y=None):
    # Group-level scales. Exponential(1), NOT HalfNormal -- see "Priors" below.
    sigma_age = numpyro.sample("sigma_age", dist.Exponential(1.0))

    # NON-CENTERED: sample standardized offsets, then scale.
    z_age     = numpyro.sample("z_age", dist.Normal(0, 1).expand([n_age]))
    alpha_age = numpyro.deterministic("alpha_age", z_age * sigma_age)
    # ... similarly for race, edu, state, (cd)

    # sex has 2 levels and region 5 -- a variance is not identifiable from 2
    # groups. Model sex as a fixed effect; treat region as a judgment call.
    beta_sex = numpyro.sample("beta_sex", dist.Normal(0, 1.5).expand([n_sex]))

    logit_p = alpha_age[age] + beta_sex[sex] + alpha_race[race] + \
              alpha_edu[edu] + alpha_state[state] + alpha_cd[cd]

    numpyro.sample("y", dist.Bernoulli(logits=logit_p), obs=y)
```

### Priors — one specification, three implementations

| | group-level sd | intercept |
|---|---|---|
| `python/fit.py` (bambi) | `Exponential(1)` | `Normal(0, 1.5)` |
| `R/run_marketing_mrp.R` (brms) | `exponential(1)` | `normal(0, 1.5)` |
| any hand-written NumPyro model | `Exponential(1)` | `Normal(0, 1.5)` |

**`exponential(1)` on group-level sds and `normal(0, 1.5)` on the intercept.**
Do not substitute Half-Normal. An earlier version of this document specified
`HalfNormal(1)` / `Normal(0, 2)`, matching neither running implementation, which
would have silently invalidated any cross-implementation comparison.

This matters more here than it usually would. `sigma_state` is ≈0.05, so the
data is nearly uninformative about the geographic variance components and the
prior largely *is* the posterior for them. Exponential(1) has a heavier right
tail than HalfNormal(1) and will give visibly different sigma estimates exactly
where this project's geography lives.

`docs/stan/*.stan` is the authoritative written form — regenerate it with
`Rscript R/run_marketing_mrp.R <question>` rather than hand-maintaining a copy.

### Is `(1 | cd)` worth including?

Open decision, and the evidence says probably not. Fitted `sigma_state` from the
prior JAX runs is 0.05–0.17 on the logit scale, and `sigma_cd` should be no
larger. Including it adds 435 parameters carrying ~11 respondents each — near-zero
contribution to the estimates, and the hardest part of the posterior to sample.

The poststratification frame is already CD-level (409,754 cells with `GEOID`,
`cd`, `pop`), so **district estimates are produced by demographic composition
within state whether or not the model has a `cd` term.** A state-level model
poststratified onto a CD-level frame is a defensible architecture here, not a
shortcut. Decide deliberately and record the choice in `docs/methodology.md`.

## Convergence criteria

- R-hat < 1.05 for all parameters
- ESS (bulk and tail) > 400
- Divergences < 1% of post-warmup draws
- Visual posterior predictive checks for at least one question

Use `arviz` for diagnostics in Python, or export draws to R and use `posterior` package.

## Prior JAX work in the platform repo

`demographai-platform/r-scoring/run_marketing_mrp_jax.py` already fits these
questions, and `demographai-platform/models/marketing/` holds the outputs
(`facts`, `gov_cares`, `country_track` — summaries plus ~33MB poststratified
predictions each). Reconcile against it rather than starting cold.

What it actually does, and how it differs from this repo's spec:

- **bambi, not hand-written NumPyro.** `bmb.Model(...).fit(inference_method="numpyro", chain_method="vectorized")`. Adds `pymc` + `pyreadr` dependencies.
- **No `cd` term.** `cd` is commented out; `demographics = [age_group, sex, race, educ, region, state]`. The 87-parameter count confirms it (1 + 13 + 2 + 5 + 4 + 5 + 51 + 6).
- **`target_accept=0.99`** — a band-aid for funnel divergences. Non-centered parameterization should let this drop toward 0.9.
- **Re-recodes from the raw CSV** rather than reading `data/cleaned/`, so it carries its own copy of every recode — including the same `hispanic < 7` defect fixed in `R/process_anes_2024.R`. Read the cleaned CSVs instead; that removes the whole duplicate-recode bug class.
- **Region mapping tests only row 0** (`df_clean['state'].iloc[0] in state_to_region`). If that row's state doesn't match, `region` silently stays numeric for the entire dataset.
- **No survey weights** (`V240107a`) in either implementation. Defensible — poststratification substitutes for weighting — but record it as a choice in `docs/methodology.md`, not an accident.
- **It poststratified over both ACS vintages at once.** The frame stacks 2022 and 2024; summing them gives a 597M "population," ~2x the adult total. Every estimate the platform script produced carries this. `python/fit.py --frame-year` guards it; `R/build_poststrat_frame.R` and any port of `mister_p.R` will need the same check. See `docs/README.md`.
- **It collapsed draws to a posterior mean before writing cells**, so district-level credible intervals cannot be recovered from its outputs. `python/fit.py` aggregates per draw instead.

Fitted variance components, which independently corroborate the ICC≈0 finding:

| σ (logit scale) | country_track | facts | gov_cares |
|---|---|---|---|
| state | 0.169 | **0.050** | 0.122 |
| region | 0.272 | 0.074 | 0.113 |
| educ | 0.801 | 0.886 | 0.696 |
| age_group | 0.457 | 0.246 | 0.411 |
| sex | 0.658 ±0.83 | 1.085 ±0.99 | 0.868 ±0.97 |

Geography is 5–17× smaller than demography. `sigma_sex` has a posterior sd at or
above its mean — prior-dominated, as expected from two groups.

### Comparing prior fits to this pipeline

| prior outcome | relationship to this repo |
|---|---|
| `facts` | **Identical coding** to `basic_facts` (`1,2,3 → 0`, `4,5 → 1`). Directly comparable — use it as the validation target. |
| `country_track` | **Exact complement.** Prior run coded `1 = Wrong track`; this repo codes `1 = Right direction`. Flip before comparing. |
| `gov_cares` | **Not comparable by flipping.** Different cut point, not an inverse — see "Not carried over" below. |

### Where the GPU speedup actually lives

The MCMC fit is small: ~4,900 rows and 87–522 parameters. The GPU is
underutilized there, and the win over cmdstanr is mostly vectorized chains plus
skipping Stan's compile step.

**The poststratification step is the GPU-shaped work.** 409,754 frame cells ×
6,000 posterior draws is ~2.5 billion evaluations per question. That is the real
bottleneck in the R pipeline (`mister_p` with `n_cores = 8`), and it is where an
order-of-magnitude-plus speedup is realistic. Benchmark that step, not the fit.

## Commands

```bash
# R pipeline
Rscript R/process_anes_2024.R          # clean and recode ANES -> data/cleaned/  [works]
Rscript R/build_poststrat_frame.R      # build ACS frame                         [todo]
Rscript R/poststratify.R               # aggregate posteriors, output estimates  [todo]

# Stan specification artifact -> docs/stan/  (seconds, no fitting)
Rscript R/run_marketing_mrp.R basic_facts
# + one-off brms fit and comparison against the JAX posterior -> docs/validation/
Rscript R/run_marketing_mrp.R basic_facts --fit

# Python/JAX pipeline
pip install -r python/requirements.txt   # JAX with CUDA + NumPyro + bambi
python python/fit.py basic_facts         # fit + poststratify on GPU  [works]
python python/fit.py election_efficacy --include-cd
python python/fit.py congress_approval --draws 400 --tune 400 --chains 2  # smoke test

# Full pipeline
bash run_all.sh                         # end-to-end: clean → fit → poststratify → output
```

Raw ANES resolves in this order: `data/raw/`, then `$ANES_2024_CSV`, then the known
local path `/mnt/data/Surveys/anes/data/2024/`.

## Critical rules

- **Never generate simulated survey data.** This project uses real ANES 2024 responses.
- **Raw ANES data stays in `data/raw/` and is gitignored.** Only cleaned/recoded data may be committed.
- **The demographic categories above are invariant.** Do not invent new bins or merge categories. The poststratification frame depends on exact alignment between survey recode and ACS frame.
- **JAX GPU setup:** Verify CUDA is available before fitting. `python -c "import jax; print(jax.devices())"` should show a GPU device.
- **If brms/Stan fits exist from prior work,** compare NumPyro posteriors against them as validation. Point estimates should agree within posterior uncertainty.
- **Model objects in `models/` are gitignored** — they're large binary artifacts. Commit convergence diagnostics and summary statistics in `docs/` instead.

## Origin

Ported from `r-scoring/run_marketing_mrp.R` and `r-scoring/process_anes_2024.R` in the demographai-platform repo. The brms/Stan inference backend is being replaced with JAX/NumPyro for GPU acceleration. The statistical model specification (varying intercepts by demographic and geographic groups, binary outcome, logit link) is identical.

### Two fitting paths, different jobs

- **`python/fit.py` is production.** Fits on GPU, poststratifies per draw onto the ACS frame with the vintage guard, emits district and state estimates with credible intervals.
- **`R/run_marketing_mrp.R` is a validation and documentation artifact.** It emits the generated Stan program and, with `--fit`, cross-checks the posterior against the JAX run. It does *not* poststratify.

**`mister_p.R` is deliberately not ported.** It was the only thing blocking the R script from running, and `python/fit.py` already poststratifies correctly and with uncertainty. Porting it would create a second poststratification implementation needing its own ACS-vintage guard — cost without benefit.

The cross-check matters because the existing validation of `python/fit.py` is bambi-against-bambi: same library, same sampler, same priors. That establishes the data plumbing is faithful, not that the model specification is right. brms/Stan is a genuinely different stack, so agreement across it is independent evidence.

Backtracking to a pure rstan workflow is cheap and does not require maintaining a standing brms path: `data/cleaned/*.csv` is ecosystem-neutral, and the model is six varying intercepts and two priors in any dialect. The expensive, defect-prone part — the recode — is already in R.

## Key source files from platform repo (for reference during extraction)

- `r-scoring/run_marketing_mrp.R` — brms pipeline for country_track (ported to `R/`)
- `r-scoring/process_anes_2024.R` — ANES loading and demographic recoding (ported to `R/`)
- `r-scoring/utils.R` — canonical demographic level definitions (ported to `R/utils.R`)
- `data/cleaned_survey_data/country_track.{csv,rds}` — validation target for the port
- `r-scoring/mister_p.R` — poststratification aggregator (**deliberately not ported**; `python/fit.py` supersedes it, see below)
- `data/census_tables/synthetic_frames_combined.rds` — ACS frame (**not yet ported**)
- Raw ANES 2024 source: `anes_timeseries_2024_csv_20250808.csv` (not in repo, on local disk)

### Not carried over from the platform script

- The `mapping`-driven policy recoding and battery aggregation loops. `mapping` was never defined in the source — it came from `.RData` or an interactive session, so the platform script cannot run cold. Neither block feeds these questions.
- `gov_cares` (from V241235). It cut the item as "Not much" = 1 vs "A good deal"/"Some" = 0 — deliberately, to target the cynical/alienated (see the comment in the platform's `run_marketing_mrp_jax.py`). `election_efficacy` cuts the same item the other way: "A good deal" = 1 vs "Some"/"Not much" = 0. **These are different cut points, not complements** — "Some" sits on the 0 side of both — so prior `gov_cares` posteriors cannot be compared to `election_efficacy` by flipping a sign.
- Hardcoded `setwd()` calls and the unused `Hmisc` import.
