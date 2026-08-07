# ==============================================================================
# Script: run_marketing_mrp.R
# Purpose: Specification artifact + cross-implementation validation, in the
#          rstan ecosystem. NOT a production fitting path.
# Ported from: demographai-platform/r-scoring/run_marketing_mrp.R
#
# python/fit.py is the production path: it fits on GPU and poststratifies per
# draw with the ACS vintage guard. This script exists for two things that the
# bambi/NumPyro path cannot provide on its own:
#
#   1. A METHODOLOGY ARTIFACT. brms::stancode() emits the generated Stan
#      program -- priors, likelihood, parameterization, all explicit -- without
#      fitting anything. That is the model in a form a reviewer or methodologist
#      can audit directly, and it is regenerated rather than maintained.
#
#   2. A CROSS-IMPLEMENTATION CHECK. The existing validation of python/fit.py is
#      bambi-against-bambi: same library, same sampler, same priors. It proves
#      the data plumbing is faithful, not that the model specification is right.
#      brms/Stan is a genuinely different stack, so agreement across it is real
#      evidence. Run once per question, keep the artifact, move on.
#
# Poststratification was deliberately removed. It required mister_p.R, which was
# never ported, and python/fit.py already does it correctly with uncertainty.
# Porting mister_p.R would mean a second poststratification implementation
# needing its own ACS-vintage guard -- cost without benefit.
#
# Usage:
#   Rscript R/run_marketing_mrp.R basic_facts           # stancode only (seconds)
#   Rscript R/run_marketing_mrp.R basic_facts --fit     # + fit and compare to JAX
# ==============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(brms)
  library(data.table)
})

source(file.path("R", "utils.R"))

args     <- commandArgs(trailingOnly = TRUE)
question <- if (length(args) >= 1) args[1] else "basic_facts"
do_fit   <- "--fit" %in% args

VALID_QUESTIONS <- c("basic_facts", "election_efficacy", "congress_approval",
                     "social_trust", "country_track")
if (!question %in% VALID_QUESTIONS) {
  stop("Unknown question: ", question,
       "\nExpected one of: ", paste(VALID_QUESTIONS, collapse = ", "))
}
message("Question: ", question)

# --- Model specification -----------------------------------------------------
# Priors MUST match python/fit.py. bambi uses Exponential(lam=1) on group-level
# sds and Normal(0, 1.5) on the intercept; brms writes the same two as below.
# A mismatch here silently invalidates the whole point of the comparison.

formula_mrp <- bf(
  target_binary ~ 1 + (1 | age_group) + (1 | sex) + (1 | race) + (1 | educ) +
    (1 | region) + (1 | state)
)

priors <- c(
  prior(normal(0, 1.5), class = "Intercept"),
  prior(exponential(1), class = "sd")
)

# --- 1. Load cleaned data ----------------------------------------------------
data_path <- file.path("data", "cleaned", paste0(question, ".csv"))
if (!file.exists(data_path)) {
  stop("Cleaned data not found: ", data_path,
       "\nRun: Rscript R/process_anes_2024.R")
}

survey_clean <- fread(data_path) %>%
  filter(!is.na(target_binary)) %>%
  apply_canonical_levels()

message(sprintf("  %d respondents, %d states, %.1f%% positive",
                nrow(survey_clean), dplyr::n_distinct(survey_clean$state),
                100 * mean(survey_clean$target_binary)))

# --- 2. Emit the Stan program (no fitting required) --------------------------
stan_dir <- file.path("docs", "stan")
dir.create(stan_dir, recursive = TRUE, showWarnings = FALSE)
stan_path <- file.path(stan_dir, paste0(question, "_model.stan"))

writeLines(
  brms::stancode(formula_mrp, data = survey_clean,
                 family = bernoulli(link = "logit"), prior = priors),
  stan_path
)
message("\nStan program written to ", stan_path)

data_spec <- brms::standata(formula_mrp, data = survey_clean,
                            family = bernoulli(link = "logit"), prior = priors)
message(sprintf("  N = %d, %d grouping factors",
                data_spec$N, sum(grepl("^N_[0-9]+$", names(data_spec)))))

if (!do_fit) {
  message("\nPass --fit to also fit the model and compare against the JAX run.")
  quit(status = 0)
}

# --- 3. Fit (rstan backend; cmdstanr is not installed on this machine) -------
backend <- if (requireNamespace("cmdstanr", quietly = TRUE)) "cmdstanr" else "rstan"
message("\nFitting with backend: ", backend,
        if (backend == "rstan") "  (no OpenCL; this is a one-off validation fit)" else "")

dir.create(file.path("models", "marketing"), recursive = TRUE, showWarnings = FALSE)

fit_mrp <- brm(
  formula = formula_mrp,
  data    = survey_clean,
  family  = bernoulli(link = "logit"),
  prior   = priors,
  chains  = 4,
  iter    = 3000,
  warmup  = 1500,
  cores   = 4,
  backend = backend,
  control = list(adapt_delta = 0.99, max_treedepth = 12),
  seed    = 42,
  refresh = 500
)

saveRDS(fit_mrp, file.path("models", "marketing", paste0(question, "_brms.rds")))

# --- 4. Compare against the bambi/NumPyro posterior --------------------------
jax_path <- file.path("models", "marketing", paste0(question, "_mrp_summary_jax.csv"))
if (!file.exists(jax_path)) {
  message("\nNo JAX summary at ", jax_path, " -- skipping comparison.")
  message("Run: python python/fit.py ", question)
  quit(status = 0)
}

jax <- fread(jax_path) %>% rename(param_jax = V1)

brms_draws <- posterior::summarise_draws(
  fit_mrp, mean, sd, "rhat", "ess_bulk"
) %>% as_tibble()

# brms and bambi name the same quantities differently:
#   b_Intercept                  <-> Intercept
#   sd_<factor>__Intercept       <-> 1|<factor>_sigma
#   r_<factor>[<level>,Intercept] <-> 1|<factor>[<level>]
to_jax_name <- function(v) {
  dplyr::case_when(
    v == "b_Intercept" ~ "Intercept",
    stringr::str_detect(v, "^sd_.*__Intercept$") ~
      paste0("1|", stringr::str_match(v, "^sd_(.*)__Intercept$")[, 2], "_sigma"),
    stringr::str_detect(v, "^r_.*\\[.*,Intercept\\]$") ~
      paste0("1|", stringr::str_match(v, "^r_([^\\[]+)\\[")[, 2],
             "[", stringr::str_match(v, "\\[(.*),Intercept\\]$")[, 2], "]"),
    TRUE ~ NA_character_
  )
}

cmp <- brms_draws %>%
  mutate(param_jax = to_jax_name(variable)) %>%
  filter(!is.na(param_jax)) %>%
  inner_join(jax %>% select(param_jax, mean_jax = mean, sd_jax = sd),
             by = "param_jax") %>%
  mutate(
    diff = mean - mean_jax,
    # difference in units of posterior sd -- the scale on which "the same
    # posterior" is a meaningful claim
    z = abs(diff) / pmax(sd_jax, 1e-9)
  ) %>%
  arrange(desc(z))

val_dir <- file.path("docs", "validation")
dir.create(val_dir, recursive = TRUE, showWarnings = FALSE)
val_path <- file.path(val_dir, paste0(question, "_brms_vs_jax.csv"))
fwrite(cmp %>% select(variable, param_jax, mean_brms = mean, mean_jax,
                      sd_brms = sd, sd_jax, diff, z, rhat, ess_bulk),
       val_path)

message("\n=== brms (Stan) vs bambi (NumPyro) ===")
message(sprintf("  %d parameters matched", nrow(cmp)))
message(sprintf("  max |difference| = %.3f posterior sd", max(cmp$z)))
message(sprintf("  max rhat = %.4f, min ess_bulk = %.0f",
                max(cmp$rhat, na.rm = TRUE), min(cmp$ess_bulk, na.rm = TRUE)))
print(cmp %>% select(variable, mean, mean_jax, sd_jax, z) %>% head(8))
message("\nWritten to ", val_path)

if (max(cmp$z) > 0.5) {
  message("\nWARNING: divergence beyond MCMC noise. Check that priors still ",
          "match python/fit.py -- exponential(1) on sd, normal(0, 1.5) on Intercept.")
}

# --- 5. Posterior predictive check (CLAUDE.md convergence criteria) ----------
ppc_path <- file.path(val_dir, paste0(question, "_ppcheck.png"))
png(ppc_path, width = 1200, height = 800, res = 150)
print(pp_check(fit_mrp, ndraws = 100))
invisible(dev.off())
message("Posterior predictive check written to ", ppc_path)

message("\nDone. This is a validation artifact -- python/fit.py remains the ",
        "production path.")
