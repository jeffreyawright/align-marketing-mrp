# Methodology

District-level opinion estimates for four ANES 2024 items, produced by
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
| `social_trust` | V241234 | 4,875 | 45.1 | 50.3 | 23.7 | 42.7 | 7.6 | **34.1** |
| *considered, not used:* `country_track` | V241117 | 4,841 | 24.8 | 44.2 | 12.7 | 5.2 | **38.9** | 22.0 |
| *considered, not used:* `democracy_importance` | V242180 | 4,038 | 93.0 | 97.3 | 79.0 | 89.9 | 7.4 | 8.8 |

Party identification is `V241227x` collapsed with leaners folded into their party
(codes 1–3 Democrat, 4 pure Independent, 5–7 Republican). Pure Independents are
kept separate because they are not the midpoint — see below.

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

### `social_trust`, added after the original three

V241234 (`TRUST_SOCTRUST`) — "Generally speaking, how often can you trust other
people?", cut at *Always* / *Most of the time*. **The scale descends** (1 =
Always → 5 = Never), the opposite of V241327; see §3.

It was selected from a screen of the 2024 study's enduring-values items against
three criteria the original three did not fully satisfy: a partisan gap below
`basic_facts`, no dependence on a current issue or officeholder, and a construct
outside the existing set. It is the only modeled item that is not about
government — generalized social trust is the GSS construct asked since 1972 — and
so the only one not anchored to the 2024 political context. At 45.1% raw it also
sits closest to maximum binomial variance of any item tested, and its 34.1-point
demographic range is the largest in the table.

The 1–3 cut (adding *About half the time*) drops the partisan gap to 3.6 but
raises the marginal to 73.7%, nearly duplicating `basic_facts` at 74.7% — the
same neutrality-versus-variance trade reasoned through above, resolved the same
way.

**Screened and rejected: `V241579` (POLVIOL_JUSTIFIED, "political violence is
never justified").** On survey statistics it was the strongest candidate found:
a D–R gap of −1.2, the smallest Dem/Ind/Rep spread of any item tested, and a
28.3-point demographic range. Fitted, its district estimates correlate **−0.86**
with `congress_approval`. Race dominates both models (σ_race 0.63 and 0.74) with
near-mirrored effects — White −0.49 against +0.74, Asian +0.52 against −0.55 — so
the two district maps are inverted copies. As a targeting surface it added
nothing to the set.

That result is a methodological caution worth recording: **demographic-cell
profile correlation did not predict district-level redundancy.** At cell level
V241579 looked like the most distinct item screened (−0.25 against
`congress_approval`); at district level it was the most redundant. Because
district estimates are demographic-composition maps (§7), redundancy has to be
judged on fitted district estimates, not on the survey cross-tabs.

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
| `social_trust` | **1 = Always … 5 = Never** (descending) | 1, 2 | 3, 4, 5 |

> **ANES scales are not consistently oriented, including within the modeled
> set.** V241327 ascends (1 = Not important at all → 5 = Extremely important);
> V241234 descends (1 = Always → 5 = Never); V242180 descends. Any recode that
> reuses a single Likert rule across items will invert one of them. An inverted
> binary outcome fits cleanly and means the opposite of what was intended, so it
> will not be caught by convergence diagnostics. Check the codebook per item.
>
> The same hazard applies to *naming*. V241579 was screened under the name
> `violence_never_justified` rather than `political_violence` precisely because
> the latter would assert the opposite of what `target_binary = 1` stores. The
> platform's old `gov_cares` recode made exactly that mistake.

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
post-warmup draws, and a visual posterior predictive check. Met by all four
modeled questions:

| Question | max R̂ | min bulk ESS | divergences |
|---|---|---|---|
| `basic_facts` | 1.0000 | 1,727 | 0 / 6,000 |
| `election_efficacy` | 1.0000 | 1,185 | 0 / 6,000 |
| `congress_approval` | 1.0000 | 1,318 | 0 / 6,000 |
| `social_trust` | 1.0000 | 1,529 | 0 / 6,000 |

Posterior predictive checks and the brms cross-comparison for each are in
`docs/validation/`.

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

> The two figures differ visibly and both appear in this repository. The §2 table
> reports unweighted counts of respondents; the national row of
> `data/estimates/lookup_<question>.csv` reports the poststratified estimate.
>
> | Question | §2 raw | poststratified | shift |
> |---|---|---|---|
> | `basic_facts` | 74.7 | 71.3 | −3.4 |
> | `election_efficacy` | 29.5 | 28.0 | −1.5 |
> | `congress_approval` | 17.6 | 19.6 | +2.0 |
> | `social_trust` | 45.1 | **37.8** | **−7.3** |
>
> The poststratified figure is the one to quote externally. §2 percentages exist
> to justify question selection, not to describe the country.
>
> `social_trust` shifts more than twice as far as any other item, and the
> direction is the expected one: its education gradient is the steepest in the
> set (HS or less 28%, Postgrad 60% raw) and ANES over-represents the educated
> relative to the ACS frame, so reweighting pulls the estimate down. A large
> shift is evidence poststratification is doing work, not evidence of a fault —
> but it does mean the raw survey figure is a poor preview of the output for
> steeply-graded items.

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

**How much the four questions overlap as targeting maps.** District estimates
correlate as follows (436 CDs):

| | `basic_facts` | `election_efficacy` | `congress_approval` | `social_trust` |
|---|---|---|---|---|
| `basic_facts` | 1.00 | 0.11 | −0.26 | 0.72 |
| `election_efficacy` | 0.11 | 1.00 | 0.43 | 0.01 |
| `congress_approval` | −0.26 | 0.43 | 1.00 | −0.48 |
| `social_trust` | 0.72 | 0.01 | −0.48 | 1.00 |

District spread: `basic_facts` 11.2 points, `election_efficacy` 11.8,
`congress_approval` 12.5, **`social_trust` 27.7**. `social_trust` discriminates
between districts more than twice as strongly as any other item, which is what
makes it useful for targeting despite its interval-width problem (§9). Its 0.72
correlation with `basic_facts` is the largest overlap in the set — both are
steeply education-graded in the same direction — so the two should be treated as
partially redundant surfaces rather than independent signals.

**Estimates are time-anchored — except one.** `basic_facts`,
`election_efficacy`, and `congress_approval` are all pre-election 2024 measures
tied to the political context of that moment; `election_efficacy` in particular
is sensitive to which party holds power, and `congress_approval` names a specific
sitting Congress. `social_trust` is the exception: it asks nothing about
government and has been asked in essentially this form since 1972, so it is the
only item in the set that should be expected to survive a change of
administration without reinterpretation.

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

**The four generated Stan programs are byte-identical** (SHA-256
`cffcebf9…`). That is structural rather than coincidental: formula, priors, and
family are fixed, and the only per-question quantities — `N` and the level counts
— live in `standata()`, not `stancode()`. One file would have sufficed; all four
are kept so that a reader looking for a specific question finds it rather than
inferring the equivalence. It also means the specification demonstrably does not
vary by outcome, which is otherwise a claim a reviewer would have to take on
faith.

The `--fit` path fits the same specification through brms/Stan — a different
probabilistic programming language, sampler implementation, and parameterization
— and compares posteriors parameter by parameter. It has now been run for all
four modeled questions:

| Question | params | median \|Δ\| | max \|Δ\| | max-Δ parameter |
|---|---|---|---|---|
| `basic_facts` | 84 | 0.015 | 0.447 | σ_sex |
| `election_efficacy` | 84 | 0.014 | 0.373 | σ_sex |
| `congress_approval` | 84 | 0.016 | 0.399 | σ_sex |
| `social_trust` | 84 | 0.021 | 0.395 | σ_sex |

Differences are in units of posterior standard deviation. No question exceeds the
0.5 threshold at which the script warns.

**In all four, the single largest disagreement is σ_sex** — the variance
component that cannot be identified from two groups (§6). That the two
independent implementations agree to a median of ~0.02 posterior SD everywhere
else, and diverge only on the one parameter known to be prior-dominated, is
about as clean a cross-implementation result as this design admits. It also means
the σ_sex problem is a property of the specification, not of either
implementation.

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

**`medium` dominates in practice, and how fast varies enormously by question.**
Share of populated rows flagged `high`:

| Details supplied | `basic_facts` | `election_efficacy` | `congress_approval` | `social_trust` |
|---|---|---|---|---|
| 0 | 100% | 100% | 100% | 100% |
| 1 | 97% | 91% | 96% | **37%** |
| 2 | 63% | 35% | 77% | **8%** |
| 3 | 41% | 12% | 52% | **2%** |
| 4 | 31% | 5% | 34% | **2%** |
| 5 | 26% | 2% | 22% | **2%** |

Share flagged `low` (whole file): `basic_facts` 0.0%, `congress_approval` 3.8%,
`election_efficacy` 8.4%, **`social_trust` 23.7%** — rising to 33% at five
attributes.

**`social_trust` breaks the flag as currently defined, and this is a known open
problem.** Its `high` tier is effectively empty past the national row, and nearly
a quarter of the file trips the `low` fallback that `docs/for-david.md` presents
as the safety rule. The cause is not a defect in the fit — diagnostics are clean
(R̂ 1.0000, minimum bulk ESS 1,529, 0 divergences) — but a combination of a 45%
marginal, which is maximum binomial variance, with the largest group-level scales
in the set (σ_educ 0.92, σ_race 0.51). Wide intervals are the honest output.

What is wrong is the *rule*, not the intervals. A fixed 0.10 / 0.20 cut on
absolute interval width cannot serve four questions whose base rates run from 20%
to 71%, and `social_trust` is the case that forces the revision flagged above.
Changing it requires no refit — `ci_width` is already a column — but it is a
threshold decision, not a computation, and it is deliberately left open here
rather than tuned to make one question look better.

Until it is resolved, `election_efficacy` and `social_trust` should be presented
in approximate language (§ `docs/for-david.md`), and an interface that suppresses
everything below `high` will go silent on both almost immediately.

`docs/for-david.md` is the consumer-facing version of this section.
