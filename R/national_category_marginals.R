# ==============================================================================
# Script: national_category_marginals.R
# Purpose: Design-weighted national category breakdown for each funnel and
#          marketing question, for demo "national color" copy.
#
# This is NOT a model and NOT the poststratified headline. It is a
# survey::svydesign / svymean marginal over the full valid-response sample --
# see the header written into the output CSV for the reconciliation caveat.
#
# Usage: Rscript R/national_category_marginals.R
# ==============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(data.table)
  library(survey)
})

cat("\n=== National category marginals ===\n")

# --- 1. Locate raw ANES (same resolution order as process_anes_2024.R) ------

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
cat("Loading raw ANES weights from:", anes_csv_path, "\n")

# PRE full-sample weight is V240107a; POST full-sample weight is V240107b.
# Both share the same PSU (V240107c) and stratum (V240107d) variables per the
# codebook's "use variance PSU" / "use variance stratum" table -- confirmed
# these are the same PSU/STRATUM process_anes_2024.R already uses for PWT.
weights_raw <- fread(anes_csv_path) %>%
  select(unique_id = V240001,
         w_pre  = V240107a,
         w_post = V240107b,
         PSU     = V240107c,
         STRATUM = V240107d)

# --- 2. Question -> field period -----------------------------------------
# V241xxx items were fielded PRE-election; V242xxx items POST-election.
# Approximated with a single weight per question, matching the item's own
# field period rather than one weight for every question.
QUESTION_WEIGHT <- c(
  basic_facts          = "w_pre",
  election_efficacy    = "w_pre",
  congress_approval    = "w_pre",
  social_trust         = "w_pre",
  country_offtrack     = "w_pre",
  gov_few_interests    = "w_pre",
  democracy_importance = "w_post",
  officials_dont_care  = "w_post",
  no_say               = "w_post"
)

# --- 3. Per-question weighted category marginal ---------------------------

marginals <- list()

for (qname in names(QUESTION_WEIGHT)) {
  cleaned_path <- file.path("data", "cleaned", paste0(qname, ".csv"))
  if (!file.exists(cleaned_path)) {
    stop("Missing cleaned file for ", qname, ": ", cleaned_path,
         "\nRun Rscript R/process_anes_2024.R first.")
  }

  q_df <- fread(cleaned_path) %>%
    select(unique_id, all_of(qname)) %>%
    filter(!is.na(.data[[qname]]))

  wcol <- QUESTION_WEIGHT[[qname]]
  joined <- q_df %>%
    inner_join(weights_raw %>% select(unique_id, PSU, STRATUM, w = all_of(wcol)),
               by = "unique_id") %>%
    filter(!is.na(w), w > 0) %>%
    mutate(!!qname := factor(.data[[qname]]))

  design <- svydesign(ids = ~PSU, strata = ~STRATUM, weights = ~w,
                       data = joined, nest = TRUE)

  fm <- as.formula(paste0("~", qname))
  sm <- svymean(fm, design)

  cats <- sub(paste0("^", qname), "", names(sm))
  props <- as.numeric(sm)
  ses <- sqrt(diag(vcov(sm)))

  cat(sprintf("  %-22s [%s] n=%d, %d categories\n", qname, wcol, nrow(joined), length(cats)))

  marginals[[qname]] <- tibble(
    question = qname,
    weight_used = wcol,
    category = cats,
    proportion = round(props, 4),
    se = round(ses, 4)
  )
}

out <- bind_rows(marginals)

# --- 4. Write with a header comment ----------------------------------------

out_path <- file.path("data", "estimates", "national_category_marginals.csv")

header <- c(
  "# national_category_marginals.csv",
  "#",
  "# Design-weighted survey marginal (survey::svydesign + svymean), NOT a model",
  "# and NOT the poststratified headline. For each funnel + marketing question,",
  "# the full-category breakdown over the MRP-eligible sample (complete",
  "# demographics + district, matching data/cleaned/<question>.csv), weighted",
  "# with the ANES design (ids = PSU, strata = STRATUM, weights = full-sample",
  "# weight matching the item's field period).",
  "#",
  "# Weight caveat: PRE-election items (V241xxx) use V240107a; POST-election",
  "# items (V242xxx: democracy_importance, officials_dont_care, no_say) use",
  "# V240107b. This is a single-weight-per-item approximation, not a",
  "# multiply-imputed or panel-adjusted weight.",
  "#",
  "# Reconciliation caveat: this survey-weighted marginal will NOT equal the",
  "# poststratified headline (e.g. basic_facts 74.7% raw vs 71.3% poststrat --",
  "# see docs/methodology.md sec 2). That is expected. It is national COLOR, to",
  "# be presented as \"nationally...\", never as a decomposition of the",
  "# \"people like you\" number.",
  "#",
  sprintf("# Generated: Rscript R/national_category_marginals.R (%s)", Sys.Date())
)

writeLines(header, out_path)
fwrite(out, out_path, append = TRUE, col.names = TRUE)

cat("\n->", out_path, "\n")
cat("Done.\n")
