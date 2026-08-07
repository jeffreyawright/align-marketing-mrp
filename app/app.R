# ==============================================================================
# What America Thinks — an MRP demonstration
# ==============================================================================
# Answer a poll question, then reveal how your answer compares as you tell the
# app more about yourself. Each disclosure narrows the comparison group.
#
# The point of the demo: every figure shown is a model-based estimate for a
# population subgroup, not a raw survey tally. The app displays the number of
# actual survey respondents behind each slice, so you can watch it fall to
# single digits while the estimate stays stable. That gap is what
# multilevel regression and poststratification buys.
#
# Data: data/estimates/lookup_<question>.csv, produced by python/fit.py.
# Run:  shiny::runApp("app")
# ==============================================================================

library(shiny)
library(ggplot2)
library(data.table)

# --- Load -------------------------------------------------------------------

QUESTIONS <- list(
  basic_facts = list(
    poll  = "How important is it that people agree on basic facts, even if they disagree politically?",
    options = c("Extremely important", "Very important", "Moderately important",
                "A little important", "Not important at all"),
    agree = c("Extremely important", "Very important"),
    label = "say it is important that we agree on basic facts"
  ),
  election_efficacy = list(
    poll  = "How much do you feel that having elections makes the government pay attention to what people think?",
    options = c("A good deal", "Some", "Not much"),
    agree = c("A good deal"),
    label = "say elections make government pay attention a good deal"
  ),
  congress_approval = list(
    poll  = "Do you approve or disapprove of the way Congress is handling its job?",
    options = c("Approve", "Disapprove"),
    agree = c("Approve"),
    label = "approve of how Congress is handling its job"
  ),
  social_trust = list(
    poll  = "Generally speaking, how often can you trust other people?",
    # Displayed most-trusting first, matching the other items. Note this is the
    # reverse of the ANES code order for V241234, which descends -- the app
    # reads labels from the lookup file and never touches the codes.
    options = c("Always", "Most of the time", "About half the time",
                "Some of the time", "Never"),
    agree = c("Always", "Most of the time"),
    label = "say other people can usually be trusted"
  )
)

est_dir <- file.path("..", "data", "estimates")
if (!dir.exists(est_dir)) est_dir <- file.path("data", "estimates")

LOOKUP <- list()
for (q in names(QUESTIONS)) {
  f <- file.path(est_dir, paste0("lookup_", q, ".csv"))
  if (file.exists(f)) LOOKUP[[q]] <- fread(f)
}
if (length(LOOKUP) == 0) {
  stop("No lookup tables found in ", normalizePath(est_dir, mustWork = FALSE),
       "\nRun: python python/fit.py <question>")
}
AVAILABLE <- names(LOOKUP)

STATES <- sort(setdiff(unique(LOOKUP[[AVAILABLE[1]]]$state), "ALL"))
AGES   <- c("18-24","25-29","30-34","35-39","40-44","45-49","50-54",
            "55-59","60-64","65-69","70-74","75-79","80 plus")

# --- Helpers ----------------------------------------------------------------

#' Pull the single row matching a partially specified slice.
#' Unsupplied dimensions are "ALL" — that is what makes progressive disclosure
#' a lookup rather than a computation.
#'
#' Filtering is written as `d$col == arg` rather than data.table's `..arg`
#' notation. The `..` prefix resolves a name from the calling scope for the `j`
#' argument; used inside an `i` filter against columns of the same name it fails
#' with "object '..educ' not found", which is what an earlier version did on
#' every single call.
slice_row <- function(q, state = "ALL", age = "ALL", sex = "ALL",
                      race = "ALL", educ = "ALL") {
  d <- LOOKUP[[q]]
  hit <- d$state == state & d$age_group == age & d$sex == sex &
         d$race == race & d$educ == educ
  if (!any(hit)) return(NULL)
  d[which(hit)[1], ]
}

pct <- function(x) sprintf("%.0f%%", 100 * x)

# --- UI ---------------------------------------------------------------------

ui <- fluidPage(
  tags$head(tags$style(HTML("
    body { background:#fbfaf8; font-family:'Helvetica Neue',Helvetica,Arial,sans-serif;
           color:#1d1d1f; }
    .wrap { max-width: 760px; margin: 0 auto; padding: 28px 20px 60px; }
    h2 { font-weight: 600; letter-spacing:-0.4px; }
    .poll { font-size: 21px; line-height: 1.45; font-weight: 500; margin: 8px 0 18px; }
    .headline { font-size: 46px; font-weight: 700; letter-spacing:-1.4px; margin: 6px 0 2px; }
    .sub { color:#6b6b70; font-size: 15px; margin-bottom: 18px; }
    .card { background:#fff; border:1px solid #e8e6e1; border-radius:12px;
            padding:20px 22px; margin-bottom:16px; }
    .evidence { font-size:13px; color:#6b6b70; border-top:1px solid #efedea;
                margin-top:14px; padding-top:12px; }
    .lowrel { color:#8a5a00; background:#fff6e5; border-color:#f0dfb8; }
    .step { font-size:12px; text-transform:uppercase; letter-spacing:1.1px;
            color:#8a8a90; margin-bottom:6px; }
  "))),
  div(class = "wrap",
    h2("What America Thinks"),
    div(class = "sub",
        "American National Election Studies 2024 · modeled with multilevel regression and poststratification"),

    div(class = "card",
      div(class = "step", "The question"),
      selectInput("question", NULL, choices = setNames(AVAILABLE, AVAILABLE), width = "100%"),
      uiOutput("poll_ui")
    ),

    uiOutput("result_ui"),

    conditionalPanel("input.answered != null && input.answered != ''",
      div(class = "card",
        div(class = "step", "Tell us more, see a closer comparison"),
        fluidRow(
          column(4, selectInput("state", "Your state", c("—" = "ALL", STATES))),
          column(4, selectInput("age",   "Your age",   c("—" = "ALL", AGES))),
          column(4, selectInput("sex",   "Your sex",   c("—" = "ALL", "Male", "Female")))
        ),
        fluidRow(
          column(6, selectInput("race", "Your race/ethnicity",
                                c("—" = "ALL", "White","Black","Hispanic","Asian","Other"))),
          column(6, selectInput("educ", "Your education",
                                c("—" = "ALL", "HS or less","Some College","BA/BS","Postgrad")))
        )
      ),
      plotOutput("trace", height = "260px"),
      div(class = "evidence", style = "max-width:760px",
          strong("What you are looking at. "),
          "Each figure is a model estimate for the population subgroup you have described, ",
          "not a tally of survey responses. Watch the respondent count fall as you add detail — ",
          "the estimate stays usable long after the raw survey data would have run out. ",
          "That is the whole point of poststratification.")
    )
  )
)

# --- Server -----------------------------------------------------------------

server <- function(input, output, session) {

  spec <- reactive(QUESTIONS[[input$question]])

  output$poll_ui <- renderUI({
    tagList(
      div(class = "poll", spec()$poll),
      radioButtons("answered", NULL, choices = spec()$options, selected = character(0))
    )
  })

  current <- reactive({
    req(input$question)
    slice_row(input$question,
              state = input$state %||% "ALL", age  = input$age  %||% "ALL",
              sex   = input$sex   %||% "ALL", race = input$race %||% "ALL",
              educ  = input$educ  %||% "ALL")
  })

  output$result_ui <- renderUI({
    req(input$answered)
    r <- current()
    if (is.null(r)) {
      return(div(class = "card lowrel",
                 strong("No estimate for that combination."),
                 " Too few people in the population frame match it. Try removing one detail."))
    }
    agrees <- input$answered %in% spec()$agree
    described <- {
      bits <- c(if (!identical(input$age,  "ALL")) input$age,
                if (!identical(input$sex,  "ALL")) tolower(input$sex),
                if (!identical(input$race, "ALL")) input$race,
                if (!identical(input$educ, "ALL")) input$educ,
                if (!identical(input$state,"ALL")) paste("in", input$state))
      if (length(bits) == 0) "Americans" else paste("Americans", paste(bits, collapse = ", "))
    }
    div(class = if (r$reliability == "low") "card lowrel" else "card",
      div(class = "headline", pct(r$estimate)),
      div(class = "sub", paste("of", described, spec()$label)),
      div(if (agrees) "You agree with them." else "You are in the minority here."),
      div(class = "evidence",
        sprintf("95%% credible interval %s to %s · %s survey respondents match this group · %s reliability",
                pct(r$q025), pct(r$q975), format(r$n_survey, big.mark = ","), r$reliability),
        if (r$reliability == "low")
          " — this slice is thin; treat it as indicative only." else ""
      )
    )
  })

  # How the estimate moves as detail is added, and what it costs in certainty.
  output$trace <- renderPlot({
    req(input$answered)
    steps <- list(
      list(l = "Everyone",  a = list()),
      list(l = "+ state",   a = list(state = input$state)),
      list(l = "+ age",     a = list(state = input$state, age = input$age)),
      list(l = "+ sex",     a = list(state = input$state, age = input$age, sex = input$sex)),
      list(l = "+ race",    a = list(state = input$state, age = input$age, sex = input$sex,
                                     race = input$race)),
      list(l = "+ educ",    a = list(state = input$state, age = input$age, sex = input$sex,
                                     race = input$race, educ = input$educ))
    )
    rows <- list()
    for (s in steps) {
      a <- modifyList(list(state="ALL", age="ALL", sex="ALL", race="ALL", educ="ALL"), s$a)
      if (any(vapply(a, is.null, logical(1)))) next
      r <- slice_row(input$question, a$state, a$age, a$sex, a$race, a$educ)
      if (is.null(r)) next
      rows[[length(rows) + 1]] <- data.table(step = s$l, est = r$estimate,
                                             lo = r$q025, hi = r$q975, n = r$n_survey)
    }
    d <- rbindlist(rows)
    d[, step := factor(step, levels = unique(step))]
    ggplot(d, aes(step, est)) +
      geom_ribbon(aes(ymin = lo, ymax = hi, group = 1), fill = "#d7e3f4") +
      geom_line(aes(group = 1), colour = "#2f5f9e", linewidth = 0.9) +
      geom_point(size = 2.6, colour = "#2f5f9e") +
      geom_text(aes(label = paste0("n=", n)), vjust = -1.4, size = 3.2, colour = "#6b6b70") +
      scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
      labs(x = NULL, y = NULL,
           title = "Estimate and uncertainty as you add detail",
           subtitle = "Shaded band is the 95% credible interval; n is matching survey respondents") +
      theme_minimal(base_size = 13) +
      theme(panel.grid.minor = element_blank(),
            plot.title = element_text(face = "bold", size = 14),
            plot.subtitle = element_text(colour = "#6b6b70", size = 11))
  })
}

`%||%` <- function(a, b) if (is.null(a)) b else a

shinyApp(ui, server)
