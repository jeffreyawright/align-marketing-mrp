# docs/

Two kinds of thing live here:

1. **Committed:** project documentation — `methodology.md`, convergence diagnostics, posterior summaries. Model objects themselves are gitignored (`models/`); their diagnostics belong here.
2. **Not committed:** ANES reference material. These are large public binaries, so `.gitignore` excludes `docs/*.pdf`, `docs/*.html`, and `docs/*_files/`. **Import them as an installation step.**

## Reference material to import

Fetch these into `docs/` after cloning. Nothing in the pipeline reads them at runtime — they are for humans verifying recodes.

| File | Why you need it |
|---|---|
| `anes_timeseries_2024_questionnaire_20240808.pdf` | Question wording and response-order randomization |
| `ANES 2024 Time Series Study Full Release User Guide and Codebook.html` | **Value labels.** The authoritative source for every recode in `R/process_anes_2024.R` |
| `anes_timeseries_2024_varlist_20250808.pdf` | Variable index, for locating items by topic |

On Skidrow these already exist at:

```
/mnt/data/Surveys/anes/data/2024/
```

so the import is a copy:

```bash
mkdir -p docs
cp "/mnt/data/Surveys/anes/data/2024/anes_timeseries_2024_questionnaire_20240808.pdf" docs/
cp "/mnt/data/Surveys/anes/data/2024/ANES 2024 Time Series Study Full Release User Guide and Codebook.html" docs/
cp "/mnt/data/Surveys/anes/data/2024/anes_timeseries_2024_varlist_20250808.pdf" docs/
```

On a fresh machine, download them from the ANES 2024 Time Series Study data center:
<https://electionstudies.org/data-center/2024-time-series-study/>

A free ANES account is required — the files are public but sit behind registration. The raw survey CSV comes from the same page; it belongs in `data/raw/` (also gitignored), not here.

## Why the codebook matters more than it looks

Response scales are **not** consistently oriented across ANES items. Two items in this project's history run in opposite directions:

```
V241327 ASCENDS   1 = Not important at all  ... 5 = Extremely important
V242180 DESCENDS  1 = Extremely important   ... 5 = Not at all important
```

Any recode written from memory or copied between items has a good chance of being exactly inverted, and an inverted binary outcome produces a model that fits cleanly and means the opposite of what you think. Check the codebook for every new item. See "Two traps" in `CLAUDE.md`.
