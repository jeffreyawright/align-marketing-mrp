# ==============================================================================
# Script: utils.R
# Purpose: Canonical demographic definitions and shared helpers.
# Ported from: demographai-platform/r-scoring/utils.R
#
# These category definitions are INVARIANT across all ALIGN projects. The
# poststratification frame depends on exact alignment between the survey recode
# and the ACS frame -- do not add bins or merge categories here.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
})

# --- Canonical factor levels -------------------------------------------------
# Use these when setting levels in any recode, survey or frame side.

.CANONICAL_AGE_LEVELS    <- c("18-24", "25-29", "30-34", "35-39", "40-44",
                              "45-49", "50-54", "55-59", "60-64", "65-69",
                              "70-74", "75-79", "80 plus")
.CANONICAL_SEX_LEVELS    <- c("Male", "Female")
.CANONICAL_RACE_LEVELS   <- c("White", "Black", "Hispanic", "Asian", "Other")
.CANONICAL_EDUC_LEVELS   <- c("HS or less", "Some College", "BA/BS", "Postgrad")
.CANONICAL_REGION_LEVELS <- c("Northeast", "Midwest", "South", "West", "DC")

# --- Geography ---------------------------------------------------------------

#' State -> census region crosswalk
#'
#' DC is broken out as its own region per the canonical geography definition.
.STATE_TO_REGION <- tibble::tribble(
  ~state_abbr, ~region_name,
  "CT", "Northeast", "ME", "Northeast", "MA", "Northeast", "NH", "Northeast",
  "RI", "Northeast", "VT", "Northeast", "NJ", "Northeast", "NY", "Northeast",
  "PA", "Northeast",
  "IL", "Midwest", "IN", "Midwest", "MI", "Midwest", "OH", "Midwest",
  "WI", "Midwest", "IA", "Midwest", "KS", "Midwest", "MN", "Midwest",
  "MO", "Midwest", "NE", "Midwest", "ND", "Midwest", "SD", "Midwest",
  "DE", "South", "DC", "DC", "FL", "South", "GA", "South", "MD", "South",
  "NC", "South", "SC", "South", "VA", "South", "WV", "South", "AL", "South",
  "KY", "South", "MS", "South", "TN", "South", "AR", "South", "LA", "South",
  "OK", "South", "TX", "South",
  "AZ", "West", "CO", "West", "ID", "West", "MT", "West", "NV", "West",
  "NM", "West", "UT", "West", "WY", "West", "AK", "West", "CA", "West",
  "HI", "West", "OR", "West", "WA", "West"
)

#' Format a congressional district as "ST-XX"
#'
#' At-large districts arrive as 0 and are rendered "ST-00". Districts that are
#' missing or blank in the source stay NA -- paste0() would otherwise silently
#' produce the literal string "ST-NA", which survives an is.na() filter and
#' becomes a spurious district level in the model.
#'
#' @param state Character vector of two-letter state abbreviations
#' @param cd Vector of district numbers (character or numeric)
#' @return Character vector of "ST-XX" codes, NA where either input is missing
format_cd <- function(state, cd) {
  cd <- trimws(as.character(cd))
  cd[cd == ""] <- NA_character_
  state <- trimws(as.character(state))
  state[state == ""] <- NA_character_

  padded <- stringr::str_pad(cd, width = 2, side = "left", pad = "0")
  out <- paste0(state, "-", padded)
  out[is.na(state) | is.na(padded)] <- NA_character_
  out
}

#' Apply canonical factor levels to a data frame's demographic columns
#'
#' @param df Data frame with age_group, sex, race, educ, region, state columns
#' @return df with canonical factor levels applied to whichever are present
apply_canonical_levels <- function(df) {
  if ("age_group" %in% names(df)) df$age_group <- factor(df$age_group, levels = .CANONICAL_AGE_LEVELS)
  if ("sex"       %in% names(df)) df$sex       <- factor(df$sex,       levels = .CANONICAL_SEX_LEVELS)
  if ("race"      %in% names(df)) df$race      <- factor(df$race,      levels = .CANONICAL_RACE_LEVELS)
  if ("educ"      %in% names(df)) df$educ      <- factor(df$educ,      levels = .CANONICAL_EDUC_LEVELS)
  if ("region"    %in% names(df)) df$region    <- factor(df$region,    levels = .CANONICAL_REGION_LEVELS)
  if ("state"     %in% names(df)) df$state     <- factor(df$state)
  df
}

# --- Poststrat frame standardization -----------------------------------------

#' Standardize poststrat frame column names to the canonical schema
#'
#' Transforms legacy column names from synthetic_frames_combined.rds into the
#' names required by the MRP formula:
#'   gender     -> sex          (rename)
#'   state_code -> state        (FIPS "06" -> abbrev "CA" via tigris::fips_codes)
#'   cd_code    -> cd           (construct "CA-32", drop cd_code + state_code)
#'   educ       -> validated    (stop() if levels don't match canonical 4-cat)
#'
#' Educ CANNOT be fixed here -- a non-canonical frame requires regeneration.
#'
#' @param df Poststrat frame as loaded from readRDS()
#' @return df with canonical column names and factor levels
standardize_poststrat_frame <- function(df) {
  if ("gender" %in% names(df)) {
    df <- df %>% rename(sex = gender)
  }

  if ("state_code" %in% names(df) && !("state" %in% names(df))) {
    fips <- tigris::fips_codes %>%
      select(state_code, state_abbr = state) %>%
      distinct()

    df <- df %>%
      left_join(fips, by = "state_code") %>%
      mutate(state = state_abbr) %>%
      select(-state_abbr)
  }

  if ("cd_code" %in% names(df) && "state" %in% names(df) && !("cd" %in% names(df))) {
    df <- df %>% mutate(cd = format_cd(state, cd_code))
  }

  df <- df %>% select(-any_of(c("cd_code", "state_code", "model_cd", "model_cd_119")))

  if ("educ" %in% names(df)) {
    invalid_levels <- setdiff(unique(as.character(df$educ)), .CANONICAL_EDUC_LEVELS)
    if (length(invalid_levels) > 0) {
      stop(paste0(
        "Non-canonical education levels detected in frame: ",
        paste(invalid_levels, collapse = ", "), "\n",
        "Required levels: ", paste(.CANONICAL_EDUC_LEVELS, collapse = ", "), "\n",
        "Action: regenerate the synthetic frame to fix labels."
      ))
    }
  }

  apply_canonical_levels(df)
}
