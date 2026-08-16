# ==============================================================================
# What America Thinks — an MRP demonstration
# ==============================================================================
# Answer a poll question, then disclose one thing about yourself at a time and
# watch the estimate move toward your group.
#
# The point of the demo is NOT that disclosure buys precision -- it does the
# opposite. Median credible-interval width goes from 0.033 at the national level
# to 0.120 once all five attributes are given. What disclosure buys is
# specificity, and the headline fact is that the survey evidence underneath the
# number disappears while the number itself stays usable: 86% of fully specified
# slices have zero matching ANES respondents. That is what poststratification is
# for, and it is what this app is built to show.
#
# Reliability is therefore surfaced once, at the end, rather than at every step.
# The credible interval is shown numerically and as a band throughout -- the
# widening is honest and visible -- but re-rendering the categorical word
# "medium" at each step reads as the app progressively disclaiming itself, which
# country_offtrack would trigger on 75% of its deep (five-detail) slices.
#
# Data: data/estimates/lookup_<question>.csv, produced by python/fit.py.
# Run:  shiny::runApp("app")
# Test: Rscript tests/verify_app.R
# ==============================================================================

library(shiny)
library(ggplot2)
library(data.table)

`%||%` <- function(a, b) if (is.null(a)) b else a

# --- Questions ----------------------------------------------------------------

# `short` is what goes in the picker. The full `poll` text stays below it: a
# 100-character question truncates badly inside a mobile <select>, and the
# redundancy worth removing was the slug ("basic_facts"), not the question.
#
# The funnel five (see CLAUDE.md "The funnel five" / docs/methodology.md "The
# funnel question set"), not the marketing four -- selected for cross-partisan
# resonance rather than district discrimination. `officials_dont_care` and
# `no_say` drop ANES's "Neither" midpoint from the model entirely (target_binary
# is NA for it), so it is left out of `options` here too: every choice offered
# must resolve to a side the model actually fit, or a respondent picking the
# dropped midpoint would fall through `agree` into a false "you are in the
# minority" verdict.
QUESTIONS <- list(
  country_offtrack = list(
    short = "Whether the country is on the right track",
    poll  = "Do you feel things in this country are generally going in the right direction, or do you feel things have pretty seriously gotten off on the wrong track?",
    options = c("Right direction", "Wrong track"),
    agree = c("Wrong track"),
    label = "say the country has gotten off on the wrong track"
  ),
  democracy_importance = list(
    short = "How important keeping democracy is",
    # !! V242180 DESCENDS (1 = Extremely important ... 5 = Not at all
    # important), the opposite of basic_facts's V241327. The app reads labels
    # from the lookup file and never touches the codes, so this only matters if
    # you are eyeballing the recode -- see docs/methodology.md sec 3.
    poll  = "How important is it that the U.S. remains a democracy?",
    options = c("Extremely important", "Very important", "Moderately important",
                "Slightly important", "Not at all important"),
    agree = c("Extremely important", "Very important"),
    label = "say keeping the U.S. a democracy is important"
  ),
  gov_few_interests = list(
    short = "Who government is really run for",
    poll  = "Is government run by a few big interests looking out for themselves, or for the benefit of all the people?",
    options = c("Run by a few big interests", "For the benefit of all the people"),
    agree = c("Run by a few big interests"),
    label = "say government is run by a few big interests looking out for themselves"
  ),
  officials_dont_care = list(
    short = "Whether officials care what you think",
    poll  = "Public officials don't care much what people like me think.",
    options = c("Agree strongly", "Agree somewhat", "Disagree somewhat", "Disagree strongly"),
    agree = c("Agree strongly", "Agree somewhat"),
    label = "agree that public officials don't care much what people like them think"
  ),
  no_say = list(
    short = "Whether you have a say in what government does",
    poll  = "People like me don't have any say about what the government does.",
    options = c("Agree strongly", "Agree somewhat", "Disagree somewhat", "Disagree strongly"),
    agree = c("Agree strongly", "Agree somewhat"),
    label = "agree that people like them don't have any say about what the government does"
  )
)

# --- Load ---------------------------------------------------------------------

est_dir <- file.path("..", "data", "estimates")
if (!dir.exists(est_dir)) est_dir <- file.path("data", "estimates")

KEY_COLS <- c("state", "age_group", "sex", "race", "educ")
BLANK    <- setNames(as.list(rep("ALL", length(KEY_COLS))), KEY_COLS)

#' The lookup key for a slice. Attributes not yet disclosed are "ALL", which is
#' what makes progressive disclosure a lookup rather than a computation.
mk_key <- function(sel) {
  paste(sel[["state"]], sel[["age_group"]], sel[["sex"]],
        sel[["race"]], sel[["educ"]], sep = "|")
}

LOOKUP <- list()
for (q in names(QUESTIONS)) {
  f <- file.path(est_dir, paste0("lookup_", q, ".csv"))
  if (!file.exists(f)) next
  d <- fread(f)
  # A single keyed character column rather than a five-column key. The earlier
  # version filtered with `d$col == arg` across all 58,701 rows on every render;
  # choices_for() below needs up to 51 lookups per step, so the scan has to go.
  d[, slice_key := mk_key(list(state = state, age_group = age_group, sex = sex,
                               race = race, educ = educ))]
  setkey(d, slice_key)
  LOOKUP[[q]] <- d
}
if (length(LOOKUP) == 0) {
  stop("No lookup tables found in ", normalizePath(est_dir, mustWork = FALSE),
       "\nRun: python python/fit.py <question>")
}
AVAILABLE <- names(LOOKUP)
REF <- LOOKUP[[AVAILABLE[1]]]

# Respondents behind the national estimate, per question -- the denominator the
# zero-match reveal is measured against.
NAT_N <- vapply(LOOKUP, function(d) d[.(mk_key(BLANK)), nomatch = NULL]$n_survey[1],
                numeric(1))

# Categories come from the data, ordered canonically. Anything present in the
# file but absent from the canonical vector is appended rather than dropped, so
# a drifted recode shows up in the UI instead of vanishing silently.
ordered_levels <- function(col, canon) {
  present <- setdiff(unique(REF[[col]]), "ALL")
  c(intersect(canon, present), sort(setdiff(present, canon)))
}
STATES <- sort(setdiff(unique(REF$state), "ALL"))
AGES   <- ordered_levels("age_group", c("18-24","25-29","30-34","35-39","40-44",
                                        "45-49","50-54","55-59","60-64","65-69",
                                        "70-74","75-79","80 plus"))
SEXES  <- ordered_levels("sex",   c("Male", "Female"))
RACES  <- ordered_levels("race",  c("White", "Black", "Hispanic", "Asian", "Other"))
EDUCS  <- ordered_levels("educ",  c("HS or less", "Some College", "BA/BS", "Postgrad"))

# --- The disclosure funnel ----------------------------------------------------

STEPS <- list(
  list(attr = "state",     label = "Which state do you live in?",  universe = STATES, trace = "+ state"),
  list(attr = "age_group", label = "How old are you?",             universe = AGES,   trace = "+ age"),
  list(attr = "sex",       label = "What is your sex?",            universe = SEXES,  trace = "+ sex"),
  list(attr = "race",      label = "Your race or ethnicity?",      universe = RACES,  trace = "+ race"),
  list(attr = "educ",      label = "How far did you get in school?", universe = EDUCS, trace = "+ educ")
)

#' Pull the single row matching a partially specified slice, or NULL.
slice_row <- function(q, sel) {
  r <- LOOKUP[[q]][.(mk_key(sel)), nomatch = NULL]
  if (nrow(r) == 0L) NULL else r
}

#' Values of `attr` that have a populated row given what has already been
#' disclosed. 6,819 of 65,520 slices do not exist and the gaps start at three
#' attributes, so an unfiltered menu walks the user into a dead end at exactly
#' the moment the funnel has promised a payoff. Filtering turns that into a
#' shorter menu.
choices_for <- function(q, sel, attr, universe) {
  keys <- vapply(universe, function(v) { s <- sel; s[[attr]] <- v; mk_key(s) },
                 character(1), USE.NAMES = FALSE)
  universe[keys %chin% LOOKUP[[q]]$slice_key]
}

pct  <- function(x) sprintf("%.0f%%", 100 * x)
hrow <- function(label, r) data.table(step = label, est = r$estimate,
                                      lo = r$q025, hi = r$q975, n = r$n_survey)

#' Interval as a band on a 0-100 track. The widening is the honest half of the
#' story, so it is drawn at every step rather than summarised in a word.
ci_bar <- function(lo, hi, est) {
  div(class = "cibar-wrap",
    div(class = "cibar",
      div(class = "cibar-band",
          style = sprintf("left:%.2f%%;width:%.2f%%", 100 * lo, 100 * (hi - lo))),
      div(class = "cibar-pt", style = sprintf("left:%.2f%%", 100 * est))
    ),
    div(class = "cibar-ax", span("0%"), span("100%"))
  )
}

# --- UI -----------------------------------------------------------------------

ui <- fluidPage(
  tags$head(tags$style(HTML("
    body { background:#fbfaf8; font-family:'Helvetica Neue',Helvetica,Arial,sans-serif;
           color:#1d1d1f; }
    .wrap { max-width: 1040px; margin: 0 auto; padding: 26px 18px 70px; }
    h2 { font-weight: 600; letter-spacing:-0.5px; margin:0 0 4px; }
    .poll { font-size: 20px; line-height: 1.4; font-weight: 500; margin: 10px 0 14px; }
    .headline { font-size: 52px; font-weight: 700; letter-spacing:-1.6px; margin: 2px 0 0;
                animation: pop .42s cubic-bezier(.2,.85,.25,1); }
    .sub { color:#6b6b70; font-size: 15px; }
    .card { background:#fff; border:1px solid #e8e6e1; border-radius:14px;
            padding:20px 22px; margin-bottom:16px; }
    .card.muted { color:#8a8a90; }
    .evidence { font-size:13px; color:#6b6b70; border-top:1px solid #efedea;
                margin-top:14px; padding-top:12px; line-height:1.5; }
    .lowrel { color:#8a5a00; background:#fff6e5; border-color:#f0dfb8; }
    .step { font-size:12px; text-transform:uppercase; letter-spacing:1.1px;
            color:#8a8a90; margin-bottom:8px; }

    /* Two columns on desktop, one on mobile. The result is first in the DOM so
       that on a phone it sits above the controls that change it -- the previous
       layout put it above but out of view once you scrolled to interact. */
    .grid { display:grid; grid-template-columns: 1.05fr 1fr; gap:18px; align-items:start; }
    @media (min-width: 761px) { .sticky { position: sticky; top: 12px; } }
    @media (max-width: 760px) {
      .grid { grid-template-columns: 1fr; }
      .headline { font-size: 40px; }
      .card { padding:16px 17px; margin-bottom:12px; }
    }

    .delta { display:inline-block; font-size:14px; font-weight:600; padding:2px 10px;
             border-radius:999px; margin-left:10px; vertical-align:9px;
             animation: pop .42s cubic-bezier(.2,.85,.25,1); }
    .delta.up   { background:#e6f4ea; color:#1c7a3e; }
    .delta.down { background:#fdecec; color:#a52222; }
    .delta.flat { background:#f0efec; color:#6b6b70; }

    .chips { margin:0 0 2px; }
    .chip { display:inline-block; background:#eef2f8; color:#2f5f9e; border:1px solid #dbe5f2;
            border-radius:999px; padding:3px 11px; font-size:13px; margin:0 6px 6px 0; }
    .chip.answer { font-weight:600; }
    .poll-compact { font-size:16px; line-height:1.4; color:#4a4a50; }

    /* Shiny sizes the plot from the container it measured at render time; without
       this the image overflows the card when the viewport is narrower. */
    .shiny-plot-output img { max-width:100%; height:auto; }

    .cibar-wrap { margin:16px 0 2px; }
    .cibar { position:relative; height:10px; background:#efedea; border-radius:5px; }
    .cibar-band { position:absolute; top:0; bottom:0; background:#c9dcf3; border-radius:5px;
                  transform-origin:center; animation: bandin .45s ease-out; }
    .cibar-pt { position:absolute; top:-3px; width:3px; height:16px; background:#2f5f9e;
                border-radius:2px; }
    .cibar-ax { display:flex; justify-content:space-between; font-size:11px;
                color:#a5a5ab; margin-top:4px; }

    .nsurv { font-size:15px; color:#4a4a50; margin-top:12px; }
    .nsurv b { font-size:19px; color:#1d1d1f; }
    .zero { background:#14141c; color:#f4f4f6; border-radius:12px; padding:15px 17px;
            margin-top:14px; font-size:14px; line-height:1.55;
            animation: pop .5s cubic-bezier(.2,.85,.25,1); }
    .zero b { color:#fff; }

    .btnrow { margin-top:4px; }
    .btnrow .btn { margin-right:8px; }
    .progress-dots span { display:inline-block; width:7px; height:7px; border-radius:50%;
                          background:#dcdad5; margin-right:5px; }
    .progress-dots span.on { background:#2f5f9e; }

    @keyframes pop { from { transform: scale(.955); opacity:.3 } to { transform:none; opacity:1 } }
    @keyframes bandin { from { opacity:0; transform: scaleX(.4) } to { opacity:1; transform:none } }
  "))),
  div(class = "wrap",
    h2("What America Thinks"),
    div(class = "sub",
        "American National Election Studies 2024 · modeled with multilevel regression and poststratification"),

    # The picker and the five radio buttons are ~400px of chrome that stops being
    # useful the moment they are answered, and on a phone they push the controls
    # that drive the funnel below the fold. Collapsing to a one-line summary is
    # done with conditionalPanel rather than by re-rendering: `question` has to
    # stay mounted, or recreating it would fire its own change observer and reset
    # the funnel in a loop.
    div(class = "card", style = "margin-top:16px",
      conditionalPanel("!output.answered_yet",
        div(class = "step", "Pick a question"),
        selectInput("question", NULL, width = "100%",
                    choices = setNames(AVAILABLE,
                                       vapply(QUESTIONS[AVAILABLE], `[[`, "", "short"))),
        uiOutput("poll_ui")
      ),
      conditionalPanel("output.answered_yet",
        div(class = "step", "Your answer"),
        div(class = "poll-compact", textOutput("poll_compact", inline = TRUE)),
        div(style = "margin-top:9px",
            span(class = "chip answer", textOutput("answer_compact", inline = TRUE)),
            actionLink("change", "Change"))
      )
    ),

    div(class = "grid",
      div(uiOutput("result_ui", class = "sticky")),
      div(uiOutput("step_ui"))
    ),

    uiOutput("trace_ui")
  )
)

# --- Server -------------------------------------------------------------------

server <- function(input, output, session) {

  spec <- reactive(QUESTIONS[[input$question]])

  rv <- reactiveValues(answer = NULL, step = 0L, sel = BLANK,
                       hist = NULL, delta = NA_real_)

  reset <- function() {
    rv$answer <- NULL
    rv$step   <- 0L
    rv$sel    <- BLANK
    rv$hist   <- NULL
    rv$delta  <- NA_real_
  }

  # Switching questions restarts the funnel. Without this the second question
  # opens fully specified and the reveal is already spent -- and because the
  # radio buttons are re-rendered rather than re-read, `input$answered` still
  # holds the previous question's answer for one flush, long enough to render
  # the new question's verdict against it.
  observeEvent(input$question, reset(), ignoreInit = TRUE)

  # "Start over" keeps the question, so poll_ui does not re-render and the radio
  # buttons keep their selection. Clearing them explicitly is what makes the
  # blank slate real -- otherwise the user is looking at a selected answer while
  # the app waits for one.
  reopen <- function() {
    reset()
    updateRadioButtons(session, "answered", selected = character(0))
  }
  observeEvent(input$restart, reopen(), ignoreInit = TRUE)
  observeEvent(input$change,  reopen(), ignoreInit = TRUE)

  # Named rather than assigned inline so the test can read it: a bare reactive
  # attached to `output` is not retrievable through testServer's output proxy.
  answered_yet <- reactive(!is.null(rv$answer))
  output$answered_yet <- answered_yet
  outputOptions(output, "answered_yet", suspendWhenHidden = FALSE)

  output$poll_compact   <- renderText(spec()$poll)
  output$answer_compact <- renderText(rv$answer %||% "")

  output$poll_ui <- renderUI({
    tagList(
      div(class = "poll", spec()$poll),
      radioButtons("answered", NULL, choices = spec()$options, selected = character(0))
    )
  })

  observeEvent(input$answered, {
    a <- input$answered
    if (is.null(a) || !nzchar(a)) return()   # the cleared radio after a reset
    rv$answer <- a
    if (is.null(rv$hist)) {
      rv$hist <- hrow("Everyone", slice_row(input$question, BLANK))
    }
  }, ignoreInit = TRUE)

  current <- reactive({
    req(input$question)
    slice_row(input$question, rv$sel)
  })

  # --- advancing the funnel ---

  observeEvent(input$go, {
    if (rv$step >= length(STEPS)) return()
    s <- STEPS[[rv$step + 1L]]
    v <- input$pick %||% ""
    # `pick` is rebuilt each step, so guard against the client's stale value
    # arriving before the new select has rendered.
    if (!nzchar(v) || !(v %in% s$universe)) return()

    sel <- rv$sel
    sel[[s$attr]] <- v
    r <- slice_row(input$question, sel)
    if (is.null(r)) return()          # choices_for() should make this unreachable

    rv$delta <- r$estimate - rv$hist[.N]$est
    rv$sel   <- sel
    rv$hist  <- rbind(rv$hist, hrow(s$trace, r))
    rv$step  <- rv$step + 1L
  })

  observeEvent(input$skip, {
    if (rv$step >= length(STEPS)) return()
    rv$delta <- NA_real_
    rv$step  <- rv$step + 1L
  })

  # --- the panel that stays in view ---

  described <- function(sel) {
    bits <- c(if (sel$age_group != "ALL") sel$age_group,
              if (sel$sex   != "ALL") tolower(sel$sex),
              if (sel$race  != "ALL") sel$race,
              if (sel$educ  != "ALL") sel$educ,
              if (sel$state != "ALL") paste("in", sel$state))
    if (length(bits) == 0) "Americans" else paste("Americans", paste(bits, collapse = ", "))
  }

  chip_row <- function(sel) {
    vals <- vapply(STEPS, function(s) sel[[s$attr]], character(1))
    keep <- vals != "ALL"
    if (!any(keep)) return(NULL)
    div(class = "chips", lapply(vals[keep], function(v) span(class = "chip", v)))
  }

  delta_tag <- function(d) {
    if (is.na(d)) return(NULL)
    pts <- 100 * d
    cls <- if (pts >= 0.5) "up" else if (pts <= -0.5) "down" else "flat"
    txt <- if (abs(pts) < 0.5) "no change"
           else sprintf("%+.0f %s", pts, if (abs(round(pts)) == 1) "pt" else "pts")
    span(class = paste("delta", cls), txt)
  }

  output$result_ui <- renderUI({
    if (is.null(rv$answer)) {
      return(div(class = "card muted",
                 "Answer the question above, then tell us about yourself one detail at a ",
                 "time. The estimate will follow you."))
    }
    r <- current()
    if (is.null(r)) {
      return(div(class = "card lowrel",
                 strong("No estimate for that combination."),
                 " Too few people in the population frame match it."))
    }
    done   <- rv$step >= length(STEPS)
    agrees <- rv$answer %in% spec()$agree
    n      <- r$n_survey

    div(class = if (done && r$reliability == "low") "card lowrel" else "card",
      chip_row(rv$sel),
      div(class = "headline", pct(r$estimate), delta_tag(rv$delta)),
      div(class = "sub", paste("of", described(rv$sel), spec()$label)),
      div(style = "margin-top:10px",
          if (agrees) "You agree with them." else "You are in the minority here."),

      ci_bar(r$q025, r$q975, r$estimate),
      div(class = "sub", style = "font-size:13px",
          sprintf("95%% credible interval %s to %s", pct(r$q025), pct(r$q975))),

      div(class = "nsurv",
        if (n == 0) tagList(strong("0"), " survey respondents match this group.")
        else tagList(strong(format(n, big.mark = ",")),
                     sprintf(" survey %s match this group.",
                             if (n == 1) "respondent" else "respondents"))),

      # Only at the end. Mid-walk the "0 survey respondents" line above already
      # says it, and repeating the full panel at every step from the moment n
      # hits zero is both redundant and 200px of scroll on a phone.
      if (done && n == 0) div(class = "zero",
        strong("Nobody like you took this survey."),
        sprintf(" Not one of the %s people ANES interviewed matches every detail you gave. ",
                format(NAT_N[[input$question]], big.mark = ",")),
        "The figure above is still an estimate for your group — it is built from the ",
        "whole sample at once rather than from the handful of people who happen to ",
        "look like you. That is what poststratification is for."),

      if (done) div(class = "evidence",
        sprintf("Reliability: %s (interval %s points wide). ",
                r$reliability, sprintf("%.0f", 100 * r$ci_width)),
        "Telling us more makes the estimate more specific, not more certain — the ",
        "interval widens as the group narrows. What holds up is that the estimate ",
        "stays usable long after the raw survey data has run out.")
    )
  })

  # --- the next thing we ask for ---

  output$step_ui <- renderUI({
    if (is.null(rv$answer)) return(NULL)

    dots <- div(class = "progress-dots",
                lapply(seq_along(STEPS), function(i)
                  span(class = if (i <= rv$step) "on" else "")))

    if (rv$step >= length(STEPS)) {
      return(div(class = "card",
        div(class = "step", "That is everything the model can use"), dots,
        div(style = "margin-top:12px",
            sprintf("Five details, and the estimate moved from %s to %s.",
                    pct(rv$hist[1]$est), pct(rv$hist[.N]$est))),
        div(class = "btnrow", style = "margin-top:14px",
            actionButton("restart", "Start over", class = "btn btn-default"))
      ))
    }

    s  <- STEPS[[rv$step + 1L]]
    ch <- choices_for(input$question, rv$sel, s$attr, s$universe)

    div(class = "card",
      div(class = "step", sprintf("Step %d of %d — tell us one thing",
                                  rv$step + 1L, length(STEPS))),
      dots,
      selectInput("pick", s$label, width = "100%",
                  choices = c("Choose one…" = "", setNames(ch, ch))),
      div(class = "btnrow",
        actionButton("go", "Show me people like me →", class = "btn btn-primary"),
        actionButton("skip", "Skip", class = "btn btn-link"))
    )
  })

  # --- how the estimate moved ---

  output$trace_ui <- renderUI({
    if (is.null(rv$hist) || nrow(rv$hist) < 2) return(NULL)
    # Title and subtitle are HTML rather than ggplot titles: ggplot draws text
    # into a fixed-width device and clips it, so at a 324px phone width the
    # title lost its last two words. HTML wraps.
    tagList(
      div(class = "card", style = "padding-bottom:8px",
        div(style = "font-weight:700;font-size:15px", "Estimate and uncertainty as you add detail"),
        div(class = "sub", style = "font-size:12.5px;margin-bottom:4px",
            "Shaded band is the 95% credible interval; n is matching survey respondents"),
        plotOutput("trace", height = "270px")
      ),
      div(class = "evidence", style = "max-width:760px",
          strong("What you are looking at. "),
          "Each figure is a model estimate for the population subgroup you have described, ",
          "not a tally of survey responses. Watch the respondent count fall as you add detail — ",
          "the estimate stays usable long after the raw survey data would have run out. ",
          "That is the whole point of poststratification.")
    )
  })

  output$trace <- renderPlot({
    d <- rv$hist
    req(!is.null(d), nrow(d) >= 2)
    d <- copy(d)[, step := factor(step, levels = unique(step))]
    ggplot(d, aes(step, est)) +
      geom_ribbon(aes(ymin = lo, ymax = hi, group = 1), fill = "#d7e3f4") +
      geom_line(aes(group = 1), colour = "#2f5f9e", linewidth = 0.9) +
      geom_point(size = 2.6, colour = "#2f5f9e") +
      geom_text(aes(label = paste0("n=", n)), vjust = -1.4, size = 3.2, colour = "#6b6b70") +
      scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
      labs(x = NULL, y = NULL) +
      theme_minimal(base_size = 12) +
      theme(panel.grid.minor = element_blank(),
            plot.margin = margin(4, 10, 2, 2))
  })
}

shinyApp(ui, server)
