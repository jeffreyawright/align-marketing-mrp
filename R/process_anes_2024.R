# ==============================================================================
# Script: process_anes_2024.R
# Purpose: ANES 2024 recode -> cleaned per-question datasets for the MOVE
#          marketing funnel MRP.
# Ported from: demographai-platform/r-scoring/process_anes_2024.R
#
# Emits one CSV per question to data/cleaned/:
#   basic_facts.csv               (V241327 DEMNORMS_DEMFACTS)   -- marketing
#   election_efficacy.csv         (V241235 RESPONS_ELECTCARE)   -- marketing
#   congress_approval.csv         (V241127 CONGAPP_CONGJOB)     -- marketing
#   social_trust.csv              (V241234 TRUST_SOCTRUST)      -- marketing
#   country_track.csv             (V241117 EMOTION_TRACK)       -- validation fixture
#   democracy_importance.csv      (V242180 IMP_DEMOC)           -- one-off demo bundle
#
# Each file carries the canonical demographics, the labeled response, and a
# target_binary column. The label is retained so the binarization is always
# reversible downstream.
#
# Usage: Rscript R/process_anes_2024.R
#        ANES_2024_CSV=/path/to/anes.csv Rscript R/process_anes_2024.R
# ==============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(data.table)
})

source(file.path("R", "utils.R"))

cat("\n=== Processing ANES 2024 Data ===\n")

# --- 1. Locate raw ANES ------------------------------------------------------
# Raw data is gitignored and lives outside the repo on this machine. Prefer
# data/raw/, then the ANES_2024_CSV override, then the known local path.

ANES_FILENAME <- "anes_timeseries_2024_csv_20250808.csv"
candidate_paths <- c(
  Sys.getenv("ANES_2024_CSV", unset = NA_character_),
  file.path("data", "raw", ANES_FILENAME),
  file.path("/mnt/data/Surveys/anes/data/2024", ANES_FILENAME)
)
candidate_paths <- candidate_paths[!is.na(candidate_paths) & nzchar(candidate_paths)]
anes_csv_path <- candidate_paths[file.exists(candidate_paths)][1]

if (is.na(anes_csv_path)) {
  stop("Raw ANES 2024 CSV not found. Looked in:\n  ",
       paste(candidate_paths, collapse = "\n  "),
       "\nSet ANES_2024_CSV to override.")
}
cat("Loading raw ANES data from:", anes_csv_path, "\n")

# --- 2. Question specifications ----------------------------------------------
# codes: ANES response code -> label. positive/negative: codes mapping to
# target_binary 1 / 0. Codes in neither (and all negative ANES missing codes)
# get target_binary = NA.

# !! SCALE DIRECTION IS NOT CONSISTENT ACROSS ANES ITEMS !!
# V241327 ASCENDS  (1 = Not important at all ... 5 = Extremely important)
# V242180 DESCENDS (1 = Extremely important  ... 5 = Not at all important)
# Never share one Likert rule across importance items without checking the
# codebook -- a shared rule gets one of them exactly backwards.

MARKETING_QUESTIONS <- list(
  basic_facts = list(
    anes_var = "basic_facts",
    anes_id  = "V241327",
    question = "How important is it that people agree on basic facts even if they disagree politically?",
    # ASCENDING scale.
    codes    = c("1" = "Not important at all", "2" = "A little important",
                 "3" = "Moderately important", "4" = "Very important",
                 "5" = "Extremely important"),
    # "Moderately important" is a lukewarm answer on an importance scale, not a
    # neutral midpoint, so it scores as non-endorsement rather than NA. This
    # keeps ~1,000 respondents and moves the marginal off the ceiling
    # (93% -> 75%). All five labels are retained for an alternative cut.
    positive = c(4L, 5L),
    negative = c(1L, 2L, 3L)
  ),
  election_efficacy = list(
    anes_var = "elections_attention",
    anes_id  = "V241235",
    question = "How much do you feel that having elections makes the government pay attention to what the people think?",
    codes    = c("1" = "A good deal", "2" = "Some", "3" = "Not much"),
    # External political efficacy (system responsiveness), NOT diffuse support
    # for democracy as a system. Strict cut: only "A good deal" counts as
    # efficacy; "Some" is too ambiguous to read as endorsement.
    # NOTE: the platform's old `gov_cares` recode coded "Not much" as 1 -- the
    # name asserted the opposite of what it stored. Do not restore it.
    positive = 1L,
    negative = c(2L, 3L)
  ),
  congress_approval = list(
    anes_var = "congress_job",
    anes_id  = "V241127",
    question = "Do you approve or disapprove of the way the U.S. Congress has been handling its job?",
    codes    = c("1" = "Approve", "2" = "Disapprove"),
    positive = 1L,   # Approve
    negative = 2L    # Disapprove
  ),
  social_trust = list(
    anes_var = "social_trust",
    anes_id  = "V241234",
    question = "Generally speaking, how often can you trust other people?",
    # !! DESCENDING scale -- the opposite of V241327 above. 1 is the MOST
    # trusting response, 5 the least. Coding positive = c(1, 2) is correct;
    # a shared "high code = endorsement" rule would invert this item exactly.
    codes    = c("1" = "Always", "2" = "Most of the time",
                 "3" = "About half the time", "4" = "Some of the time",
                 "5" = "Never"),
    # Generalized social trust, the GSS construct asked since 1972 -- the only
    # item in the set that is not about government, and the least
    # time-anchored. "About half the time" is a genuine midpoint here (unlike
    # "Moderately important" on an importance scale), but scoring it as
    # non-endorsement keeps the marginal at 45% rather than 74%, which is where
    # the usable variance is. See docs/methodology.md sec 2.
    positive = c(1L, 2L),
    negative = c(3L, 4L, 5L)
  )
)

# Screened and rejected: V241579 POLVIOL_JUSTIFIED ("violence never justified").
# On raw survey statistics it looked like the best complement in the 2024 study
# -- Dem-Rep gap -1.2, the smallest Dem/Ind/Rep spread of any candidate, and a
# 28.3-point demographic range. Fitted, its district estimates correlate -0.86
# with congress_approval, because race dominates both models with near-mirrored
# effects (White -0.49 vs +0.74, Asian +0.52 vs -0.55). As a targeting map it is
# an inverted copy of a question already in the set. Cell-level demographic
# profiles did NOT predict this; only the district estimates did.

# Not a marketing question. country_track is the regression anchor for this
# port: its output is byte-identical to the platform's shipped
# data/cleaned_survey_data/country_track.csv on all shared respondents. Delete
# this list to drop it. It is also the most partisan item tested (39-point
# Dem-Rep gap), which is why it is not in the marketing set.
VALIDATION_QUESTIONS <- list(
  country_track = list(
    anes_var = "right_track",
    anes_id  = "V241117",
    question = "Do you feel things in this country are generally going in the right direction, or do you feel things have pretty seriously gotten off on the wrong track?",
    codes    = c("1" = "Right direction", "2" = "Wrong track"),
    positive = 1L,   # Right direction
    negative = 2L    # Wrong track
  )
)

# democracy_importance (V242180) was screened and set aside for the marketing
# funnel per docs/methodology.md sec 2 -- 93% ceiling, only an 8.8-point
# demographic range, and it is a post-election item that loses ~500
# respondents to non-completion. Recoded here anyway at Jeff's explicit
# request for a one-off demo bundle (2026-08-14); the exclusion rationale
# still stands for the production marketing set and this entry should not be
# read as reversing it.
#
# !! DESCENDS, same trap V242180 is called out for above: 1 = Extremely
# important ... 5 = Not at all important. positive = c(1L, 2L) mirrors the
# "Very or Extremely important" cut basic_facts uses on its ASCENDING scale
# (there, positive = c(4L, 5L)) -- same cut point, opposite numeric codes.
DEMO_ONLY_QUESTIONS <- list(
  democracy_importance = list(
    anes_var = "democracy_importance",
    anes_id  = "V242180",
    question = "How important is the following issue in the country today? Keeping the U.S. a democracy.",
    codes    = c("1" = "Extremely important", "2" = "Very important",
                 "3" = "Moderately important", "4" = "Slightly important",
                 "5" = "Not at all important"),
    positive = c(1L, 2L),
    negative = c(3L, 4L, 5L)
  )
)

# --- 3. Load and select ------------------------------------------------------

anes24_raw <- fread(anes_csv_path) %>%
  select(
    unique_id   = V240001,
    PWT         = V240107a,
    STRATUM     = V240107d,
    PSU         = V240107c,
    hispanic    = V241512x,
    cd          = V243009,
    state       = V243001,
    region      = V243007,
    sex         = V241550,
    race        = V241501x,
    education   = V241465x,
    age         = V241458x,
    # marketing funnel outcomes
    basic_facts         = V241327,
    elections_attention = V241235,
    congress_job        = V241127,
    social_trust        = V241234,
    # validation fixture
    right_track         = V241117,
    # one-off demo bundle
    democracy_importance = V242180
  )

cat("Raw respondents:", nrow(anes24_raw), "\n")

# --- 4. Demographic recoding (canonical platform standard) -------------------

cat("Recoding demographics...\n")

anes24_clean <- anes24_raw %>%
  mutate(
    state = trimws(as.character(state)),
    state = if_else(nzchar(state), state, NA_character_),

    # "ST-XX"; at-large -> "ST-00"; missing district stays NA (see format_cd)
    cd = format_cd(state, cd),

    # Sex (1 = Man, 2 = Woman)
    sex = case_when(
      as.numeric(sex) == 1 ~ "Male",
      as.numeric(sex) == 2 ~ "Female",
      TRUE ~ NA_character_
    ),

    # Race (Hispanic-dominant). The hispanic origin item is only informative
    # for codes 1-6; negative codes are refusals and must not be read as
    # Hispanic.
    race = case_when(
      as.numeric(race) == 3 | (hispanic > 0 & hispanic < 7) ~ "Hispanic",
      as.numeric(race) == 1 ~ "White",
      as.numeric(race) == 2 ~ "Black",
      as.numeric(race) == 4 ~ "Asian",
      as.numeric(race) %in% c(5, 6) ~ "Other",
      TRUE ~ NA_character_
    ),

    # Education (4-cat invariant)
    educ = case_when(
      as.numeric(education) %in% c(1, 2) ~ "HS or less",
      as.numeric(education) == 3         ~ "Some College",
      as.numeric(education) == 4         ~ "BA/BS",
      as.numeric(education) == 5         ~ "Postgrad",
      TRUE ~ NA_character_
    ),

    # Age bins
    age_numeric = as.numeric(age),
    age_group = case_when(
      age_numeric %in% 18:24  ~ "18-24",
      age_numeric %in% 25:29  ~ "25-29",
      age_numeric %in% 30:34  ~ "30-34",
      age_numeric %in% 35:39  ~ "35-39",
      age_numeric %in% 40:44  ~ "40-44",
      age_numeric %in% 45:49  ~ "45-49",
      age_numeric %in% 50:54  ~ "50-54",
      age_numeric %in% 55:59  ~ "55-59",
      age_numeric %in% 60:64  ~ "60-64",
      age_numeric %in% 65:69  ~ "65-69",
      age_numeric %in% 70:74  ~ "70-74",
      age_numeric %in% 75:79  ~ "75-79",
      age_numeric %in% 80:150 ~ "80 plus",
      TRUE ~ NA_character_
    )
  )

# Region comes from the state crosswalk so that DC breaks out as its own level.
anes24_clean <- anes24_clean %>%
  left_join(.STATE_TO_REGION, by = c("state" = "state_abbr")) %>%
  mutate(region = region_name) %>%
  select(-region_name) %>%
  apply_canonical_levels()

# --- 5. Per-question extraction ----------------------------------------------

DEMO_COLS <- c("region", "state", "cd", "unique_id", "age_group", "race", "educ", "sex")

out_dir <- file.path("data", "cleaned")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# Respondents usable for MRP: every demographic and geographic cell present.
complete_demo <- anes24_clean %>%
  filter(!is.na(age_group), !is.na(sex), !is.na(race),
         !is.na(educ), !is.na(state), !is.na(cd), !is.na(region))

cat("Respondents with complete demographics:", nrow(complete_demo),
    sprintf("(dropped %d)\n", nrow(anes24_clean) - nrow(complete_demo)))

summaries <- list()

ALL_QUESTIONS <- c(MARKETING_QUESTIONS, VALIDATION_QUESTIONS, DEMO_ONLY_QUESTIONS)
question_role <- c(
  setNames(rep("marketing",  length(MARKETING_QUESTIONS)),  names(MARKETING_QUESTIONS)),
  setNames(rep("validation", length(VALIDATION_QUESTIONS)), names(VALIDATION_QUESTIONS)),
  setNames(rep("demo_only",  length(DEMO_ONLY_QUESTIONS)),  names(DEMO_ONLY_QUESTIONS))
)

for (qname in names(ALL_QUESTIONS)) {
  spec <- ALL_QUESTIONS[[qname]]
  cat(sprintf("\n--- %s [%s] (%s / %s) ---\n",
              qname, question_role[[qname]], spec$anes_id, spec$anes_var))

  raw_vals <- as.numeric(complete_demo[[spec$anes_var]])

  labels <- unname(spec$codes[as.character(raw_vals)])
  binary <- case_when(
    raw_vals %in% spec$positive ~ 1L,
    raw_vals %in% spec$negative ~ 0L,
    TRUE ~ NA_integer_
  )

  q_df <- complete_demo %>%
    select(all_of(DEMO_COLS)) %>%
    mutate(!!qname := factor(labels, levels = unname(spec$codes)),
           target_binary = binary) %>%
    filter(!is.na(.data[[qname]]))

  out_path <- file.path(out_dir, paste0(qname, ".csv"))
  fwrite(q_df, out_path)

  n_modelable <- sum(!is.na(q_df$target_binary))
  cat("  respondents with a valid response:", nrow(q_df), "\n")
  cat("  usable for binary model:", n_modelable,
      sprintf("(%d excluded as midpoint/NA)\n", nrow(q_df) - n_modelable))
  cat("  districts covered:", dplyr::n_distinct(q_df$cd), "\n")
  print(q_df %>% count(.data[[qname]], target_binary))
  cat("  ->", out_path, "\n")

  summaries[[qname]] <- tibble(
    question = qname, role = question_role[[qname]], anes_var = spec$anes_id,
    n = nrow(q_df), n_modelable = n_modelable,
    pct_positive = round(100 * mean(q_df$target_binary, na.rm = TRUE), 1)
  )
}

cat("\n=== Summary ===\n")
print(bind_rows(summaries))
cat("\nProcessing complete. Cleaned data in", out_dir, "\n")
