# align-marketing-mrp

District-level estimates of American public opinion on four questions chosen for
cross-partisan appeal, for use in marketing funnel targeting.

Multilevel regression and poststratification (MRP) on ANES 2024 survey data,
projected onto an ACS-derived population frame. GPU-accelerated Bayesian
inference via JAX/NumPyro.

## The four questions

| Short name | Question | Coded 1 when | D–R gap |
|---|---|---|---|
| `basic_facts` | "How important is it that people agree on basic facts even if they disagree politically?" | Very / Extremely important | 9.2 |
| `election_efficacy` | "How much do you feel that having elections makes the government pay attention to what the people think?" | A good deal | 12.4 |
| `congress_approval` | "Do you approve or disapprove of the way the U.S. Congress has been handling its job?" | Approve | 4.6 |
| `social_trust` | "Generally speaking, how often can you trust other people?" | Always / Most of the time | 7.6 |

All four were selected because they divide the public along lines other than
party — compared with 38.9 points for a "right direction / wrong track" item,
which in 2024 is close to a proxy for partisanship. See
[`docs/methodology.md`](docs/methodology.md) for the selection evidence.

`social_trust` is the only item that is not about government, the only one not
anchored to the 2024 political moment, and the one that separates districts most
sharply (27.7 points of spread against 11–13 for the others). Its scale
**descends** in the ANES coding — 1 = Always, 5 = Never — the opposite of
`basic_facts`. It also carries visibly wider credible intervals; see
[`docs/methodology.md`](docs/methodology.md) §9.

## Output

For each question, a population-weighted estimate per congressional district and
per state, with credible intervals:

```
data/estimates/<question>_estimates_cd.csv       # 436 districts
data/estimates/<question>_estimates_state.csv    # 51 states
```

Columns: `estimate`, `sd`, `q025`, `q975`, `pop`.

Plus a lookup table covering every combination of demographics a poll respondent
might disclose — 58,701 slices of state × age × sex × race × education, with
`ALL` meaning "not supplied":

```
data/estimates/lookup_<question>.csv
```

Columns: the five demographic keys, then `estimate`, `sd`, `q025`, `q975`,
`ci_width`, `reliability`, `pop`, `n_survey`. This is the artifact the funnel
consumes; [`docs/for-david.md`](docs/for-david.md) is the guide for using it and
[`docs/methodology.md`](docs/methodology.md) §9 explains how it is built.

National estimates:

| Question | Estimate | 95% CI | Raw survey % |
|---|---|---|---|
| `basic_facts` | 71.3% | 69.7 – 72.9 | 74.7 |
| `election_efficacy` | 28.0% | 26.3 – 29.7 | 29.5 |
| `congress_approval` | 19.6% | 18.2 – 21.1 | 17.6 |
| `social_trust` | 37.8% | 36.1 – 39.5 | 45.1 |

These are poststratified onto the ACS frame and differ from the raw survey
percentages quoted in `docs/methodology.md` §2, which are unweighted by design.
`social_trust` shifts furthest because its education gradient is the steepest in
the set and ANES over-represents the educated — the reweighting is doing exactly
what it is there for.

## Setup

Requires R (≥ 4.4) and Python (≥ 3.11) with a CUDA-capable GPU.

```bash
pip install -r python/requirements.txt
python -c "import jax; print(jax.devices())"   # expect [CudaDevice(id=0)]
```

R packages: `tidyverse`, `data.table`, and — only for the validation path —
`brms`, `posterior`.

Two inputs are not in the repository and must be imported first: the raw ANES
2024 survey file and the ACS poststratification frame. See
[`docs/README.md`](docs/README.md).

## Running

```bash
# 1. Clean and recode the survey data -> data/cleaned/
Rscript R/process_anes_2024.R

# 2. Fit, poststratify, build the lookup -> data/estimates/
python python/fit.py basic_facts
python python/fit.py election_efficacy
python python/fit.py congress_approval
python python/fit.py social_trust

# 3. Optional: walk the funnel in a browser
Rscript -e 'shiny::runApp("app")'
```

Fitting takes roughly five minutes per question on an RTX 4070 SUPER.
Poststratification — 187,193 frame cells by 6,000 posterior draws — takes about
a second. The lookup table repeats that aggregation once per demographic subset
and is the longest step after the fit; `--no-lookup` skips it.

Verify the survey processing is unchanged at any time:

```bash
tests/verify_cleaned.sh
```

## Layout

```
R/
  process_anes_2024.R    survey cleaning and recoding
  utils.R                canonical demographic categories, CD formatting
  run_marketing_mrp.R    Stan specification artifact + brms cross-check
python/
  fit.py                 GPU fitting, poststratification, lookup table
app/
  app.R                  Shiny demo of the progressive-disclosure funnel
  manifest.json          R version and package pins for Posit Connect Cloud
data/
  raw/                   ANES source data (not committed)
  cleaned/               recoded survey data, one file per question
  frames/                ACS poststratification frame (not committed)
  estimates/             district, state, and lookup estimates
docs/
  methodology.md         model specification, decisions, limitations
  for-david.md           how to consume the lookup tables
  stan/                  generated Stan programs
  validation/            cross-implementation checks
tests/
  verify_cleaned.sh      drift check on the cleaned data
```

## Reading the estimates

District estimates are driven primarily by demographic composition. Opinion on
these questions shows almost no geographic clustering beyond sampling noise, so
two districts with similar age, race, and education profiles will receive similar
estimates regardless of where they are. This is a property of the data, not a
limitation of the method — but it means the output should be read as a
demographic map rather than as the discovery of regional pockets.
See [`docs/methodology.md`](docs/methodology.md).
