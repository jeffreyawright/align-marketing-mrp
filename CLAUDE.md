# align-marketing-mrp

MRP (multilevel regression and poststratification) estimates of three ANES 2024
questions at congressional-district level, for marketing funnel targeting.
GPU-accelerated Bayesian inference via JAX/NumPyro.

**Read [`docs/methodology.md`](docs/methodology.md) before changing the model, the
recode, or the question set.** It carries the decisions and their rationale.
[`README.md`](README.md) is the user-facing entry point.

## The three questions

| Short name | ANES | Coded 1 when |
|---|---|---|
| `basic_facts` | V241327 | Very / Extremely important |
| `election_efficacy` | V241235 | A good deal |
| `congress_approval` | V241127 | Approve |

Selected for cross-partisan appeal — Dem–Rep gaps of 9.2, 12.4, and 4.6 points.
`country_track` (V241117) is also processed to `data/cleaned/` but is not modeled;
at a 38.9-point gap it is close to a proxy for party ID.

## Project structure

```
align-marketing-mrp/
├── README.md
├── CLAUDE.md
├── R/
│   ├── process_anes_2024.R       # ANES cleaning + recoding -> data/cleaned/
│   ├── utils.R                   # canonical categories, CD formatting, frame std.
│   └── run_marketing_mrp.R       # Stan spec artifact + brms cross-check
├── python/
│   ├── fit.py                    # GPU fit + poststratification -> data/estimates/
│   └── requirements.txt
├── data/
│   ├── raw/                      # ANES source (gitignored, imported)
│   ├── cleaned/                  # recoded survey data, one file per question
│   ├── frames/                   # ACS frame (gitignored, imported)
│   └── estimates/                # district and state estimates (output)
├── models/                       # fitted artifacts (gitignored)
├── docs/
│   ├── methodology.md            # specification, decisions, limitations
│   ├── README.md                 # reference material to import
│   ├── stan/                     # generated Stan programs
│   └── validation/               # cross-implementation checks
├── tests/
│   └── verify_cleaned.sh         # drift check on cleaned data
└── .gitignore
```

`R/build_poststrat_frame.R` does not exist yet. The ACS frame is currently
imported rather than built; see `docs/README.md`.

## Invariant demographic categories

Canonical across all ALIGN projects. Survey recode and ACS frame must use these
exact definitions — poststratification depends on cell-for-cell alignment, and a
mismatch fails silently rather than raising.

**Age groups:**
```r
cut(age, breaks = c(17, 24, 29, 34, 39, 44, 49, 54, 59, 64, 69, 74, 79, Inf),
    labels = c("18-24","25-29","30-34","35-39","40-44","45-49",
               "50-54","55-59","60-64","65-69","70-74","75-79","80 plus"))
```

**Sex:** Male, Female
**Race/ethnicity:** White, Black, Hispanic, Asian, Other (Hispanic-dominant)
**Education:** HS or less, Some College, BA/BS, Postgrad
**Region:** Northeast, Midwest, South, West, DC
**District:** `ST-XX`, at-large `ST-00`

These are defined once in `R/utils.R` (`.CANONICAL_*`) and mirrored in
`python/fit.py` (`CANONICAL`). Change both or neither.

## Model specification

```
target_binary ~ 1 + (1|age_group) + (1|sex) + (1|race) + (1|educ)
                  + (1|region) + (1|state)
```

Bernoulli likelihood, logit link.

**Priors — one specification, every implementation:** `exponential(1)` on
group-level standard deviations, `normal(0, 1.5)` on the intercept. Do not
substitute Half-Normal. `sigma_state` is ≈0.05, so the data is nearly
uninformative about the geographic variance components and the prior largely
*is* the posterior for them; a different family gives visibly different results
exactly where this project's geography lives.

`docs/stan/*.stan` is the authoritative written form — regenerate with
`Rscript R/run_marketing_mrp.R <question>` rather than hand-maintaining a copy.

**Use non-centered parameterization** in any reimplementation. The geographic
scales are near zero, and a centered `Normal(0, sigma)` on a group effect whose
`sigma` approaches zero produces Neal's funnel. Measured, same model: at
`target_accept = 0.9` centered gives 50% divergences, R-hat 2.08, ESS 3.

```python
z_age     = numpyro.sample("z_age", dist.Normal(0, 1).expand([n_age]))
alpha_age = numpyro.deterministic("alpha_age", z_age * sigma_age)
```

`(1 | cd)` is deliberately absent — see `docs/methodology.md` §6.
`python/fit.py --include-cd` enables it for testing.

## Convergence criteria

- R-hat < 1.05 for all parameters
- ESS (bulk and tail) > 400
- Divergences < 1% of post-warmup draws
- Visual posterior predictive check for at least one question

`python/fit.py` checks the first three and warns on failure. Use `arviz` in
Python, `posterior` in R.

## Commands

```bash
# Survey processing
Rscript R/process_anes_2024.R            # raw ANES -> data/cleaned/
tests/verify_cleaned.sh                  # confirm the recode has not drifted

# Fit + poststratify (production path)
pip install -r python/requirements.txt
python python/fit.py basic_facts
python python/fit.py congress_approval --draws 400 --tune 400 --chains 2  # smoke test

# Specification artifact and independent cross-check
Rscript R/run_marketing_mrp.R basic_facts          # -> docs/stan/ (seconds, no fit)
Rscript R/run_marketing_mrp.R basic_facts --fit    # -> docs/validation/
```

Raw ANES resolves in this order: `data/raw/`, `$ANES_2024_CSV`, then the local
path under `/mnt/data/Surveys/` on Skidrow.

## Critical rules

- **Never generate simulated survey data.** This project uses real ANES 2024 responses.
- **Raw ANES data stays in `data/raw/` and is gitignored.** Only cleaned/recoded data may be committed. The repo is private; cleaned files are respondent-level microdata governed by ANES terms.
- **The demographic categories above are invariant.** Do not add bins or merge categories.
- **ANES importance scales are not consistently oriented.** V241327 ascends (1 = Not important at all → 5 = Extremely important); V242180 descends. Reusing one Likert rule across importance items inverts one of them, and an inverted outcome fits cleanly while meaning the opposite — no diagnostic catches it. Check the codebook per item.
- **The ACS frame stacks multiple vintages** (2022 and 2024). Aggregating over both weights by ~2× the adult population. `python/fit.py --frame-year` guards this; anything else consuming the frame needs the same check.
- **One recode, in R.** Python reads `data/cleaned/*.csv`; it does not re-derive demographics from raw ANES. Duplicated recodes drift.
- **After changing the recode,** run `tests/verify_cleaned.sh --update` and commit the manifest with the change.
- **JAX GPU setup:** `python -c "import jax; print(jax.devices())"` should show a GPU device before fitting.
- **Model objects in `models/` are gitignored.** Commit diagnostics and summaries under `docs/` instead.

## Where the GPU matters

The fit is small — ~4,900 rows, 87 parameters — and the GPU is underutilized
there; roughly 1.8× over 4-core CPU rstan. **Poststratification is the
GPU-shaped work:** 187,193 frame cells × 6,000 draws, about a second on device.
Benchmark that step, not the fit.
