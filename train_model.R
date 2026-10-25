# train_model.R
# Trains the sentiment model used by the Shiny dashboard (app.R) and saves
# everything it needs to model/model_bundle.rds.
#
#   * Sentiment model : elastic-net logistic regression on tf-idf words + word pairs
#                       trained on Stanford's 25,000 TRAIN reviews,
#                       evaluated on the 25,000 TEST reviews (unseen movies)
#   * Topics          : the same 10 LSA topics as the report (movie_review_lsa.Rmd)
#   * Lexicons        : AFINN, Bing, NRC for side-by-side comparison
#
# Run once from the project folder (takes a few minutes):  Rscript train_model.R

source("R/features.R")
library(readr)
library(tidyr)
library(irlba)
library(glmnet)

dir.create("model", showWarnings = FALSE)
reviews <- read_csv("data/imdb_reviews.csv", show_col_types = FALSE)
log_step <- function(...) cat(format(Sys.time(), "%H:%M:%S"), "-", ..., "\n")

# ---- 1. LSA topics (identical sample and settings to the report) -------------
log_step("Building LSA topics")
set.seed(2026)
lsa_sample <- reviews |>
  group_by(sentiment) |>
  slice_sample(n = 5000) |>
  ungroup()

domain_stop <- c("movie", "movies", "film", "films", "br", "time", "watch",
                 "watching", "watched", "people", "lot", "makes", "bit", "thing")

lsa_counts <- tibble(doc = seq_len(nrow(lsa_sample)), text = clean_text(lsa_sample$review)) |>
  unnest_tokens(term, text) |>
  filter(!term %in% stop_words$word, str_length(term) > 2) |>
  count(doc, term)

lsa_df  <- lsa_counts |> count(term, name = "df")
lsa_idf <- with(lsa_df, setNames(log(n_distinct(lsa_counts$doc) / df), term))
lsa_vocab <- lsa_df |>
  filter(!term %in% domain_stop, df >= 20, df <= 0.30 * nrow(lsa_sample)) |>
  pull(term) |>
  sort()
lsa_idf <- lsa_idf[lsa_vocab]

lsa_dtm <- counts_to_matrix(lsa_counts, nrow(lsa_sample), lsa_vocab, lsa_idf)
svd50   <- irlba(lsa_dtm, nv = 50, nu = 50)
loadings <- unclass(varimax(svd50$v[, 1:10], normalize = FALSE)$loadings)
rownames(loadings) <- lsa_vocab
loadings <- sweep(loadings, 2, apply(loadings, 2, \(c) sign(c[which.max(abs(c))])), `*`)

# Name each topic by the anchor word it loads on most (the topic order out of
# the SVD can vary, the topics themselves do not)
anchors <- c("Horror & slashers" = "horror", "TV series & episodes" = "episode",
             "Comedy & humour" = "comedy", "Book adaptations" = "book",
             "War, history & documentaries" = "war", "Action & special effects" = "action",
             "Music, love & family viewing" = "music", "Bad acting & wasted money" = "worst",
             "Acting & performances" = "performance", "Family & thriller plots" = "guy")
labels <- character(10)
for (lab in names(anchors)) {
  free <- which(labels == "")
  labels[free[which.max(loadings[anchors[[lab]], free])]] <- lab
}
colnames(loadings) <- labels

for (lab in labels) {
  cat(sprintf("  %-30s %s\n", lab,
              paste(names(sort(loadings[, lab], decreasing = TRUE))[1:8], collapse = ", ")))
}
lsa <- list(vocab = lsa_vocab, idf = lsa_idf, loadings = loadings, labels = labels)

# ---- 2. Sentiment model -----------------------------------------------------
train <- filter(reviews, split == "train")
test  <- filter(reviews, split == "test")

log_step("Tokenizing", nrow(train), "training reviews (words + word pairs)")
train_counts <- tokenize_terms(train$review)
doc_freq <- train_counts |> count(term, name = "df")
vocab <- doc_freq |>
  filter(df <= 0.5 * nrow(train),
         (!str_detect(term, " ") & df >= 10) |
           (str_detect(term, " ") & df >= 15 & useful_bigram(term))) |>
  pull(term) |>
  sort()
idf <- with(filter(doc_freq, term %in% vocab), setNames(log(nrow(train) / df), term))[vocab]
log_step("Vocabulary:", sum(!str_detect(vocab, " ")), "words +",
         sum(str_detect(vocab, " ")), "word pairs")

x_train <- counts_to_matrix(train_counts, nrow(train), vocab, idf)
y_train <- factor(train$sentiment, levels = c("negative", "positive"))

log_step("Training elastic-net logistic regression (5-fold CV)")
set.seed(2026)
cv_fit <- cv.glmnet(x_train, y_train, family = "binomial", alpha = 0.5,
                    nfolds = 5, type.measure = "class")
coefs <- coef(cv_fit, s = "lambda.min")
model <- list(intercept = coefs[1, 1],
              beta      = setNames(as.numeric(coefs[-1, 1]), vocab),
              lambda    = cv_fit$lambda.min,
              cv_error  = min(cv_fit$cvm))
log_step("Kept", sum(model$beta != 0), "of", length(vocab), "terms; CV accuracy",
         round(1 - model$cv_error, 4))

# ---- 3. Evaluate on the 25,000 unseen test reviews ---------------------------
log_step("Scoring the test set")
x_test <- featurize(test$review, vocab, idf)
test <- test |>
  mutate(prob      = predict_prob(x_test, model),
         predicted = if_else(prob > 0.5, "positive", "negative"),
         topic     = dominant_topic(topic_scores(review, lsa)))

lexicons <- list(
  afinn = readRDS("lexicons/afinn/afinn.rds"),
  bing  = get_sentiments("bing"),
  nrc   = readRDS("lexicons/nrc/nrc.rds") |> filter(sentiment %in% c("positive", "negative"))
)
lex <- lexicon_scores(test$review, lexicons)

truth <- test$sentiment == "positive"
acc <- function(pred_pos) mean(pred_pos == truth)
metrics <- tibble(
  method   = c("Logistic regression (this model)", "AFINN", "AFINN + negation", "Bing", "NRC"),
  accuracy = c(acc(test$prob > 0.5), acc(lex$afinn > 0), acc(lex$afinn_negation > 0),
               acc(lex$bing > 0), acc(lex$nrc > 0))
)
confusion <- table(Predicted = test$predicted, Actual = test$sentiment)
print(metrics)
print(confusion)

# ---- 4. Summaries for the dashboard -------------------------------------------
topic_summary <- test |>
  group_by(topic) |>
  summarise(reviews = n(), actual_positive = mean(sentiment == "positive"),
            predicted_positive = mean(prob > 0.5), .groups = "drop") |>
  arrange(desc(actual_positive))

movies <- test |>
  group_by(movie_id) |>
  summarise(reviews = n(),
            actual_positive    = mean(sentiment == "positive"),
            predicted_positive = mean(prob > 0.5),
            mean_stars         = mean(rating), .groups = "drop") |>
  filter(reviews >= 10) |>
  arrange(desc(reviews))

movie_reviews <- test |>
  filter(movie_id %in% movies$movie_id) |>
  select(movie_id, review, sentiment, rating, prob, topic)

log_step("Movies with 10+ test reviews:", nrow(movies),
         "| mean abs error of predicted % positive:",
         round(mean(abs(movies$predicted_positive - movies$actual_positive)), 3))

top_terms <- tibble(term = vocab, weight = model$beta) |> filter(weight != 0)

bundle <- list(
  created       = Sys.time(),
  vocab         = vocab,
  idf           = idf,
  model         = model,
  lsa           = lsa,
  lexicons      = lexicons,
  metrics       = metrics,
  confusion     = confusion,
  topic_summary = topic_summary,
  movies        = movies,
  movie_reviews = movie_reviews,
  top_terms     = top_terms,
  n_train       = nrow(train),
  n_test        = nrow(test)
)
saveRDS(bundle, "model/model_bundle.rds")
log_step("Saved model/model_bundle.rds (",
         round(file.size("model/model_bundle.rds") / 1e6, 1), "MB )")
