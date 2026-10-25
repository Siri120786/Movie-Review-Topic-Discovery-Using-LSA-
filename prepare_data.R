# prepare_data.R
# Builds data/imdb_reviews.csv (50,000 rows: review, sentiment, split, rating,
# movie_id)
# from the official Stanford IMDb archive (Maas et al., 2011).
# Run once from the project folder:  Rscript prepare_data.R
#
# The reviews are streamed straight out of the .tar.gz instead of extracting
# 100,000 tiny files to disk, which is very slow on Windows.

library(readr)
library(dplyr)

archive <- "data/aclImdb_v1.tar.gz"
out_csv <- "data/imdb_reviews.csv"

if (!file.exists(archive)) {
  stop("Download aclImdb_v1.tar.gz from https://ai.stanford.edu/~amaas/data/sentiment/ into data/")
}

# Minimal tar reader: every entry is a 512-byte header followed by its data
# padded to a multiple of 512 bytes. Keeps only the labelled review files and
# the urls_*.txt files that link each review to its IMDb movie page.
read_labelled_reviews <- function(path) {
  con <- gzfile(path, "rb")
  on.exit(close(con))
  wanted  <- "^aclImdb/(train|test)/(pos|neg)/\\d+_\\d+\\.txt$"
  url_rx  <- "^aclImdb/(train|test)/urls_(pos|neg)\\.txt$"
  urls    <- list()
  out     <- vector("list", 50000)
  n       <- 0
  pending <- NULL    # long name from a GNU ././@LongLink entry

  repeat {
    header <- readBin(con, "raw", 512)
    if (length(header) < 512 || all(header == 0)) break
    field <- function(from, to) {
      b <- header[from:to]
      rawToChar(b[seq_len(max(0, match(as.raw(0), b, nomatch = length(b) + 1) - 1))])
    }
    name   <- field(1, 100)
    prefix <- field(346, 500)
    if (nzchar(prefix)) name <- paste0(prefix, "/", name)
    size   <- strtoi(trimws(field(125, 136)), 8L)
    type   <- rawToChar(header[157])
    data   <- if (size > 0) readBin(con, "raw", size) else raw(0)
    pad    <- (512 - size %% 512) %% 512
    if (pad > 0) readBin(con, "raw", pad)

    if (type == "L") { pending <- sub("\\x00.*$", "", rawToChar(data[data != 0])); next }
    if (!is.null(pending)) { name <- pending; pending <- NULL }

    if (grepl(wanted, name)) {
      n <- n + 1
      out[[n]] <- c(name, rawToChar(data))
    } else if (grepl(url_rx, name)) {
      urls[[name]] <- strsplit(rawToChar(data), "\n", fixed = TRUE)[[1]]
    }
  }
  m <- do.call(rbind, out[seq_len(n)])
  parts <- strsplit(m[, 1], "/", fixed = TRUE)
  split <- vapply(parts, `[`, "", 2)
  label <- vapply(parts, `[`, "", 3)
  file  <- vapply(parts, `[`, "", 4)
  # line i+1 of urls_<label>.txt is the IMDb page of review file i_<stars>.txt
  url <- mapply(function(s, l, f) urls[[sprintf("aclImdb/%s/urls_%s.txt", s, l)]][as.integer(sub("_.*", "", f)) + 1],
                split, label, file, USE.NAMES = FALSE)
  tibble(
    review    = enc2utf8(m[, 2]),
    sentiment = ifelse(label == "pos", "positive", "negative"),
    split     = split,
    # file names look like 123_8.txt -> the star rating is 8
    rating    = as.integer(sub(".*_(\\d+)\\.txt$", "\\1", file)),
    movie_id  = sub(".*/title/(tt\\d+)/.*", "\\1", url)
  )
}

reviews <- read_labelled_reviews(archive)

write_csv(reviews, out_csv)
cat("Wrote", nrow(reviews), "reviews to", out_csv, "\n")
print(count(reviews, split, sentiment))
