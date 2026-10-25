# R/landing.R
# Full-screen landing page shown when the app opens: a short intro sequence,
# then a 3D carousel of the 10 LSA topics with "Try the predictor" in the centre.
# Styles and animation live in www/landing.css and www/landing.js.

topic_cards <- function(bundle) {
  load <- bundle$lsa$loadings
  ts   <- bundle$topic_summary
  lapply(colnames(load), function(lab) {
    row <- ts[ts$topic == lab, ]
    list(
      label = lab,
      words = names(sort(load[, lab], decreasing = TRUE))[1:5],
      pct   = if (nrow(row)) round(100 * row$actual_positive) else NA,
      n     = if (nrow(row)) row$reviews else NA
    )
  })
}

landing_ui <- function(bundle) {
  acc <- sprintf("%.1f%%", 100 * bundle$metrics$accuracy[1])
  tagList(
    tags$head(
      tags$link(rel = "stylesheet", href = "landing.css"),
      tags$script(HTML(sprintf("window.LANDING_TOPICS = %s;",
                               jsonlite::toJSON(topic_cards(bundle), auto_unbox = TRUE)))),
      tags$script(src = "landing.js", defer = NA)
    ),
    div(
      id = "landing", class = "intro-playing", role = "dialog", `aria-label` = "Welcome",

      div(class = "ld-bg"),
      div(class = "ld-stars", id = "ldStarsA"),
      div(class = "ld-stars", id = "ldStarsB"),

      # ---- the short "commercial": logo pop, tagline, audience line ----
      div(
        class = "ld-intro", `aria-hidden` = "true",
        div(class = "ld-logo",
            span(class = "ld-logo-mark", HTML('<svg viewBox="0 0 48 48"><defs><linearGradient id="ldg" x1="8" y1="8" x2="40" y2="40" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#8ef4ff"/><stop offset=".5" stop-color="#35d8ff"/><stop offset="1" stop-color="#0a86d8"/></linearGradient></defs><rect x="6" y="10" width="36" height="28" rx="6" fill="none" stroke="url(#ldg)" stroke-width="3.2"/><path d="M20 18v12l10-6z" fill="url(#ldg)"/></svg>')),
            span(class = "ld-logo-text", "CINE", tags$b("SENSE"))),
        div(class = "ld-tag", "What do audiences really think?"),
        div(class = "ld-for", "Built for streaming platforms like Netflix and Prime Video")
      ),

      # ---- main hero ----
      div(
        class = "ld-hero",
        div(class = "ld-badge",
            tags$i(HTML('<svg viewBox="5 1 14 22" preserveAspectRatio="none"><path d="M13.9 1.6 5.5 13.6a.7.7 0 0 0 .6 1.1h4.2l-1 7.7a.7.7 0 0 0 1.25.55l8.3-12.1a.7.7 0 0 0-.6-1.1h-4.2l1-7.7a.7.7 0 0 0-1.25-.55Z"/></svg>')),
            tags$b(sprintf("%s accurate on unseen reviews", acc))),
        h1(class = "ld-h1", "What do audiences", tags$br(), "really think?"),
        p(class = "ld-sub",
          tags$b("LSA topic discovery + sentiment analysis"), " on ",
          sprintf("%s IMDb reviews.", format(bundle$n_train + bundle$n_test, big.mark = ",")),
          tags$br(), "Paste a review, or a whole movie's worth, and see the verdict."),
        div(class = "ld-ctas",
            tags$a(href = "#", class = "ld-btn", id = "ldTryReview", span("Try the predictor")),
            tags$a(href = "#", class = "ld-btn ld-btn-ghost", id = "ldTryMovie", span("Predict a movie"))),
        div(class = "ld-stats",
            div(tags$b(acc), span("test accuracy")),
            div(tags$b("50,000"), span("IMDb reviews")),
            div(tags$b("10"), span("LSA topics")),
            div(tags$b(nrow(bundle$movies)), span("movies to explore")))
      ),

      # ---- 3D topic carousel ----
      div(class = "ld-showcase", div(class = "ld-ring", id = "ldRing")),

      tags$button(type = "button", class = "ld-skip", id = "ldSkip", "Skip intro")
    )
  )
}
