# R/features.R
# Text features shared by train_model.R (training) and app.R (prediction), so a
# review typed into the dashboard is processed exactly like the training data.

library(dplyr)
library(stringr)
library(tidytext)
library(Matrix)

# Same cleaning as the report: drop HTML tags, numbers and punctuation; lowercase
clean_text <- function(x) {
  x |>
    str_replace_all("<[^>]+>", " ") |>
    str_to_lower() |>
    str_replace_all("[^a-z' ]", " ") |>
    str_replace_all("(^| )'+|'+( |$)", " ") |>
    str_squish()
}

negators <- c("not", "no", "never", "without", "nothing", "isn't", "wasn't",
              "aren't", "don't", "doesn't", "didn't", "can't", "couldn't",
              "won't", "wouldn't", "hardly", "nor", "neither")

# Single words plus two-word phrases, so the model can learn "not good",
# "waste time", "highly recommend" and so on. One row per (doc, term).
tokenize_terms <- function(texts) {
  d <- tibble(doc = seq_along(texts), text = clean_text(texts))
  unigrams <- d |>
    unnest_tokens(term, text, token = "words") |>
    filter(!term %in% stop_words$word, str_length(term) > 2)
  bigrams <- d |>
    unnest_tokens(term, text, token = "ngrams", n = 2) |>
    filter(!is.na(term))
  bind_rows(unigrams, bigrams) |> count(doc, term)
}

# Keep a bigram when at least one word carries meaning, or it starts with a negator
useful_bigram <- function(terms) {
  w <- str_split_fixed(terms, " ", 2)
  !(w[, 1] %in% stop_words$word & w[, 2] %in% stop_words$word) | w[, 1] %in% negators
}

# tf-idf matrix over a fixed vocabulary, each row scaled to unit length
counts_to_matrix <- function(counts, n_docs, vocab, idf) {
  counts <- counts |> filter(term %in% vocab)
  m <- sparseMatrix(i = counts$doc, j = match(counts$term, vocab),
                    x = counts$n * idf[counts$term],
                    dims = c(n_docs, length(vocab)),
                    dimnames = list(NULL, vocab))
  norms <- sqrt(rowSums(m^2))
  norms[norms == 0] <- 1
  as(Diagonal(x = 1 / norms) %*% m, "CsparseMatrix")
}

featurize <- function(texts, vocab, idf) {
  counts_to_matrix(tokenize_terms(texts), length(texts), vocab, idf)
}

# LSA topic features use single words only (as in the report)
featurize_lsa <- function(texts, lsa) {
  counts <- tibble(doc = seq_along(texts), text = clean_text(texts)) |>
    unnest_tokens(term, text) |>
    count(doc, term)
  counts_to_matrix(counts, length(texts), lsa$vocab, lsa$idf)
}

# ---- predictions -----------------------------------------------------------

predict_prob <- function(x, model) {
  eta <- as.numeric(x %*% model$beta) + model$intercept
  1 / (1 + exp(-eta))
}

# Exact per-term explanation for a linear model: contribution = weight x value
# x is a one-row feature matrix from featurize()
explain_terms <- function(x, model) {
  v  <- as.numeric(x[1, ])
  nz <- which(v != 0)
  tibble(term = colnames(x)[nz], value = v[nz], weight = as.numeric(model$beta[nz])) |>
    mutate(contribution = value * weight) |>
    filter(contribution != 0) |>
    arrange(desc(abs(contribution)))
}

topic_scores <- function(texts, lsa) {
  s <- as.matrix(featurize_lsa(texts, lsa) %*% lsa$loadings)
  colnames(s) <- lsa$labels
  s
}

dominant_topic <- function(scores) {
  best <- max.col(scores, ties.method = "first")
  out <- colnames(scores)[best]
  out[apply(scores, 1, max) <= 0.02] <- "No clear topic"
  out
}

lexicon_scores <- function(texts, lexicons) {
  words <- tibble(doc = seq_along(texts), text = clean_text(texts)) |>
    unnest_tokens(word, text) |>
    group_by(doc) |>
    mutate(prev1 = lag(word, 1), prev2 = lag(word, 2)) |>
    ungroup()
  afinn <- words |>
    inner_join(lexicons$afinn, by = "word") |>
    mutate(neg = coalesce(prev1 %in% negators | prev2 %in% negators, FALSE)) |>
    group_by(doc) |>
    summarise(afinn = sum(value), afinn_negation = sum(if_else(neg, -value, value)))
  bing <- words |>
    inner_join(lexicons$bing, by = "word", relationship = "many-to-many") |>
    group_by(doc) |>
    summarise(bing = sum(sentiment == "positive") - sum(sentiment == "negative"))
  nrc <- words |>
    inner_join(lexicons$nrc, by = "word", relationship = "many-to-many") |>
    group_by(doc) |>
    summarise(nrc = sum(sentiment == "positive") - sum(sentiment == "negative"))
  tibble(doc = seq_along(texts)) |>
    left_join(afinn, by = "doc") |>
    left_join(bing, by = "doc") |>
    left_join(nrc, by = "doc") |>
    mutate(across(-doc, \(x) coalesce(x, 0)))
}

verdict <- function(p) {
  cut(p, c(-Inf, 0.2, 0.4, 0.6, 0.8, Inf),
      labels = c("Overwhelmingly negative", "Mostly negative", "Mixed",
                 "Mostly positive", "Overwhelmingly positive"))
}
