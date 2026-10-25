# deploy.R
# Publishes the Shiny dashboard to shinyapps.io.
#
# One-time setup (in the RStudio Console, never commit the token):
#   install.packages("rsconnect")
#   rsconnect::setAccountInfo(name = "...", token = "...", secret = "...")
#     (copy this line from shinyapps.io -> Account -> Tokens)
#
# Then, from the project folder:  source("deploy.R")
# Needs model/model_bundle.rds, created by train_model.R.

library(rsconnect)

stopifnot(file.exists("model/model_bundle.rds"))

deployApp(
  appDir   = ".",
  # only what the running app needs - not the 146 MB data/ folder or the report
  appFiles = c("app.R",
               "R/features.R", "R/landing.R",
               "www/landing.css", "www/landing.js",
               "model/model_bundle.rds"),
  appName  = "movie-review-sentiment",
  appTitle = "Movie Review Sentiment (LSA)",
  forceUpdate    = TRUE,
  launch.browser = FALSE
)
