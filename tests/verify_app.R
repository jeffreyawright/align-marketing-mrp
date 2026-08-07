#!/usr/bin/env Rscript
# Smoke test for app/app.R.
#
# The app is the only consumer of data/estimates/lookup_*.csv inside this repo,
# and it failed silently for a long time: slice_row() used data.table's `..name`
# notation inside an `i` filter, which does not resolve there, so every lookup
# raised "object '..educ' not found" and the app showed the no-estimate card for
# every input. Nothing caught it because nothing ever called the function.
#
# This exercises the real server reactives -- not a copy of them -- for every
# question, at both ends of the disclosure funnel, and checks the answers
# against the lookup CSVs directly.
#
# Run from the repository root:
#   Rscript tests/verify_app.R

suppressPackageStartupMessages({
  library(shiny); library(data.table); library(ggplot2)
})

# One "agree"-side answer per question, so the result card takes its main branch.
AGREE <- list(basic_facts       = "Extremely important",
              election_efficacy = "A good deal",
              congress_approval = "Approve",
              social_trust      = "Most of the time")

DEEP <- list(state = "TX", age = "35-39", sex = "Female",
             race = "Hispanic", educ = "BA/BS")

# shinyAppFile() sets the working directory to app/ for the duration of the
# test, so resolve the lookup paths against the repo root before that happens.
EST <- normalizePath(file.path("data", "estimates"), mustWork = TRUE)

failures <- 0L

shiny::testServer(shiny::shinyAppFile("app/app.R"), {
  for (q in names(AGREE)) {
    lk <- fread(file.path(EST, paste0("lookup_", q, ".csv")))

    session$setInputs(question = q, answered = AGREE[[q]],
                      state = "ALL", age = "ALL", sex = "ALL",
                      race = "ALL", educ = "ALL")
    got_natl <- current()

    session$setInputs(state = DEEP$state, age = DEEP$age, sex = DEEP$sex,
                      race = DEEP$race, educ = DEEP$educ)
    got_deep <- current()

    # rendering must not error
    ui <- output$result_ui
    tr <- output$trace

    want_natl <- lk[state == "ALL" & age_group == "ALL" & sex == "ALL" &
                    race == "ALL" & educ == "ALL"][1]
    want_deep <- lk[state == DEEP$state & age_group == DEEP$age &
                    sex == DEEP$sex & race == DEEP$race & educ == DEEP$educ][1]

    ok <- !is.null(got_natl) && !is.null(got_deep) &&
          isTRUE(all.equal(got_natl$estimate, want_natl$estimate)) &&
          isTRUE(all.equal(got_deep$estimate, want_deep$estimate)) &&
          length(ui) > 0 && !is.null(tr)

    if (!ok) failures <<- failures + 1L
    cat(sprintf("  %-20s %s  national %.3f  deep %.3f\n", q,
                if (ok) "OK  " else "FAIL",
                if (is.null(got_natl)) NA_real_ else got_natl$estimate,
                if (is.null(got_deep)) NA_real_ else got_deep$estimate))
  }
})

cat("\n")
if (failures > 0L) {
  cat(sprintf("FAIL: %d question(s) did not round-trip through the app.\n", failures))
  quit(status = 1L)
}
cat("PASS: all questions resolve through the app and render.\n")
