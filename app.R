# app.R - Movie Review Sentiment Dashboard
# Open this file in RStudio and click "Run App".
# Needs model/model_bundle.rds (created by train_model.R).

library(shiny)
library(bslib)
library(ggplot2)
library(dplyr)
library(tidyr)
library(scales)
source("R/features.R")
source("R/landing.R")

if (!file.exists("model/model_bundle.rds")) {
  stop("model/model_bundle.rds not found - run train_model.R first.")
}
bundle <- readRDS("model/model_bundle.rds")
model  <- bundle$model
lsa    <- bundle$lsa

col_pos <- "#00798c"
col_neg <- "#d1495b"
theme_set(theme_minimal(base_size = 14))

examples <- list(
  "Positive" = "One of the best films I have seen this year. The acting is superb, especially the lead, and the music fits every scene perfectly. A beautiful, moving story that I would happily watch again. Highly recommended.",
  "Negative" = "What a waste of two hours. The plot makes no sense, the dialogue is laughable and the acting is just awful. I kept waiting for it to get better but it never did. Avoid this one.",
  "Mixed"    = "The special effects are impressive and the action scenes are fun, but the story is thin and the characters are forgettable. Not bad for a lazy Sunday, but nothing special.",
  "Negation" = "I don't think this movie was good at all. Not funny, not scary, and certainly not worth the money."
)

movie_choices <- setNames(
  bundle$movies$movie_id,
  sprintf("%s  (%d reviews)", bundle$movies$movie_id, bundle$movies$reviews)
)

# ---- helpers -----------------------------------------------------------------

analyse_review <- function(text) {
  x     <- featurize(text, bundle$vocab, bundle$idf)
  prob  <- predict_prob(x, model)
  terms <- explain_terms(x, model)
  topics <- topic_scores(text, lsa)
  list(prob = prob, terms = terms, topics = topics[1, ],
       topic = dominant_topic(topics), lexicon = lexicon_scores(text, bundle$lexicons))
}

highlight_html <- function(text, terms) {
  words <- str_split(clean_text(text), " ")[[1]]
  uni   <- terms |> filter(!str_detect(term, " "))
  lim   <- max(abs(uni$contribution), 1e-9)
  spans <- vapply(words, function(w) {
    k <- match(w, uni$term)
    if (is.na(k)) return(htmltools::htmlEscape(w))
    c <- uni$contribution[k]
    alpha <- round(0.15 + 0.6 * abs(c) / lim, 2)
    rgb <- if (c > 0) "0,121,140" else "209,73,91"
    sprintf('<span title="%+.3f" style="background:rgba(%s,%s);border-radius:4px;padding:1px 3px;">%s</span>',
            c, rgb, alpha, htmltools::htmlEscape(w))
  }, character(1))
  HTML(paste(spans, collapse = " "))
}

split_reviews <- function(txt) {
  parts <- str_split(txt, "\\n\\s*\\n")[[1]]
  parts <- str_squish(parts)
  parts[nchar(parts) >= 15]
}

fmt_prob <- function(p) {
  if (p > 0.999) ">99.9%" else if (p < 0.001) "<0.1%" else sprintf("%.1f%%", 100 * p)
}

prob_box <- function(p) {
  value_box(
    title = "Prediction",
    value = if (p > 0.5) "POSITIVE" else "NEGATIVE",
    p(paste(fmt_prob(p), "probability positive")),
    theme = value_box_theme(bg = if (p > 0.5) col_pos else col_neg, fg = "white"),
    showcase = icon(if (p > 0.5) "face-smile" else "face-frown")
  )
}

# ---- UI ------------------------------------------------------------------------

ui <- page_navbar(
  title = "Movie Review Sentiment",
  theme = bs_theme(bootswatch = "flatly"),
  fillable = FALSE,
  header = tagList(
    tags$head(
      tags$link(rel = "preconnect", href = "https://fonts.googleapis.com"),
      tags$link(rel = "preconnect", href = "https://fonts.gstatic.com", crossorigin = NA),
      tags$link(rel = "stylesheet",
                href = "https://fonts.googleapis.com/css2?family=Poppins:wght@400;500;600;700;800;900&family=Playfair+Display:ital,wght@0,600;1,600&display=swap")
    ),
    tags$style(HTML(".shiny-plot-output img{max-width:100%;height:auto!important}")),
    landing_ui(bundle)   # full-screen intro + topic carousel (R/landing.R)
  ),

  nav_panel(
    "Predict a review", icon = icon("pen"),
    layout_columns(
      col_widths = c(5, 7),
      card(
        card_header("Type or paste a movie review"),
        textAreaInput("review", NULL, value = examples$Positive, rows = 9, width = "100%",
                      placeholder = "Write a review here..."),
        div(class = "d-flex flex-wrap gap-2",
            span(class = "text-muted me-1", "Try an example:"),
            actionButton("ex_Positive", "Positive", class = "btn-sm btn-outline-success"),
            actionButton("ex_Negative", "Negative", class = "btn-sm btn-outline-danger"),
            actionButton("ex_Mixed",    "Mixed",    class = "btn-sm btn-outline-secondary"),
            actionButton("ex_Negation", "Negation", class = "btn-sm btn-outline-secondary")),
        p(class = "text-muted small mt-2",
          "The prediction updates automatically as you type.")
      ),
      div(
        uiOutput("review_boxes"),
        card(card_header("Your review, coloured by influence"),
             p(class = "small text-muted mb-1",
               HTML(sprintf('<span style="color:%s">&#9632;</span> pushes towards positive &nbsp; <span style="color:%s">&#9632;</span> pushes towards negative (hover a word for its weight)', col_pos, col_neg))),
             uiOutput("highlight"))
      )
    ),
    layout_columns(
      col_widths = c(7, 5),
      card(card_header("Why? The words and phrases that drove the prediction"),
           plotOutput("why_plot", height = "auto")),
      card(card_header("What is it about? LSA topic scores"),
           plotOutput("topic_plot", height = "auto"))
    ),
    card(card_header("Comparison with the sentiment lexicons"),
         tableOutput("lexicon_table"))
  ),

  nav_panel(
    "Predict a movie", icon = icon("film"),
    layout_sidebar(
      sidebar = sidebar(
        width = 340,
        radioButtons("movie_source", "Reviews to analyse",
                     c("A movie from the IMDb test set" = "dataset",
                       "Paste my own reviews" = "paste")),
        conditionalPanel(
          "input.movie_source == 'dataset'",
          selectizeInput("movie_id", "IMDb movie", choices = movie_choices),
          p(class = "small text-muted",
            "These movies were never seen during training. Their real labels are shown so you can check the prediction.")
        ),
        conditionalPanel(
          "input.movie_source == 'paste'",
          textAreaInput("movie_text", "Reviews (separate each review with a blank line)",
                        rows = 12,
                        value = paste(examples$Positive, examples$Mixed, examples$Negative,
                                      "Loved it! Great cast, great songs and a lovely ending for the whole family.",
                                      sep = "\n\n"))
        )
      ),
      uiOutput("movie_boxes"),
      layout_columns(
        col_widths = c(6, 6),
        card(card_header("How positive is each review?"), plotOutput("movie_dist", height = "auto")),
        card(card_header("What are viewers talking about?"), plotOutput("movie_topics", height = "auto"))
      ),
      card(card_header("The most typical public review"),
           p(class = "small text-muted",
             "The review closest to the average of all reviews of this movie - the most probable public review."),
           uiOutput("typical_review")),
      layout_columns(
        col_widths = c(6, 6),
        card(card_header("Most positive review"), uiOutput("best_review")),
        card(card_header("Most negative review"), uiOutput("worst_review"))
      )
    )
  ),

  nav_panel(
    "Model performance", icon = icon("chart-column"),
    uiOutput("perf_boxes"),
    layout_columns(
      col_widths = c(6, 6),
      card(card_header("Accuracy on 25,000 unseen test reviews"), plotOutput("acc_plot", height = "auto")),
      card(card_header("Predicted vs actual public opinion per movie"),
           plotOutput("movie_scatter", height = "auto"))
    ),
    layout_columns(
      col_widths = c(7, 5),
      card(card_header("Strongest words and phrases in the model"), plotOutput("coef_plot", height = "auto")),
      div(
        card(card_header("Confusion matrix (test set)"), tableOutput("confusion")),
        card(card_header("Topics: share of positive reviews (test set)"), tableOutput("topic_table"))
      )
    )
  ),

  nav_panel(
    "About", icon = icon("circle-info"),
    card(
      card_header("How this dashboard works"),
      markdown(sprintf("
**Data.** IMDb Large Movie Review Dataset (Maas et al., 2011): 50,000 labelled reviews.
The model is trained on the %s *train* reviews and evaluated on the %s *test* reviews,
which come from **different movies**, so every number here is on unseen data.

**Pipeline.**
1. **Clean** the text: remove HTML tags, numbers and punctuation; lowercase.
2. **Tokenize** into single words (stop words removed) and two-word phrases such as *not good*.
3. **tf-idf** weights over a vocabulary of %s terms; each review scaled to unit length.
4. **Sentiment model:** elastic-net logistic regression. Output = probability the review is positive.
5. **Topics:** the 10 LSA topics from the project report (SVD + varimax rotation).
6. **Lexicons:** AFINN, Bing and NRC scores for comparison.

**Explanations.** For a linear model, each term's contribution is exactly
*weight x tf-idf value*, so the coloured words and the *Why?* chart show precisely what drove the prediction.

**Movie prediction.** Every review of the movie is scored; the predicted public opinion is the share
of reviews predicted positive. The *most typical public review* is the one most similar to the
average of all the movie's reviews.

**Limits.** The model reads text only: it needs reviews to predict a movie's reception and cannot
forecast an unreleased film. Sarcasm and very mixed reviews remain hard.
", comma(bundle$n_train), comma(bundle$n_test), comma(length(bundle$vocab))))
    )
  ),
  nav_spacer(),
  nav_item(tags$a(href = "#", class = "nav-link", onclick = "window.showLanding(); return false;",
                  icon("house"), "Home")),
  nav_item(span(class = "navbar-text small", "IDS Project - LSA & Sentiment in R"))
)

# ---- server --------------------------------------------------------------------

server <- function(input, output, session) {

  for (nm in names(examples)) local({
    n <- nm
    observeEvent(input[[paste0("ex_", n)]], updateTextAreaInput(session, "review", value = examples[[n]]))
  })

  review_text <- debounce(reactive(input$review), 500)

  res <- reactive({
    txt <- review_text()
    validate(need(nchar(str_squish(txt)) >= 3, "Type a review to get a prediction."))
    analyse_review(txt)
  })

  output$review_boxes <- renderUI({
    r <- res()
    layout_columns(
      col_widths = c(5, 4, 3),
      prob_box(r$prob),
      value_box(title = "Main topic", value = tags$span(style = "font-size:1.3rem", r$topic),
                showcase = icon("tags"), theme = "light"),
      value_box(title = "Terms recognised", value = nrow(r$terms),
                showcase = icon("spell-check"), theme = "light")
    )
  })

  output$highlight <- renderUI({
    r <- res()
    div(style = "line-height:2; font-size:1.05rem;", highlight_html(review_text(), r$terms))
  })

  output$why_plot <- renderPlot({
    t <- res()$terms
    validate(need(nrow(t) > 0, "None of the words are in the model's vocabulary."))
    t |>
      slice_max(abs(contribution), n = 15) |>
      mutate(direction = if_else(contribution > 0, "towards positive", "towards negative")) |>
      ggplot(aes(contribution, reorder(term, contribution), fill = direction)) +
      geom_col() +
      geom_vline(xintercept = 0, colour = "grey40") +
      scale_fill_manual(values = c("towards positive" = col_pos, "towards negative" = col_neg)) +
      labs(x = "Contribution to the prediction", y = NULL, fill = NULL) +
      theme(legend.position = "top")
  }, width = 760, height = 380, res = 96)

  output$topic_plot <- renderPlot({
    s <- res()$topics
    tibble(topic = names(s), score = pmax(s, 0)) |>
      ggplot(aes(score, reorder(topic, score))) +
      geom_col(fill = "#30638e") +
      labs(x = "Topic score", y = NULL)
  }, width = 560, height = 380, res = 96)

  output$lexicon_table <- renderTable({
    r <- res()
    l <- r$lexicon
    lab <- function(s) if (s > 0) "positive" else "negative"
    tibble(
      Method = c("Logistic regression (this model)", "AFINN", "AFINN + negation", "Bing", "NRC"),
      Score  = c(paste(fmt_prob(r$prob), "positive"), l$afinn, l$afinn_negation, l$bing, l$nrc),
      Verdict = c(lab(r$prob - 0.5), lab(l$afinn), lab(l$afinn_negation), lab(l$bing), lab(l$nrc)),
      `Test-set accuracy` = percent(bundle$metrics$accuracy, accuracy = 0.1)
    )
  }, striped = TRUE, width = "100%")

  # ---- movie tab ----
  movie_data <- reactive({
    if (input$movie_source == "dataset") {
      req(input$movie_id)
      d <- bundle$movie_reviews |> filter(movie_id == input$movie_id)
      list(texts = d$review, prob = d$prob, topic = d$topic, actual = d$sentiment,
           movie_id = input$movie_id)
    } else {
      texts <- split_reviews(input$movie_text)
      validate(need(length(texts) > 0, "Paste at least one review."))
      x <- featurize(texts, bundle$vocab, bundle$idf)
      list(texts = texts, prob = predict_prob(x, model),
           topic = dominant_topic(topic_scores(texts, lsa)), actual = NULL, movie_id = NULL)
    }
  })

  output$movie_boxes <- renderUI({
    m <- movie_data()
    share <- mean(m$prob > 0.5)
    v <- as.character(verdict(share))
    boxes <- list(
      value_box(title = "Predicted public opinion", value = percent(share, accuracy = 1),
                p(paste(v, "- share of reviews predicted positive")),
                theme = value_box_theme(bg = if (share >= 0.5) col_pos else col_neg, fg = "white"),
                showcase = icon("users")),
      value_box(title = "Reviews analysed", value = length(m$texts),
                p(sprintf("Average probability positive: %.0f%%", 100 * mean(m$prob))),
                showcase = icon("comments"), theme = "light")
    )
    if (!is.null(m$actual)) {
      actual <- mean(m$actual == "positive")
      boxes[[3]] <- value_box(
        title = "Actual public opinion (labels)", value = percent(actual, accuracy = 1),
        p(sprintf("Prediction off by %d points", round(100 * abs(actual - share)))),
        p(tags$a(href = sprintf("https://www.imdb.com/title/%s/", m$movie_id), target = "_blank",
                 "Open this movie on IMDb")),
        showcase = icon("check-double"), theme = "light")
    }
    do.call(layout_columns, c(list(col_widths = if (length(boxes) == 3) c(4, 4, 4) else c(6, 6)), boxes))
  })

  output$movie_dist <- renderPlot({
    m <- movie_data()
    tibble(prob = m$prob,
           actual = if (is.null(m$actual)) "unknown" else m$actual) |>
      ggplot(aes(prob, fill = actual)) +
      geom_histogram(breaks = seq(0, 1, 0.1), colour = "white") +
      geom_vline(xintercept = 0.5, linetype = "dashed") +
      scale_fill_manual(values = c(positive = col_pos, negative = col_neg, unknown = "#30638e")) +
      scale_x_continuous(labels = percent) +
      labs(x = "Predicted probability positive", y = "Reviews",
           fill = if (is.null(m$actual)) NULL else "Actual label") +
      theme(legend.position = if (is.null(m$actual)) "none" else "top")
  }, width = 640, height = 320, res = 96)

  output$movie_topics <- renderPlot({
    m <- movie_data()
    tibble(topic = m$topic, positive = m$prob > 0.5) |>
      group_by(topic) |>
      summarise(reviews = n(), pct_positive = mean(positive)) |>
      ggplot(aes(reviews, reorder(topic, reviews), fill = pct_positive)) +
      geom_col() +
      scale_fill_gradient2(low = col_neg, mid = "grey80", high = col_pos, midpoint = 0.5,
                           limits = c(0, 1), labels = percent) +
      labs(x = "Reviews", y = NULL, fill = "Predicted\npositive")
  }, width = 640, height = 320, res = 96)

  review_card <- function(text, prob, topic) {
    tagList(
      p(tags$b(sprintf("%s  |  %.0f%% positive  |  %s", if (prob > 0.5) "Positive" else "Negative",
                       100 * prob, topic))),
      p(style = "white-space:pre-wrap;", str_trunc(str_squish(str_replace_all(text, "<[^>]+>", " ")), 900))
    )
  }

  output$typical_review <- renderUI({
    m <- movie_data()
    x <- featurize(m$texts, bundle$vocab, bundle$idf)
    centroid <- colMeans(x)
    sims <- as.numeric(x %*% centroid) / sqrt(sum(centroid^2))
    k <- which.max(sims)
    review_card(m$texts[k], m$prob[k], m$topic[k])
  })
  output$best_review <- renderUI({
    m <- movie_data(); k <- which.max(m$prob); review_card(m$texts[k], m$prob[k], m$topic[k])
  })
  output$worst_review <- renderUI({
    m <- movie_data(); k <- which.min(m$prob); review_card(m$texts[k], m$prob[k], m$topic[k])
  })

  # ---- performance tab ----
  output$perf_boxes <- renderUI({
    mv <- bundle$movies
    layout_columns(
      col_widths = c(3, 3, 3, 3),
      value_box("Test accuracy", percent(bundle$metrics$accuracy[1], accuracy = 0.1),
                p("on unseen reviews"), showcase = icon("bullseye"), theme = "primary"),
      value_box("Training reviews", comma(bundle$n_train), showcase = icon("graduation-cap"), theme = "light"),
      value_box("Test reviews", comma(bundle$n_test), showcase = icon("vial"), theme = "light"),
      value_box("Movie-level error", sprintf("%.1f pts",
                                             100 * mean(abs(mv$predicted_positive - mv$actual_positive))),
                p(sprintf("avg. over %d test movies", nrow(mv))),
                showcase = icon("film"), theme = "light")
    )
  })

  output$acc_plot <- renderPlot({
    bundle$metrics |>
      mutate(type = if_else(str_detect(method, "Logistic"), "Trained model", "Lexicon")) |>
      ggplot(aes(accuracy, reorder(method, accuracy), fill = type)) +
      geom_col(width = 0.65) +
      geom_text(aes(label = percent(accuracy, accuracy = 0.1)), hjust = -0.1) +
      geom_vline(xintercept = 0.5, linetype = "dashed", colour = "grey50") +
      scale_x_continuous(labels = percent, limits = c(0, 1.08)) +
      scale_fill_manual(values = c("Trained model" = "#30638e", Lexicon = "#edae49")) +
      labs(x = "Accuracy", y = NULL, fill = NULL) +
      theme(legend.position = "top")
  }, width = 640, height = 320, res = 96)

  output$movie_scatter <- renderPlot({
    bundle$movies |>
      ggplot(aes(actual_positive, predicted_positive, size = reviews)) +
      geom_abline(linetype = "dashed", colour = "grey50") +
      geom_point(alpha = 0.35, colour = "#30638e") +
      scale_x_continuous(labels = percent) + scale_y_continuous(labels = percent) +
      scale_size_area(max_size = 4) +
      labs(x = "Actual % positive reviews", y = "Predicted % positive", size = "Reviews")
  }, width = 640, height = 320, res = 96)

  output$coef_plot <- renderPlot({
    t <- bundle$top_terms
    bind_rows(slice_max(t, weight, n = 15), slice_min(t, weight, n = 15)) |>
      mutate(direction = if_else(weight > 0, "positive", "negative")) |>
      ggplot(aes(weight, reorder(term, weight), fill = direction)) +
      geom_col() +
      scale_fill_manual(values = c(positive = col_pos, negative = col_neg)) +
      labs(x = "Model weight", y = NULL, fill = NULL) +
      theme(legend.position = "top")
  }, width = 760, height = 520, res = 96)

  output$confusion <- renderTable({
    cm <- bundle$confusion
    tibble(` ` = paste("Predicted", rownames(cm)),
           `Actual negative` = comma(cm[, "negative"]),
           `Actual positive` = comma(cm[, "positive"]))
  }, width = "100%")

  output$topic_table <- renderTable({
    bundle$topic_summary |>
      transmute(Topic = topic, Reviews = comma(reviews),
                `Actual positive` = percent(actual_positive, accuracy = 1),
                `Predicted positive` = percent(predicted_positive, accuracy = 1))
  }, striped = TRUE, width = "100%")

  # Shiny 1.14's hidden-output tracking can miss bslib tab switches, leaving
  # outputs on the movie and performance tabs suspended ("recalculating")
  # forever. They are cheap to compute, so never suspend them.
  for (id in c("review_boxes", "highlight", "why_plot", "topic_plot", "lexicon_table",
               "movie_boxes", "movie_dist", "movie_topics", "typical_review",
               "best_review", "worst_review", "perf_boxes", "acc_plot",
               "movie_scatter", "coef_plot", "confusion", "topic_table")) {
    outputOptions(output, id, suspendWhenHidden = FALSE)
  }
}

shinyApp(ui, server)
