# align-marketing-mrp

MRP (multilevel regression and poststratification) estimates of four ANES 2024
questions at congressional-district level, for marketing funnel targeting.
GPU-accelerated Bayesian inference via JAX/NumPyro.

**Read [`docs/methodology.md`](docs/methodology.md) before changing the model, the
recode, or the question set.** It carries the decisions and their rationale.
[`README.md`](README.md) is the user-facing entry point.

## The four questions

| Short name | ANES | Scale | Coded 1 when | D–R gap |
|---|---|---|---|---|
| `basic_facts` | V241327 | ascends | Very / Extremely important | 9.2 |
| `election_efficacy` | V241235 | — | A good deal | 12.4 |
| `congress_approval` | V241127 | — | Approve | 4.6 |
| `social_trust` | V241234 | **descends** | Always / Most of the time | 7.6 |

Selected for cross-partisan appeal. `country_track` (V241117) is also processed
to `data/cleaned/` but is not modeled; at a 38.9-point gap it is close to a proxy
for party ID.

`social_trust` was added after the original three and differs from them in ways
that matter operationally: **its ANES scale descends** (1 = Always → 5 = Never),
it is the only item not about government and the only one not anchored to 2024,
it separates districts about twice as sharply as the others (27.7 points of CD
spread), and its credible intervals are wide enough to break the `reliability`
flag — see "The lookup table" below.

**Rejected after fitting: V241579** ("political violence never justified"). It
screened as the best candidate in the study on survey statistics, then came out
at **−0.86** district correlation with `congress_approval`. Do not re-propose it.
The general lesson is in `docs/methodology.md` §2: demographic-cell profiles do
not predict district-level redundancy — only fitted district estimates do.

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
│   ├── fit.py                    # GPU fit + poststrat + lookup -> data/estimates/
│   └── requirements.txt
├── app/
│   └── app.R                     # Shiny demo of the disclosure funnel
├── data/
│   ├── raw/                      # ANES source (gitignored, imported)
│   ├── cleaned/                  # recoded survey data, one file per question
│   ├── frames/                   # ACS frame (gitignored, imported)
│   └── estimates/                # district, state, lookup estimates (committed)
├── models/                       # fitted artifacts (gitignored)
├── docs/
│   ├── methodology.md            # specification, decisions, limitations
│   ├── for-david.md              # consumer guide to the lookup tables
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

**`(1|sex)` stays a varying intercept. Do not propose converting it to a fixed
effect.** σ_sex is weakly identified from two groups and is the one parameter
where brms and NumPyro disagree measurably — that is expected and settled, not a
bug to fix. Partial pooling shrinks the two sex effects toward the grand mean,
and that shrinkage is information a fixed effect discards; keeping the term
varying also keeps every grouping factor written identically across
implementations. Fitted sex effects are the smallest in the model (0.04–0.36
logits) so the choice barely moves estimates anyway. Rationale in
`docs/methodology.md` §6.

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

## The lookup table

`data/estimates/lookup_<question>.csv` is the artifact the marketing funnel
actually consumes — the district and state files are secondary. `build_lookup()`
poststratifies over every *subset* of state × age × sex × race × education, with
`ALL` meaning "not yet disclosed", so a respondent disclosing attributes in any
order always hits a precomputed row. 58,701 of a possible 65,520 slices are
populated; all slices of two or fewer attributes exist, gaps start at three.

**It is not a second model.** Same posterior, same frame, same per-draw
aggregation as §5 of the methodology — only the grouping key changes. Never refit
for it.

**`n_survey` is reported, not used.** It counts matching ANES respondents so a
consumer can see the direct evidence thin out while the estimate holds. It is not
an input to the estimate.

**`reliability` thresholds are absolute and deliberately so** (`ci_width` < 0.15
high, < 0.25 medium, else low). The deliverable is copy, not inference: 15 points
is ±7.5, where "about N in 10" stays true at any base rate; 25 points is where the
rounded fraction moves. Do not replace this with a relative-width rule without a
reason grounded in how the output is used.

They were originally 0.10 / 0.20, which sat below the median width of every
question and left `high` nearly empty (`social_trust` 2.1%). If you ever move them
again: recomputing needs **no refit** — `ci_width` is a stored column, so patch
the lookup CSVs in place and assert the other columns are byte-identical
afterwards. Update `docs/methodology.md` §9 and `docs/for-david.md` in the same
commit; the flag is a published contract.

`docs/for-david.md` is the consumer-facing contract for this file. **Changing the
lookup's columns, keys, or reliability rule breaks it — update it in the same
commit.**

## Commands

```bash
# Survey processing
Rscript R/process_anes_2024.R            # raw ANES -> data/cleaned/
tests/verify_cleaned.sh                  # confirm the recode has not drifted

# Fit + poststratify + lookup (production path)
pip install -r python/requirements.txt
python python/fit.py basic_facts        # or election_efficacy | congress_approval | social_trust
python python/fit.py congress_approval --draws 400 --tune 400 --chains 2  # smoke test
python python/fit.py basic_facts --no-lookup           # stop after cd/state
python python/fit.py basic_facts --exclude educ        # sensitivity; implies --no-lookup

# Demo the funnel against the lookup tables
Rscript -e 'shiny::runApp("app")'

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
- **`data/estimates/` is committed**, lookup tables included (~17 MB), because `docs/for-david.md` hands those exact paths to a consumer. Regenerating them changes tracked files — expect the diff.
- **Raw survey percentages are not the estimates.** `docs/methodology.md` §2 quotes unweighted respondent counts (`basic_facts` 74.7%); the poststratified national figure is 71.3%. Only the latter describes the country. Never quote a §2 percentage externally, and never "reconcile" the two by changing one.
- **Sensitivity runs must not overwrite production.** `--exclude` suffixes every output `_no_<factor>` and skips the lookup. Keep that if the flag changes.

## Where the GPU matters

The fit is small — ~4,900 rows, 87 parameters — and the GPU is underutilized
there; roughly 1.8× over 4-core CPU rstan. **Poststratification is the
GPU-shaped work:** 187,193 frame cells × 6,000 draws, about a second on device.
Benchmark that step, not the fit.
