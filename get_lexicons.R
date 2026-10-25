# get_lexicons.R
# Downloads the AFINN and NRC sentiment lexicons once into lexicons/ using
# textdata's own download/process functions. textdata normally asks for
# confirmation interactively, which fails under Rscript, so this script calls
# the same steps directly.
#   AFINN  - Finn Arup Nielsen, Open Database License (ODbL) v1.0
#   NRC    - Saif Mohammad & Peter Turney; free for research / educational use
# Bing ships inside tidytext and needs no download.

library(textdata)

dir <- "lexicons"
for (name in c("afinn", "nrc")) {
  folder <- file.path(dir, name)
  target <- file.path(folder, paste0(name, ".rds"))
  if (file.exists(target)) next
  dir.create(folder, recursive = TRUE, showWarnings = FALSE)
  textdata:::download_functions[[name]](folder)
  textdata:::process_functions[[name]](folder, target)
  cat("Saved", target, "\n")
}

print(head(readRDS(file.path(dir, "afinn", "afinn.rds"))))
print(head(readRDS(file.path(dir, "nrc", "nrc.rds"))))
