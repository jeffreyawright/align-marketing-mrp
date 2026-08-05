# ==============================================================================
# Script: run_marketing_mrp.R
# Purpose: Bayesian MRP for the MOVE marketing funnel questions (brms/Stan).
# Ported from: demographai-platform/r-scoring/run_marketing_mrp.R
#
# STATUS: ported but NOT yet runnable in this repo. It still depends on two
# artifacts that live in the platform repo and have not been brought over:
#   - R/mister_p.R                          (poststratification aggregator)
#   - data/frames/synthetic_frames_combined.rds  (ACS poststrat frame)
# Steps 1-3 are structurally complete; steps 4-5 will fail until those land.
#
# This is the brms/Stan backend being replaced by JAX/NumPyro. It is kept as
# the reference implementation and validation target for the ported model:
# NumPyro posteriors should agree with these within posterior uncertainty.
#
# Usage: Rscript R/run_marketing_mrp.R [question]
#   question: basic_facts (default) | election_efficacy | congress_approval
#             | country_track (validation fixture)
# ==============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(brms)
  library(cmdstanr)
  library(tictoc)
  library(data.table)
})

source(file.path("R", "utils.R"))

args <- commandArgs(trailingOnly = TRUE)
question <- if (length(args) >= 1) args[1] else "basic_facts"

# country_track is the validation fixture, not a marketing question -- it is
# accepted here so the brms fit can be compared against the platform's.
VALID_QUESTIONS <- c("basic_facts", "election_efficacy", "congress_approval",
                     "country_track")
if (!question %in% VALID_QUESTIONS) {
  stop("Unknown question: ", question,
       "\nExpected one of: ", paste(VALID_QUESTIONS, collapse = ", "))
}
message("Question: ", question)

# --- 0. GPU Configuration ---
# OpenCL device for Stan (RTX 4070 SUPER)
options(cmdstanr_opencl_platform_id = 0)
options(cmdstanr_opencl_device_id = 0)

# --- 1. Load Data ---
message("\n[STEP 1/4] Loading cleaned ANES 2024 data...")
data_path <- file.path("data", "cleaned", paste0(question, ".csv"))
if (!file.exists(data_path)) {
  stop("Cleaned data not found: ", data_path,
       "\nRun: Rscript R/process_anes_2024.R")
}
survey_raw <- fread(data_path)

# target_binary is written by process_anes_2024.R. Rows with no binary coding
# (the excluded Likert midpoint on democracy_importance) drop out here.
survey_clean <- survey_raw %>%
  filter(!is.na(target_binary)) %>%
  apply_canonical_levels()

message(sprintf("  %d respondents, %d districts",
                nrow(survey_clean), dplyr::n_distinct(survey_clean$cd)))

# --- 2. Load Poststrat Frame ---
message("\n[STEP 2/4] Loading poststratification frame...")
poststrat_file <- file.path("data", "frames", "synthetic_frames_combined.rds")
if (!file.exists(poststrat_file)) {
  stop("Poststrat frame not found: ", poststrat_file,
       "\nPort it from the platform repo (data/census_tables/) before fitting.")
}
poststrat_df <- readRDS(poststrat_file) %>%
  standardize_poststrat_frame()

# mister_p requires a GEOID column; 'cd' serves that purpose here.
if (!"GEOID" %in% names(poststrat_df)) {
  poststrat_df$GEOID <- poststrat_df$cd
}

# --- 3. Fit Model (GPU Accelerated) ---
message("\n[STEP 3/4] Fitting Bayesian MRP model (GPU Accelerated)...")
formula_mrp <- bf(
  target_binary ~ 1 + (1 | age_group) + (1 | sex) + (1 | race) + (1 | educ) +
    (1 | region) + (1 | state) + (1 | cd)
)

priors <- c(
  prior(normal(0, 1.5), class = "Intercept"),
  prior(exponential(1), class = "sd")
)

stan_tmp_dir <- file.path("models", "stan_tmp")
dir.create(stan_tmp_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path("models", "marketing"), recursive = TRUE, showWarnings = FALSE)

tic("Model Fit")
fit_mrp <- brm(
  formula = formula_mrp,
  data = survey_clean,
  family = bernoulli(link = "logit"),
  prior = priors,
  chains = 4,
  iter = 2000,
  warmup = 1000,
  cores = 4,
  backend = "cmdstanr",
  opencl = opencl(c(0, 0)),
  output_dir = stan_tmp_dir,
  file = file.path("models", "marketing", paste0(question, "_mrp")),
  file_refit = "always",
  control = list(adapt_delta = 0.95, max_treedepth = 14),
  seed = 42,
  refresh = 100
)
toc()

# --- 4. Poststratification ---
message("\n[STEP 4/4] Generating poststratified estimates...")
source(file.path("R", "mister_p.R"))

tic("Poststrat (CD)")
mrp_results_cd <- mister_p(
  state = "all",
  draws = 1000,
  group_vars = "GEOID",
  model = fit_mrp,
  poststrat_table = poststrat_df,
  n_cores = 8
)
toc()

tic("Poststrat (State)")
mrp_results_state <- mister_p(
  state = "all",
  draws = 1000,
  group_vars = "state",
  model = fit_mrp,
  poststrat_table = poststrat_df,
  n_cores = 8
)
toc()

# --- 5. Export ---
message("\nExporting results...")
out_dir <- file.path("data", "estimates")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

fwrite(mrp_results_cd$summary,    file.path(out_dir, paste0(question, "_estimates_cd.csv")))
fwrite(mrp_results_state$summary, file.path(out_dir, paste0(question, "_estimates_state.csv")))

message("\nDone. Results saved to ", out_dir)
message(sprintf("  - CD estimates: %d",    nrow(mrp_results_cd$summary)))
message(sprintf("  - State estimates: %d", nrow(mrp_results_state$summary)))
