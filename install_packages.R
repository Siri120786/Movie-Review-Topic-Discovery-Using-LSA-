# install_packages.R - run once in a fresh R / RStudio installation
pkgs <- c("tidytext", "dplyr", "tidyr", "stringr", "readr", "forcats", "ggplot2",
          "scales", "irlba", "Matrix", "wordcloud", "RColorBrewer", "reshape2",
          "textdata", "caret", "glmnet", "lime", "rmarkdown", "knitr",
          "shiny", "bslib", "htmltools")
install.packages(setdiff(pkgs, rownames(installed.packages())))
