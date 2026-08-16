# Using the estimates

**This document describes the five funnel questions wired into the demo app**
(`app/app.R`) — selected for cross-partisan resonance (shared grievance or a
unifying value), not district discrimination. The original four-question
research-grade targeting set (`basic_facts`, `election_efficacy`,
`congress_approval`, `social_trust`) is still fit and its lookup tables are
still committed, but it is no longer what the app walks; see
`docs/methodology.md` "Question selection" for that set.

Everything you need is in five CSV files:

```
data/estimates/lookup_country_offtrack.csv
data/estimates/lookup_democracy_importance.csv
data/estimates/lookup_gov_few_interests.csv
data/estimates/lookup_officials_dont_care.csv
data/estimates/lookup_no_say.csv
```

One file per poll question. No database, no API, no code to run — load the CSV
and look up a row.

All five have identical columns and identical keys, so one piece of code reads
any of them. They do not all carry the same precision — `country_offtrack` has
visibly wider intervals than the rest once state, age, sex, race, and
education are all supplied — but the `reliability` column tells you that per
row, so you do not need per-question logic.

---

## The idea in one paragraph

Someone answers your poll. You show them what the country thinks. Then, as they
tell you where they live and how old they are, you show them what *people like
them* think. Each detail they give you narrows the comparison, and each narrowing
is a reason for them to give you one more detail. The estimates are already
computed for every combination they might enter, so there is nothing to
calculate at runtime.

## How to read a row

Each row is one group of people. The five demographic columns say who that group
is. `ALL` means "not specified".

| state | age_group | sex | race | educ | estimate | q025 | q975 | n_survey | reliability |
|---|---|---|---|---|---|---|---|---|---|
| ALL | ALL | ALL | ALL | ALL | 0.781 | 0.766 | 0.795 | 4841 | high |
| TX | ALL | ALL | ALL | ALL | 0.815 | 0.783 | 0.847 | 375 | high |
| TX | 35-39 | ALL | ALL | ALL | 0.848 | 0.806 | 0.886 | 34 | high |
| TX | 35-39 | Female | ALL | ALL | 0.846 | 0.803 | 0.885 | 16 | high |
| TX | 35-39 | Female | Hispanic | ALL | 0.853 | 0.805 | 0.894 | 7 | high |

*(Real rows from `lookup_country_offtrack.csv`.)*

- **`estimate`** — the share of that group who answered the "yes" side. Multiply
  by 100 for a percentage. `0.713` → 71.3%.
- **`q025` / `q975`** — the range the true value is 95% likely to sit in. Row one
  says: nationally it is 71.3%, and almost certainly between 69.7% and 72.9%.
- **`n_survey`** — how many real survey respondents are in this group.
- **`ci_width`** — `q975 − q025`, the width of that range in the same units.
- **`reliability`** — `high`, `medium`, or `low`, derived from `ci_width`. See below.
- **`pop`** — how many American adults this group represents.

Note the last two rows: 16 respondents, then 7. The estimate keeps working
because it is a model estimate, not a tally of those 7 people.

## Start here

**The first row of every file — all five columns `ALL` — is the national
figure.** That is your opening screen, right after they answer the poll. It is
the most robust number in the file and the one you will show most often.

| File | National estimate | 95% range |
|---|---|---|
| `lookup_country_offtrack` | 78.1% | 76.6 – 79.5 |
| `lookup_democracy_importance` | 80.9% | 79.0 – 82.6 |
| `lookup_gov_few_interests` | 81.8% | 80.4 – 83.3 |
| `lookup_officials_dont_care` | 85.8% | 84.4 – 87.1 |
| `lookup_no_say` | 76.5% | 74.8 – 78.0 |

## Looking up a row

Set every column the user has told you, and `ALL` for everything else. In SQL:

```sql
SELECT estimate, q025, q975, n_survey, reliability
FROM lookup_country_offtrack
WHERE state = 'TX' AND age_group = '35-39'
  AND sex = 'ALL' AND race = 'ALL' AND educ = 'ALL';
```

Always constrain all five columns. If you leave one out you will get many rows
back instead of one.

Valid values are exactly the ones in the file. Age groups are five-year bands
(`18-24`, `25-29`, … `80 plus`), states are two-letter codes (51, including
`DC`), sex is `Male` / `Female`, race is `White` / `Black` / `Hispanic` /
`Asian` / `Other`, and education is one of `HS or less`, `Some College`,
`BA/BS`, `Postgrad`.

## The reliability flag

The more detail the user gives, the fewer real survey respondents resemble them,
and the wider the credible interval becomes. The flag is a plain-language read of
`ci_width`:

| Flag | Interval width | What it licenses |
|---|---|---|
| `high` | under 15 points | Show it as a number. "38% of people like you." |
| `medium` | 15 to 25 points | Show it as a rounded fraction. "About 4 in 10." |
| `low` | over 25 points | Do not present as a fact about that person's group. |

The thresholds are set by what the copy can safely claim, not by a statistical
convention. A 15-point interval is ±7.5 points, which leaves an "about N in 10"
statement true across the whole range whatever the base rate. At 25 points the
rounded fraction itself starts to move, so there is nothing safe left to say.

**A simple rule that will not get you in trouble: if `reliability` is `low`, drop
the last detail the user gave and use that row instead.** This is rare on most
questions — under 3% of rows — with one exception (`country_offtrack` at 6.0%),
so it is a genuine exception, not a path you will be on constantly.

**`high` means "±7.5 points", not "precise."** Share of rows flagged `high` at
each level of disclosure:

| Details supplied | Rows | `country_offtrack` | `democracy_importance` | `gov_few_interests` | `officials_dont_care` | `no_say` |
|---|---|---|---|---|---|---|
| 0 (national) | 1 | 100% | 100% | 100% | 100% | 100% |
| 1 | 75 | 99% | 100% | 99% | 99% | 99% |
| 2 | 1,405 | 76% | 94% | 92% | 98% | 98% |
| 3 | 9,549 | 48% | 84% | 70% | 94% | 88% |
| 4 | 25,267 | 33% | 78% | 51% | 89% | 74% |
| 5 | 22,404 | 25% | 74% | 35% | 83% | 60% |

**One detail — the realistic funnel opener — is safe on all five questions.**
Past that they separate quickly, and `country_offtrack` is consistently the
least certain of the five: only a quarter of fully-specified rows are `high`.
That is real — it carries genuinely wider intervals than the others — and the
flag is telling you so rather than hiding it.

Practical guidance for `country_offtrack` and `gov_few_interests`: fine as a
number through one detail, and past two prefer a rounded fraction ("about 8 in
10") over a specific figure. Do not suppress `medium` on any question — that is
the normal, usable tier.

## How deep to go

**One detail is comfortably safe on all five** — state alone, or age alone, is
`high` for 99–100% of rows on every question.

**Two details is still mostly safe**, at 92–98% `high` on four of them and 76%
on `country_offtrack`.

**Three or more is where the questions separate.** `officials_dont_care` stays
at 94% `high` at three details, `no_say` 88%, `democracy_importance` 84%,
`gov_few_interests` 70%, `country_offtrack` 48%. Check the flag rather than
assuming.

Realistically, a poll funnel gets one or two details before people lose patience,
and that is enough to make the comparison feel personal. The deeper combinations
exist in the file because they cost nothing to include, not because you should
ask five questions.

## Missing rows

The file has 58,701 rows out of a possible 65,520. The gaps are combinations that
essentially nobody in the country matches — a demographic profile with no
population in that state.

**Every combination of two or fewer details exists**, in all five files. So the
realistic funnel path — national, then state, then age — never misses. Gaps only
start at three details and are concentrated at four and five.

Still, code the fallback: if the lookup returns no row, drop the last detail and
retry. That is the same handling as a `low` reliability row.

## What these numbers are, and are not

**They are model estimates, not survey tallies.** The survey has roughly 3,700
to 4,800 respondents per question (4,841 for `country_offtrack`, 4,396 for
`democracy_importance`, 4,840 for `gov_few_interests`, 3,737 for
`officials_dont_care`, 3,806 for `no_say` — the two POST-election items lose
more respondents to non-completion) — the `n_survey` value in the all-`ALL` row
of each file. There is no state with enough respondents to just count them
directly — Wyoming has a handful. The model learns how age, sex, race,
education, and state relate to the answer, then applies that to the actual
population makeup of each group. This is standard practice for exactly this
problem; it is how election night projections and district-level opinion
estimates are made.

**These will not match a raw count of the survey.** 85.5% of ANES respondents
gave the "yes" answer on `democracy_importance`, but the estimate here is
80.9%. That is not an error — the raw figure counts the people who happened to
be surveyed, while the estimate reweights them to the actual makeup of the
country. The reweighted number is the one to quote. If you see a different
percentage for this question in `docs/methodology.md`, that is either the
raw survey figure or the marketing-set screening cut, and both are labelled as
such — see methodology.md §2 for why one ANES item has three different
reported numbers.

**Fair things to say:**
- "78% of Americans say the country has gotten off on the wrong track."
- "In Texas, about 82% say the same."
- "Among people your age in your state, roughly 85%."

**Things to avoid:**
- Quoting decimals. "71%", not "71.3%" — the extra digit is not real precision.
- "People exactly like you." The model does not capture every interaction between
  traits; it is a good estimate for a group, not a reading of an individual.
- Presenting a `low` reliability row as a firm number.
- Comparing two similar groups and calling the difference meaningful. If their
  `q025`–`q975` ranges overlap, the difference may be noise.

## Where the data comes from

American National Election Studies 2024 Time Series — a long-running,
academically maintained, nationally representative survey. These are the real
questions, asked with the real wording. The population figures come from the
American Community Survey.

If anyone asks how it works, `docs/methodology.md` has the full specification;
§9 covers this file specifically.

## The questions

| File | Question asked | `estimate` is the share who said |
|---|---|---|
| `lookup_country_offtrack` | "Do you feel things in this country are generally going in the right direction, or have they pretty seriously gotten off on the wrong track?" | Wrong track |
| `lookup_democracy_importance` | "How important is it that the U.S. remains a democracy?" | Extremely or Very important |
| `lookup_gov_few_interests` | "Is government run by a few big interests looking out for themselves, or for the benefit of all the people?" | Run by a few big interests |
| `lookup_officials_dont_care` | "Public officials don't care much what people like me think." | Agree strongly or somewhat |
| `lookup_no_say` | "People like me don't have any say about what the government does." | Agree strongly or somewhat |

Use this wording in the poll. The estimates only mean what they mean because
these are the exact questions that were asked.

These five were picked for cross-partisan resonance, not district
discrimination — the point is that they land as shared grievance or shared
value across the political spectrum, not that they discriminate between
congressional districts (that is what the marketing four are for). Two of
them stand out: on `officials_dont_care` and `no_say`, political Independents
agree *more* than either party does (90.7% and 84.5% vs. both Democrats and
Republicans below that) — the opposite of the marketing-set pattern, and the
reason `no_say` is the funnel's cross-partisan spine. See
`docs/methodology.md` "The funnel question set" for the full detail.

## Seeing it work

There is a small Shiny app in `app/` that walks the whole funnel — answer the
poll, add details one at a time, watch the estimate move and the respondent count
fall. It reads the same lookup CSVs and nothing else.

```bash
Rscript -e 'shiny::runApp("app")'
```
