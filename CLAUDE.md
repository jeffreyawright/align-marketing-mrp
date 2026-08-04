# align-marketing-mrp

R + Python project for MRP (multilevel regression and poststratification) modeling of three ANES 2024 survey questions selected for the MOVE marketing funnel. GPU-accelerated Bayesian inference via JAX/NumPyro on an RTX 4070 SUPER.

## What this does

Fits three hierarchical Bayesian models to ANES 2024 survey data, poststratifies predictions onto an ACS-derived population frame, and outputs congressional-district-level estimates of public opinion for marketing targeting.

## The three questions

| # | Short name | ANES variable | Question text | Binary coding |
|---|-----------|---------------|---------------|---------------|
| 1 | country_track | V241117 (`right_track`) | "Do you feel things in this country are generally going in the right direction, or have they pretty seriously gotten off on the wrong track?" | 1 = Right direction, 0 = Wrong track |
| 2 | congress_approval | V241127 (`congress_job`) | "Do you approve of how Congress is doing its job?" | 1 = Approve, 0 = Disapprove |
| 3 | democracy_importance | V242180 (`imp_democ`) | "How important is keeping the U.S. a democracy to the country today?" | 1 = Important (top responses), 0 = Not important (bottom responses) |

Question 1 (country_track) already has a working brms pipeline in the platform repo (`r-scoring/run_marketing_mrp.R`) and cleaned data (`data/cleaned_survey_data/country_track.{csv,rds}`). Questions 2 and 3 need the same ANES processing pipeline applied to their respective variables. All three share the same model specification — only the outcome variable changes.

## Tech stack

- **R:** Data processing, ACS frame construction, poststratification aggregation, output generation
- **Python (JAX/NumPyro):** GPU-accelerated MCMC inference (NUTS sampler)
- **Hardware:** Skidrow — Ryzen 9 7900, RTX 4070 SUPER (CUDA), Antigravity IDE

## Project structure

```
align-marketing-mrp/
├── CLAUDE.md
├── R/
│   ├── process_anes_2024.R       # ANES data cleaning and variable recoding
│   ├── build_poststrat_frame.R   # ACS poststratification frame construction
│   ├── poststratify.R            # aggregate posteriors onto frame, output estimates
│   └── utils.R                   # shared helpers (category definitions, CD formatting)
├── python/
│   ├── requirements.txt          # jax[cuda], numpyro, arviz
│   ├── models.py                 # NumPyro model definitions (MRP specification)
│   ├── fit.py                    # MCMC fitting script (GPU)
│   └── export_posteriors.py      # export posterior draws to CSV/RDS for R
├── data/
│   ├── raw/                      # ANES 2024 source data (gitignored)
│   ├── cleaned/                  # recoded survey data
│   ├── frames/                   # ACS poststratification frames
│   └── estimates/                # final CD-level poststratified estimates (output)
├── models/                       # fitted model artifacts (gitignored)
├── docs/
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

```python
def mrp_model(age, sex, race, edu, state, cd, y=None):
    # Priors on group-level effects (varying intercepts)
    sigma_age = numpyro.sample("sigma_age", dist.HalfNormal(1.0))
    alpha_age = numpyro.sample("alpha_age", dist.Normal(0, sigma_age).expand([n_age]))
    # ... similarly for sex, race, edu, state, cd

    # Linear predictor
    logit_p = alpha_age[age] + alpha_sex[sex] + alpha_race[race] + \
              alpha_edu[edu] + alpha_state[state] + alpha_cd[cd]

    # Likelihood
    numpyro.sample("y", dist.Bernoulli(logits=logit_p), obs=y)
```

Prior choices should follow Gelman et al. conventions for MRP. Half-Normal(1) on group-level standard deviations. Weakly informative Normal(0, 2) on fixed intercept if included.

## Convergence criteria

- R-hat < 1.05 for all parameters
- ESS (bulk and tail) > 400
- Divergences < 1% of post-warmup draws
- Visual posterior predictive checks for at least one question

Use `arviz` for diagnostics in Python, or export draws to R and use `posterior` package.

## Commands

```bash
# R pipeline
Rscript R/process_anes_2024.R          # clean and recode ANES data
Rscript R/build_poststrat_frame.R      # build ACS frame
Rscript R/poststratify.R               # aggregate posteriors, output estimates

# Python/JAX pipeline
pip install -r python/requirements.txt  # install JAX with CUDA + NumPyro
python python/fit.py --question 1       # fit model for question 1 on GPU
python python/export_posteriors.py      # export draws for R poststratification

# Full pipeline
bash run_all.sh                         # end-to-end: clean → fit → poststratify → output
```

## Critical rules

- **Never generate simulated survey data.** This project uses real ANES 2024 responses.
- **Raw ANES data stays in `data/raw/` and is gitignored.** Only cleaned/recoded data may be committed.
- **The demographic categories above are invariant.** Do not invent new bins or merge categories. The poststratification frame depends on exact alignment between survey recode and ACS frame.
- **JAX GPU setup:** Verify CUDA is available before fitting. `python -c "import jax; print(jax.devices())"` should show a GPU device.
- **If brms/Stan fits exist from prior work,** compare NumPyro posteriors against them as validation. Point estimates should agree within posterior uncertainty.
- **Model objects in `models/` are gitignored** — they're large binary artifacts. Commit convergence diagnostics and summary statistics in `docs/` instead.

## Origin

Ported from `r-scoring/run_marketing_mrp.R` and `r-scoring/process_anes_2024.R` in the demographai-platform repo. The brms/Stan inference backend is being replaced with JAX/NumPyro for GPU acceleration. The statistical model specification (varying intercepts by demographic and geographic groups, binary outcome, logit link) is identical.

## Key source files from platform repo (for reference during extraction)

- `r-scoring/run_marketing_mrp.R` — existing brms pipeline for country_track (Question 1)
- `r-scoring/process_anes_2024.R` — ANES 2024 data loading and demographic recoding
- `r-scoring/utils.R` — canonical demographic level definitions (`.CANONICAL_AGE_LEVELS`, etc.)
- `data/cleaned_survey_data/country_track.{csv,rds}` — cleaned Question 1 data
- `data/census_tables/synthetic_frames_combined.rds` — ACS poststratification frame
- Raw ANES 2024 source: `anes_timeseries_2024_csv_20250808.csv` (not in repo, on local disk)# align-marketing-mrp

R + Python project for MRP (multilevel regression and poststratification) modeling of three ANES survey questions selected for the MOVE marketing funnel. GPU-accelerated Bayesian inference via JAX/NumPyro on an RTX 4070 SUPER.

## What this does

Fits three hierarchical Bayesian models to ANES 2024 survey data, poststratifies predictions onto an ACS-derived population frame, and outputs congressional-district-level estimates of public opinion for marketing targeting.

## Tech stack

- **R:** Data processing, ACS frame construction, poststratification aggregation, output generation
- **Python (JAX/NumPyro):** GPU-accelerated MCMC inference (NUTS sampler)
- **Hardware:** Skidrow — Ryzen 9 7900, RTX 4070 SUPER (CUDA), Antigravity IDE

## Project structure

```
align-marketing-mrp/
├── CLAUDE.md
├── R/
│   ├── process_anes_2024.R       # ANES data cleaning and variable recoding
│   ├── build_poststrat_frame.R   # ACS poststratification frame construction
│   ├── poststratify.R            # aggregate posteriors onto frame, output estimates
│   └── utils.R                   # shared helpers (category definitions, CD formatting)
├── python/
│   ├── requirements.txt          # jax[cuda], numpyro, arviz
│   ├── models.py                 # NumPyro model definitions (MRP specification)
│   ├── fit.py                    # MCMC fitting script (GPU)
│   └── export_posteriors.py      # export posterior draws to CSV/RDS for R
├── data/
│   ├── raw/                      # ANES 2024 source data (gitignored)
│   ├── cleaned/                  # recoded survey data
│   ├── frames/                   # ACS poststratification frames
│   └── estimates/                # final CD-level poststratified estimates (output)
├── models/                       # fitted model artifacts (gitignored)
├── docs/
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

```python
def mrp_model(age, sex, race, edu, state, cd, y=None):
    # Priors on group-level effects (varying intercepts)
    sigma_age = numpyro.sample("sigma_age", dist.HalfNormal(1.0))
    alpha_age = numpyro.sample("alpha_age", dist.Normal(0, sigma_age).expand([n_age]))
    # ... similarly for sex, race, edu, state, cd

    # Linear predictor
    logit_p = alpha_age[age] + alpha_sex[sex] + alpha_race[race] + \
              alpha_edu[edu] + alpha_state[state] + alpha_cd[cd]

    # Likelihood
    numpyro.sample("y", dist.Bernoulli(logits=logit_p), obs=y)
```

Prior choices should follow Gelman et al. conventions for MRP. Half-Normal(1) on group-level standard deviations. Weakly informative Normal(0, 2) on fixed intercept if included.

## Convergence criteria

- R-hat < 1.05 for all parameters
- ESS (bulk and tail) > 400
- Divergences < 1% of post-warmup draws
- Visual posterior predictive checks for at least one question

Use `arviz` for diagnostics in Python, or export draws to R and use `posterior` package.

## Commands

```bash
# R pipeline
Rscript R/process_anes_2024.R          # clean and recode ANES data
Rscript R/build_poststrat_frame.R      # build ACS frame
Rscript R/poststratify.R               # aggregate posteriors, output estimates

# Python/JAX pipeline
pip install -r python/requirements.txt  # install JAX with CUDA + NumPyro
python python/fit.py --question 1       # fit model for question 1 on GPU
python python/export_posteriors.py      # export draws for R poststratification

# Full pipeline
bash run_all.sh                         # end-to-end: clean → fit → poststratify → output
```

## Critical rules

- **Never generate simulated survey data.** This project uses real ANES 2024 responses.
- **Raw ANES data stays in `data/raw/` and is gitignored.** Only cleaned/recoded data may be committed.
- **The demographic categories above are invariant.** Do not invent new bins or merge categories. The poststratification frame depends on exact alignment between survey recode and ACS frame.
- **JAX GPU setup:** Verify CUDA is available before fitting. `python -c "import jax; print(jax.devices())"` should show a GPU device.
- **If brms/Stan fits exist from prior work,** compare NumPyro posteriors against them as validation. Point estimates should agree within posterior uncertainty.
- **Model objects in `models/` are gitignored** — they're large binary artifacts. Commit convergence diagnostics and summary statistics in `docs/` instead.

## Origin

Ported from `r-scoring/run_marketing_mrp.R` and `r-scoring/process_anes_2024.R` in the demographai-platform repo. The brms/Stan inference backend is being replaced with JAX/NumPyro for GPU acceleration. The statistical model specification (varying intercepts by demographic and geographic groups, binary outcome, logit link) is identical.
