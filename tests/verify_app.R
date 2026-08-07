#!/usr/bin/env Rscript
# Smoke test for app/app.R.
#
# The app is the only consumer of data/estimates/lookup_*.csv inside this repo,
# and it failed silently for a long time: slice_row() used data.table's `..name`
# notation inside an `i` filter, which does not resolve there, so every lookup
# raised "object '..educ' not found" and the app showed the no-estimate card for
# every input. Nothing caught it because nothing ever called the function.
#
# This exercises the real server reactives -- not a copy of them -- walking the
# whole disclosure funnel one step at a time for every question, and checking
# each row against the lookup CSVs directly. It also pins the behaviours the
# funnel depends on and that nothing else would catch:
#
#   * switching questions, Start over, and Change all reset to a blank slate;
#   * every choice offered at a step resolves to a populated slice, so the walk
#     cannot dead-end in the 6,819 combinations that do not exist;
#   * the categorical reliability word appears only once the walk is complete;
#   * the zero-respondent panel tracks n_survey rather than the step count;
#   * Skip advances without recording a value or adding a trace point;
#   * the question card collapses once answered and reopens on Change.
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

# Two profiles, in STEPS order, walked for every question. `matched` still has a
# couple of literal ANES respondents behind it; `unseen` has none for any of the
# four questions, which is the case the app is built to dramatise and the only
# one that reaches the zero-respondent panel.
PROFILES <- list(
  matched = list(state = "TX", age_group = "35-39", sex = "Female",
                 race = "Hispanic", educ = "BA/BS"),
  unseen  = list(state = "AK", age_group = "18-24", sex = "Female",
                 race = "Asian", educ = "Postgrad")
)

# shinyAppFile() sets the working directory to app/ for the duration of the
# test, so resolve the lookup paths against the repo root before that happens.
EST <- normalizePath(file.path("data", "estimates"), mustWork = TRUE)

failures <- character()
check <- function(ok, what) if (!isTRUE(ok)) failures <<- c(failures, what)

# renderUI output arrives as a list of html/deps; flatten it to searchable text.
as_text <- function(o) paste(unlist(o), collapse = " ")

shiny::testServer(shiny::shinyAppFile("app/app.R"), {
  # testServer's data mask exposes the server function's locals (rv, current,
  # reset) but not the app file's top-level objects. `reset` is a closure over
  # the server frame, whose parents reach the app's globals, so get() from there
  # is how the test sees STEPS, BLANK, and the two lookup helpers.
  app_get    <- function(n) get(n, envir = environment(reset))
  BLANK      <- app_get("BLANK")
  STEPS      <- app_get("STEPS")
  slice_row  <- app_get("slice_row")
  choices_for <- app_get("choices_for")

  clicks <- 0L; restarts <- 0L

  for (q in names(AGREE)) {
    lk  <- fread(file.path(EST, paste0("lookup_", q, ".csv")))
    row <- function(sel) lk[state == sel$state & age_group == sel$age_group &
                            sel$sex == sex & race == sel$race & educ == sel$educ][1]

    # --- blank slate on question change ---------------------------------------
    session$setInputs(question = q)
    check(rv$step == 0L,        paste(q, "step not reset on question change"))
    check(is.null(rv$answer),   paste(q, "answer not cleared on question change"))
    check(identical(rv$sel, BLANK), paste(q, "demographics not cleared on question change"))
    check(is.null(rv$hist),     paste(q, "history not cleared on question change"))

    natl <- current()
    check(!is.null(natl) && isTRUE(all.equal(natl$estimate, row(BLANK)$estimate)),
          paste(q, "national estimate wrong"))

    for (pname in names(PROFILES)) {
      profile <- PROFILES[[pname]]
      tag <- paste(q, pname)

      # Re-answering after "Start over" needs the clear first: updateRadioButtons
      # does not round-trip to a client under testServer, so without it the input
      # never changes value and the observer never fires -- which is exactly the
      # bug the clear was added to fix.
      session$setInputs(answered = "")
      session$setInputs(answered = AGREE[[q]])
      check(identical(rv$answer, AGREE[[q]]), paste(tag, "answer not recorded"))
      check(!is.null(rv$hist) && nrow(rv$hist) == 1L, paste(tag, "history not seeded"))
      check(!grepl("Reliability:", as_text(output$result_ui), fixed = TRUE),
            paste(tag, "reliability word shown before the walk is complete"))

      # --- walk the five steps ------------------------------------------------
      sel <- BLANK
      for (i in seq_along(STEPS)) {
        s  <- STEPS[[i]]
        ch <- choices_for(q, sel, s$attr, s$universe)
        check(length(ch) > 0L, sprintf("%s step %d offers no choices", tag, i))
        # Every offered choice must resolve -- this is the dead-end guard.
        bad <- Filter(function(v) { t <- sel; t[[s$attr]] <- v
                                    is.null(slice_row(q, t)) }, ch)
        check(length(bad) == 0L,
              sprintf("%s step %d offers %d unpopulated choice(s)", tag, i, length(bad)))

        want <- profile[[s$attr]]
        check(want %in% ch, sprintf("%s step %d does not offer %s", tag, i, want))

        session$setInputs(pick = want)
        clicks <- clicks + 1L
        session$setInputs(go = clicks)

        sel[[s$attr]] <- want
        check(rv$step == i,            sprintf("%s did not advance to step %d", tag, i))
        check(identical(rv$sel, sel),  sprintf("%s selection wrong after step %d", tag, i))
        check(nrow(rv$hist) == i + 1L, sprintf("%s history wrong after step %d", tag, i))

        got <- current()
        check(!is.null(got) && isTRUE(all.equal(got$estimate, row(sel)$estimate)),
              sprintf("%s estimate wrong after step %d", tag, i))
      }

      # --- the completed panel ------------------------------------------------
      deep <- current()
      txt  <- as_text(output$result_ui)
      check(grepl("Reliability:", txt, fixed = TRUE),
            paste(tag, "reliability word missing once the walk is complete"))
      check(grepl("Nobody like you", txt, fixed = TRUE) == (deep$n_survey == 0),
            paste(tag, "zero-respondent reveal does not track n_survey"))
      check(nchar(as_text(output$step_ui)) > 0, paste(tag, "step panel did not render"))
      check(!is.null(output$trace), paste(tag, "trace plot did not render"))

      cat(sprintf("  %-20s %-8s national %.3f  deep %.3f  n=%-3d %s\n", q, pname,
                  natl$estimate, deep$estimate, as.integer(deep$n_survey),
                  deep$reliability))

      restarts <- restarts + 1L
      session$setInputs(restart = restarts)
      check(rv$step == 0L && is.null(rv$answer) && identical(rv$sel, BLANK),
            paste(tag, "Start over did not clear the funnel"))
    }
  }

  # --- skipping leaves the attribute at ALL and does not add a trace point -----
  session$setInputs(question = "basic_facts")
  session$setInputs(answered = AGREE$basic_facts)
  before <- nrow(rv$hist)
  session$setInputs(skip = 1L)
  check(rv$step == 1L, "skip did not advance the step")
  check(rv$sel$state == "ALL", "skip recorded a value")
  check(nrow(rv$hist) == before, "skip added a trace point despite no change")

  # --- the collapsed question card and its way back ---------------------------
  # answered_yet drives the conditionalPanel that hides the picker and the five
  # radio buttons once the question is answered.
  check(isTRUE(answered_yet()), "question card did not collapse after answering")
  session$setInputs(change = 1L)
  check(is.null(rv$answer) && rv$step == 0L && identical(rv$sel, BLANK),
        "Change did not clear the funnel")
  check(isFALSE(answered_yet()), "question card did not reopen on Change")
})

cat("\n")
if (length(failures) > 0L) {
  cat("FAIL:\n"); cat(paste0("  - ", failures, collapse = "\n"), "\n")
  quit(status = 1L)
}
cat("PASS: all questions walk the full funnel and render.\n")
