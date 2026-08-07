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
any of them. **They do not behave identically** — `social_trust` in particular
needs different handling, covered under "Reliability" below. Read that section
before wiring it up.

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
| TX | 35-39 | Female | Hispanic | ALL | 0.627 | 0.565 | 0.687 | 7 | medium |

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

| Flag | Interval width | How to use it |
|---|---|---|
| `high` | under 10 points | Safe to show as a number. |
| `medium` | 10 to 20 points | Fine, but show it as approximate. "About 7 in 10." |
| `low` | over 20 points | Do not present as a fact about that person's group. |

**A simple rule that will not get you in trouble: if `reliability` is `low`, drop
the last detail the user gave and use that row instead.**

### Two things to know about the flag before you build against it

**It is an absolute rule, so it means different things per question.** A 10-point
interval on `basic_facts` (around 71%) is a modest band. The same 10 points on
`congress_approval` (around 20%) is half the estimate. Treat `high` on a
low-percentage question as less precise than the label suggests.

**`medium` is the normal case, not the exception.** Here is the share of rows
flagged `high` at each level of disclosure:

| Details supplied | Rows | `basic_facts` | `election_efficacy` | `congress_approval` | `social_trust` |
|---|---|---|---|---|---|
| 0 (national) | 1 | 100% | 100% | 100% | 100% |
| 1 | 75 | 97% | 91% | 96% | **37%** |
| 2 | 1,405 | 63% | 35% | 77% | **8%** |
| 3 | 9,549 | 41% | 12% | 52% | **2%** |
| 4 | 25,267 | 31% | 5% | 34% | **2%** |
| 5 | 22,404 | 26% | 2% | 22% | **2%** |

**`social_trust` needs different handling from the other three.** Outside the
national row its `high` tier is essentially empty, and 24% of the file is `low` —
so the "if `low`, drop the last detail" rule below will fire constantly, and a UI
that shows only `high` rows as numbers will show almost nothing for this
question.

That is not a bug and the estimates are sound; the question genuinely carries
more uncertainty than the others, and the `high`/`medium`/`low` cut-offs are
fixed percentage-point widths that suit a 71% question better than a 38% one.
**We know this rule needs revising and it is being looked at.** In the meantime,
for `social_trust`:

- Present it in approximate language by default — "roughly 4 in 10" — rather than
  gating on the flag.
- Trust the national and single-detail rows; treat three or more details as
  indicative only.
- Do not suppress `medium`. If you do, this question disappears.

`election_efficacy` has a milder version of the same pattern: past one detail
most of its rows are `medium` too. `basic_facts` and `congress_approval` behave
the way the flag suggests.

## How deep to go

**One detail is comfortably safe on three of the four** — state alone, or age
alone, is `high` for 91–97% of rows on `basic_facts`, `election_efficacy`, and
`congress_approval`. On `social_trust` it is 37%.

**Two details is where it starts to depend on the question.** State plus age is
`high` for 77% of rows on `congress_approval`, 63% on `basic_facts`, 35% on
`election_efficacy`, and 8% on `social_trust`. Check the flag rather than
assuming.

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
