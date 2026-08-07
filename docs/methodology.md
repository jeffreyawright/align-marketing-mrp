# Methodology

District-level opinion estimates for three ANES 2024 items, produced by
multilevel regression and poststratification.

---

## 1. Data

**Survey.** ANES 2024 Time Series Study, full release (`anes_timeseries_2024_csv_20250808.csv`),
5,521 respondents.

**Population frame.** An ACS-derived synthetic poststratification frame,
187,193 cells for the 2024 vintage, covering 436 congressional districts and
a total population of 340,821,325.

Each frame cell is one combination of congressional district × age group × sex ×
race × education, with a population count. Survey recode and frame must use
identical category definitions, or the poststratification join misaligns
silently — so the definitions below are treated as invariant.

### Demographic categories

| Variable | Levels |
|---|---|
| Age group | 18-24, 25-29, 30-34, 35-39, 40-44, 45-49, 50-54, 55-59, 60-64, 65-69, 70-74, 75-79, 80 plus |
| Sex | Male, Female |
| Race/ethnicity | White, Black, Hispanic, Asian, Other (Hispanic-dominant coding) |
| Education | HS or less, Some College, BA/BS, Postgrad |
| Region | Northeast, Midwest, South, West, DC |
| District | `ST-XX`, at-large as `ST-00` |

Respondents missing any demographic or geographic value are excluded: 4,883 of
5,521 retain complete demographics. Per-question sample sizes are lower still,
depending on item non-response.

---

## 2. Question selection

The funnel requires items that appeal across the political spectrum, so partisan
gap was treated as a selection criterion rather than a diagnostic. All figures
below are unweighted (ANES design weights are not applied — see §6), computed on
the cleaned files.

| Question | ANES | n | % positive | Dem | Ind | Rep | **D–R gap** | demographic range |
|---|---|---|---|---|---|---|---|---|
| `basic_facts` | V241327 | 4,857 | 74.7 | 80.5 | 55.4 | 71.4 | 9.2 | 22.5 |
| `election_efficacy` | V241235 | 4,871 | 29.5 | 36.4 | 15.6 | 23.9 | 12.4 | 24.4 |
| `congress_approval` | V241127 | 4,787 | 17.6 | 19.8 | 17.6 | 15.2 | **4.6** | 22.1 |
| *considered, not used:* `country_track` | V241117 | 4,841 | 24.8 | 44.2 | 12.7 | 5.2 | **38.9** | 22.0 |
| *considered, not used:* `democracy_importance` | V242180 | 4,038 | 93.0 | 97.3 | 79.0 | 89.9 | 7.4 | 8.8 |

"Demographic range" is the spread in percent positive across age, race, and
education groups — the variation that actually differentiates districts after
poststratification.

**Excluded items.** `country_track` was set aside because a 38.9-point partisan
gap makes it close to a proxy for party identification in 2024, the opposite of
cross-spectrum appeal. `democracy_importance` was set aside because it is a
post-election item (losing ~500 respondents to non-completion), sits at a 93%
ceiling, and shows only an 8.8-point demographic range — too little variation to
support district-level discrimination.

`country_track` is still processed to `data/cleaned/` and remains available; it
is simply not part of the modeled set.

### Two findings that shape interpretation

**Cross-partisan appeal and targeting value trade off directly.** The property
that makes an item bipartisan — near-universal agreement — is the property that
destroys its variance. `basic_facts` cut at the top two boxes is 93.1% positive
with a 3.2-point partisan gap: maximally neutral, useless for discriminating
districts. The cut adopted here scores "Moderately important" as
non-endorsement, trading some neutrality for usable variance (74.7% positive,
9.2-point gap). Every response label is retained in `data/cleaned/`, so an
alternative cut requires no reprocessing.

**Independents are the outlier, not the middle.** On every item, pure
Independents score *below both* partisan groups — `basic_facts` 55.4 against
80.5 and 71.4. "Cross-partisan" here means these items appeal to committed
partisans of both parties; the disengaged middle is where they land worst. A
funnel aimed at persuadable independents should treat that as a caution.

### What `election_efficacy` measures

V241235 (`RESPONS_ELECTCARE`) measures **external political efficacy** — whether
the system is perceived as responsive to people like the respondent — not
diffuse support for democracy as a system. It is best read as a mobilization
variable, mapping where disengaged-but-reachable populations are concentrated.

It is a pre-election item, so estimates are anchored to the pre-November-2024
context. External efficacy carries a well-documented winner–loser gap and will
shift after a change in governing party.

---

## 3. Response coding

| Question | Scale | Coded 1 | Coded 0 |
|---|---|---|---|
| `basic_facts` | 1 = Not important at all … 5 = Extremely important | 4, 5 | 1, 2, 3 |
| `election_efficacy` | 1 = A good deal, 2 = Some, 3 = Not much | 1 | 2, 3 |
| `congress_approval` | 1 = Approve, 2 = Disapprove | 1 | 2 |

> **ANES importance scales are not consistently oriented.** V241327 ascends
> (1 = Not important at all → 5 = Extremely important) while V242180 descends
> (1 = Extremely important → 5 = Not at all important). Any recode that reuses a
> single Likert rule across importance items will invert one of them. An
> inverted binary outcome fits cleanly and means the opposite of what was
> intended, so it will not be caught by convergence diagnostics. Check the
> codebook per item.

Negative ANES codes (refusal, don't know, inapplicable, no post-interview) are
treated as missing throughout. The `hispanic` origin item is informative only for
codes 1–6; negative codes must not be read as Hispanic.

---

## 4. Model

Binary outcome, logit link, varying intercepts by demographic and geographic
group:

```
target_binary ~ 1 + (1|age_group) + (1|sex) + (1|race) + (1|educ)
                  + (1|region) + (1|state)
```

**Priors.** `exponential(1)` on group-level standard deviations, `normal(0, 1.5)`
on the intercept. These are used identically across every implementation; the
generated Stan program in `docs/stan/` is the authoritative written form.

**Sampling.** NUTS, 4 chains, 1,500 warmup + 1,500 draws each (6,000 posterior
draws), `target_accept = 0.99`.

**Convergence criteria.** R̂ < 1.05, bulk and tail ESS > 400, divergences < 1% of
post-warmup draws, and a visual posterior predictive check. Achieved for
`basic_facts`: R̂ 1.0000, minimum bulk ESS 1,911, 0 of 6,000 divergences.
Posterior predictive check in `docs/validation/`.

### Why `target_accept` is set so high

The geographic variance components are near zero (σ_state ≈ 0.05 on the logit
scale). A centered parameterization of a group effect whose scale approaches zero
produces Neal's funnel, and the sampler degrades sharply: at
`target_accept = 0.9` the same model yields 50% divergences, R̂ 2.08, and bulk ESS
of 3. The high acceptance target suppresses this at considerable cost in speed.

A non-centered parameterization is the actual fix and is the recommended path for
any future reimplementation. `docs/stan/*.stan` shows the form — standardized
offsets sampled from `std_normal`, then scaled.

---

## 5. Poststratification

Cell-level probabilities are computed for every frame cell and aggregated to
district and state as a population-weighted mean, **per posterior draw**, then
summarized. Aggregating per draw rather than from posterior means is what makes
district-level credible intervals recoverable.

Districts present in the frame but absent from the survey — `WA-09` — receive a
draw from the relevant group's own prior predictive, `Normal(0, σ)`, the correct
treatment for an unobserved group.

> **The frame stacks multiple ACS vintages.** It contains both 2022 (222,560
> cells, 256.5M people) and 2024 (187,193 cells, 340.8M). Aggregating over both
> weights by roughly twice the adult population and blends the vintages.
> `python/fit.py` selects a single vintage via `--frame-year`, defaulting to
> 2024. Anything else that consumes this frame needs the same guard.

---

## 6. Decisions and their rationale

**Survey weights are not applied.** ANES provides design weights (`V240107a`),
stratum, and PSU. These are not used. Poststratification onto a population frame
substitutes for weighting in the MRP framework, which is standard practice. The
consequence is that raw descriptive percentages in this document are unweighted
and should not be quoted as national population estimates; the poststratified
output in `data/estimates/` is the population-representative quantity.

> The two figures differ visibly and both appear in this repository. On
> `basic_facts` the §2 table reports **74.7%** (unweighted count of respondents)
> while the national row of `data/estimates/lookup_basic_facts.csv` reports
> **71.3%** (poststratified onto the 2024 ACS frame). The equivalents are 29.5 →
> 28.0 for `election_efficacy` and 17.6 → 19.6 for `congress_approval`. The
> poststratified figure is the one to quote externally. §2 percentages exist to
> justify question selection, not to describe the country.

**No district-level varying intercept.** The model stops at state. Fitted
σ_state is 0.05–0.17 across items, and district-level clustering is
indistinguishable from sampling noise, so a `(1|cd)` term would add 435
weakly-identified parameters — roughly 11 respondents each — for negligible gain,
while making the posterior substantially harder to sample. Because the frame is
district-level, district estimates are still produced: they emerge from
demographic composition within state. `python/fit.py --include-cd` enables the
term for anyone who wants to test the decision; `loo_compare` on the brms fit
would settle it formally.

**Sex is modeled as a varying intercept, though it should not be.** A variance
component cannot be identified from two groups: σ_sex has a posterior standard
deviation at or above its mean, meaning it is prior-dominated. Modeling sex as a
fixed effect is the correct treatment and is recommended for the next revision.
The current specification is retained for comparability with prior fits.

**Missing districts are dropped, not imputed.** Respondents with no
congressional district are excluded rather than assigned. String concatenation of
a missing district silently produces a literal `"ST-NA"` that survives a
null check and enters the model as a spurious district; `format_cd()` in
`R/utils.R` prevents this.

---

## 7. Limitations

**Geographic signal is weak.** State-level intraclass correlation is
indistinguishable from zero for every item tested. District estimates are
demographic-composition maps. Two districts with similar profiles receive similar
estimates regardless of geography, and the method should not be expected to
surface regional pockets.

**And the map is largely an education map.** Refitting `basic_facts` without the
education term (`python/fit.py basic_facts --exclude educ`) compresses the
district spread from 11.2 points to 7.4 (SD across districts 1.91 → 1.56 points)
and correlates with the production estimates at only r = 0.70. Education is
therefore the single largest source of district-to-district differentiation in
the output, not a marginal covariate. Two consequences: the estimates inherit
whatever error the ACS frame carries in district-level educational composition,
and any future change to the four education categories will move district
rankings more than a change to any other dimension.

**Estimates are time-anchored.** All three items are pre-election measures from
2024. `election_efficacy` in particular is sensitive to which party holds power.

**Unweighted descriptive statistics.** See §6.

**Synthetic frame.** The poststratification frame is ACS-derived and synthetic.
Estimate quality is bounded by how well it represents true district composition.

**Single survey source.** No external validation against independent polling or
election returns has been performed.

---

## 8. Reproducing

```bash
Rscript R/process_anes_2024.R          # survey -> data/cleaned/
tests/verify_cleaned.sh                # confirm the recode is unchanged
python python/fit.py <question>        # fit + poststratify + lookup -> data/estimates/
```

Two flags alter the last step. `--no-lookup` stops after the district and state
estimates, skipping §9. `--exclude <factor> ...` drops grouping factors from both
the model and the poststratification for sensitivity testing; it suffixes every
output with `_no_<factor>` so a sensitivity run cannot overwrite production, and
it implies `--no-lookup`.

The survey recode is deterministic; `tests/verify_cleaned.sh` checks the cleaned
files against a recorded manifest, so any unintended change to the processing is
caught before it propagates into estimates.

The model specification can be regenerated as a Stan program without fitting:

```bash
Rscript R/run_marketing_mrp.R <question>          # -> docs/stan/
Rscript R/run_marketing_mrp.R <question> --fit    # + independent brms fit
```

The `--fit` path fits the same specification through brms/Stan — a different
probabilistic programming language, sampler implementation, and parameterization
— and compares posteriors parameter by parameter. For `basic_facts`, 84
parameters agree to a median of 0.015 posterior standard deviations, maximum
0.447. The single parameter above 0.3 is σ_sex, the unidentifiable one discussed
in §6.

---

## 9. The progressive-disclosure lookup table

The consuming application is a poll funnel: a respondent answers the question,
sees the national figure, then discloses attributes one at a time and sees the
comparison narrow. Every step must return an answer immediately, and the
attributes arrive in no fixed order.

So `python/fit.py` precomputes all of them. `build_lookup()` enumerates every
*subset* of five disclosure dimensions — state, age group, sex, race, education —
and poststratifies once per subset, with `ALL` denoting a dimension the user has
not supplied. Output is `data/estimates/lookup_<question>.csv`, one row per
answerable slice.

**This is the same computation as §5, not a second model.** Each subset is a
different grouping key over the same frame and the same 6,000 posterior draws,
aggregated per draw exactly as district and state estimates are. The only reason
it is a separate step is the number of groupings. Nothing is refit.

### Size and coverage

Five dimensions with 51, 13, 2, 5 and 4 levels give 52 × 14 × 3 × 6 × 5 = 65,520
possible slices. **58,701 are populated**; the remaining 6,819 are combinations
with no population in the frame.

| Details supplied | Possible | Populated | Missing |
|---|---|---|---|
| 0 | 1 | 1 | 0 |
| 1 | 75 | 75 | 0 |
| 2 | 1,405 | 1,405 | 0 |
| 3 | 9,765 | 9,549 | 216 |
| 4 | 27,754 | 25,267 | 2,487 |
| 5 | 26,520 | 22,404 | 4,116 |

Every slice of two or fewer attributes exists, which is the region a real funnel
occupies. Gaps begin at three and are concentrated at four and five. Consumers
still need a fallback path — drop the last attribute and retry — but it will
rarely fire.

### `n_survey` is reported, and is not the estimate

Each row carries `n_survey`, the count of ANES respondents falling in that slice.
It is not an input to the estimate; the estimate comes from the model applied to
the frame. It is included because it is the honest measure of how thin the direct
evidence is, and because a slice with 7 respondents and a stable estimate is the
clearest available demonstration of what poststratification buys. Any interface
built on this file should display it.

### The reliability flag and its limits

`reliability` is a plain-language recode of `ci_width` = `q975 − q025`: `high`
below 0.10, `medium` below 0.20, `low` above. Two properties matter to anyone
building against it.

**The thresholds are absolute, so the flag means different things per question.**
A 10-point interval around `basic_facts`' 71% is a modest band; the same interval
around `congress_approval`'s 20% is half the estimate. A relative-width rule would
be more defensible and is the recommended revision.

**`medium` dominates in practice.** Share of populated rows flagged `high`:

| Details supplied | `basic_facts` | `election_efficacy` | `congress_approval` |
|---|---|---|---|
| 0 | 100% | 100% | 100% |
| 1 | 97% | 91% | 96% |
| 2 | 63% | 35% | 77% |
| 3 | 41% | 12% | 52% |
| 4 | 31% | 5% | 34% |
| 5 | 26% | 2% | 22% |

`election_efficacy` is the constraining case: past one attribute most of its rows
are `medium`, and 8.4% of the file is `low`. This is not a defect in the lookup —
it is the near-zero geographic variance of §7 showing up as interval width once
slices get thin. An interface that suppresses everything below `high` will go
silent on that question almost immediately; the intended handling is to present
`medium` in approximate language.

`docs/for-david.md` is the consumer-facing version of this section.
