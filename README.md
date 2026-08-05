# align-marketing-mrp

District-level estimates of American public opinion on three questions chosen for
cross-partisan appeal, for use in marketing funnel targeting.

Multilevel regression and poststratification (MRP) on ANES 2024 survey data,
projected onto an ACS-derived population frame. GPU-accelerated Bayesian
inference via JAX/NumPyro.

## The three questions

| Short name | Question | Coded 1 when |
|---|---|---|
| `basic_facts` | "How important is it that people agree on basic facts even if they disagree politically?" | Very / Extremely important |
| `election_efficacy` | "How much do you feel that having elections makes the government pay attention to what the people think?" | A good deal |
| `congress_approval` | "Do you approve or disapprove of the way the U.S. Congress has been handling its job?" | Approve |

All three were selected because they divide the public along lines other than
party. The Democrat–Republican gap is 9.2, 12.4, and 4.6 points respectively —
compared with 38.9 points for a "right direction / wrong track" item, which in
2024 is close to a proxy for partisanship. See
[`docs/methodology.md`](docs/methodology.md) for the selection evidence.

## Output

For each question, a population-weighted estimate per congressional district and
per state, with credible intervals:

```
data/estimates/<question>_estimates_cd.csv       # 436 districts
data/estimates/<question>_estimates_state.csv    # 51 states
```

Columns: `estimate`, `sd`, `q025`, `q975`, `pop`.

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

# 2. Fit and poststratify -> data/estimates/
python python/fit.py basic_facts
python python/fit.py election_efficacy
python python/fit.py congress_approval
```

Fitting takes roughly five minutes per question on an RTX 4070 SUPER.
Poststratification — 187,193 frame cells by 6,000 posterior draws — takes about
a second.

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
  fit.py                 GPU fitting and poststratification
data/
  raw/                   ANES source data (not committed)
  cleaned/               recoded survey data, one file per question
  frames/                ACS poststratification frame (not committed)
  estimates/             final district and state estimates
docs/
  methodology.md         model specification, decisions, limitations
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
