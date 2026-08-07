# Using the estimates

Everything you need is in four CSV files:

```
data/estimates/lookup_basic_facts.csv
data/estimates/lookup_election_efficacy.csv
data/estimates/lookup_congress_approval.csv
data/estimates/lookup_social_trust.csv
```

One file per poll question. No database, no API, no code to run — load the CSV
and look up a row.

All four have identical columns and identical keys, so one piece of code reads
any of them. They do not all carry the same precision — `social_trust` has
visibly wider intervals than the rest — but the `reliability` column tells you
that per row, so you do not need per-question logic.

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
| ALL | ALL | ALL | ALL | ALL | 0.713 | 0.697 | 0.729 | 4857 | high |
| TX | ALL | ALL | ALL | ALL | 0.702 | 0.673 | 0.729 | 377 | high |
| TX | 35-39 | ALL | ALL | ALL | 0.691 | 0.642 | 0.736 | 34 | high |
| TX | 35-39 | Female | ALL | ALL | 0.666 | 0.614 | 0.714 | 16 | high |
| TX | 35-39 | Female | Hispanic | ALL | 0.627 | 0.565 | 0.687 | 7 | high |

*(Real rows from `lookup_basic_facts.csv`.)*

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
| `lookup_basic_facts` | 71.3% | 69.7 – 72.9 |
| `lookup_election_efficacy` | 28.0% | 26.3 – 29.7 |
| `lookup_congress_approval` | 19.6% | 18.2 – 21.1 |
| `lookup_social_trust` | 37.8% | 36.1 – 39.5 |

## Looking up a row

Set every column the user has told you, and `ALL` for everything else. In SQL:

```sql
SELECT estimate, q025, q975, n_survey, reliability
FROM lookup_basic_facts
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
the last detail the user gave and use that row instead.** This is rare — under 2%
of rows on every question — so it is a genuine exception, not a path you will be
on constantly.

**`high` means "±7.5 points", not "precise."** Share of rows flagged `high` at
each level of disclosure:

| Details supplied | Rows | `basic_facts` | `election_efficacy` | `congress_approval` | `social_trust` |
|---|---|---|---|---|---|
| 0 (national) | 1 | 100% | 100% | 100% | 100% |
| 1 | 75 | 100% | 99% | 100% | 91% |
| 2 | 1,405 | 99% | 92% | 95% | 62% |
| 3 | 9,549 | 97% | 71% | 88% | 39% |
| 4 | 25,267 | 88% | 52% | 80% | 27% |
| 5 | 22,404 | 80% | 38% | 72% | 21% |

**One and two details — the realistic funnel — are safe on all four questions.**
Past that the questions separate, and `social_trust` is consistently the least
certain of the four. That is real: it carries genuinely wider intervals than the
others, and the flag is telling you so rather than hiding it.

Practical guidance for `social_trust`: it is fine as a number through two
details, and past three prefer "roughly 4 in 10" over a specific figure. Do not
suppress `medium` on any question — that is the normal, usable tier.

## How deep to go

**One detail is comfortably safe on all four** — state alone, or age alone, is
`high` for 91–100% of rows on every question.

**Two details is still safe**, at 92–99% `high` on three of them and 62% on
`social_trust`.

**Three or more is where the questions separate.** `basic_facts` stays at 97%
`high`, `congress_approval` 88%, `election_efficacy` 71%, `social_trust` 39%.
Check the flag rather than assuming.

Realistically, a poll funnel gets one or two details before people lose patience,
and that is enough to make the comparison feel personal. The deeper combinations
exist in the file because they cost nothing to include, not because you should
ask five questions.

## Missing rows

The file has 58,701 rows out of a possible 65,520. The gaps are combinations that
essentially nobody in the country matches — a demographic profile with no
population in that state.

**Every combination of two or fewer details exists**, in all four files. So the
realistic funnel path — national, then state, then age — never misses. Gaps only
start at three details and are concentrated at four and five.

Still, code the fallback: if the lookup returns no row, drop the last detail and
retry. That is the same handling as a `low` reliability row.

## What these numbers are, and are not

**They are model estimates, not survey tallies.** The survey has roughly 4,800
respondents per question (4,857 for `basic_facts`, 4,871 for
`election_efficacy`, 4,787 for `congress_approval`, 4,875 for `social_trust`) —
the `n_survey` value in the
all-`ALL` row of each file. There is no state with enough respondents to just count them
directly — Wyoming has a handful. The model learns how age, sex, race,
education, and state relate to the answer, then applies that to the actual
population makeup of each group. This is standard practice for exactly this
problem; it is how election night projections and district-level opinion
estimates are made.

**These will not match a raw count of the survey.** 74.7% of ANES respondents
gave the "yes" answer on `basic_facts`, but the estimate here is 71.3%. That is
not an error — the raw figure counts the people who happened to be surveyed,
while the estimate reweights them to the actual makeup of the country. The
reweighted number is the one to quote. If you see 74.7% in `docs/methodology.md`,
that is the raw survey figure and it is labelled as such.

**Fair things to say:**
- "71% of Americans say it is important that we agree on basic facts."
- "In Texas, about 70% say the same."
- "Among people your age in your state, roughly 69%."

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
| `lookup_basic_facts` | "How important is it that people agree on basic facts even if they disagree politically?" | Very or Extremely important |
| `lookup_election_efficacy` | "How much do you feel that having elections makes the government pay attention to what the people think?" | A good deal |
| `lookup_congress_approval` | "Do you approve or disapprove of the way the U.S. Congress has been handling its job?" | Approve |
| `lookup_social_trust` | "Generally speaking, how often can you trust other people?" | Always, or Most of the time |

Use this wording in the poll. The estimates only mean what they mean because
these are the exact questions that were asked.

`social_trust` is the odd one out in a useful way: it is the only question that
isn't about government, and the only one that won't need revisiting after an
election — it has been asked in this form since 1972. It also separates districts
about twice as sharply as the other three, so if you are picking one question to
target on, it is the strongest signal. Its intervals are wider; see
"Reliability".

## Seeing it work

There is a small Shiny app in `app/` that walks the whole funnel — answer the
poll, add details one at a time, watch the estimate move and the respondent count
fall. It reads the same lookup CSVs and nothing else.

```bash
Rscript -e 'shiny::runApp("app")'
```
