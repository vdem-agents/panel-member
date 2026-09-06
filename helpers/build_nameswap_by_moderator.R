# build_nameswap_by_moderator.R — direct effect of movement / prominence on name-swap tracking
# (does a country's staleness or prominence predict whether the model reads real evidence content
# over an injected fake country name?). Same simplification as build_slope_by_condition.R /
# build_signeddev_by_condition.R (2026-09-06): single model, no interaction term:
#
#   track ~ movement   (movement-only)
#   track ~ reid       (reid-only)
#
# Unlike those two figures, there's no de-identification ladder to cross here -- the name-swap
# test only ever ran on one text condition per weight-state (Summarized for Base, Summarized-
# zeroshot for Fine-Tuned; see helpers/build_priorreliance.R's Panel B, which reports the plain
# level of this same outcome). So this is Base vs Fine-Tuned only, three families, no condition
# dimension -- shape matches fig_nameswap_tracking's y=model / facet=block layout, not the
# condition-ladder layout of Figures 6-7.
#
# Movement uses the UNSIGNED, rank-tamed magnitude (same as build_slope_by_condition.R) -- there's
# no a priori direction theory for tracking the way there is for signed deviation's lag/anchoring
# story, so magnitude ("how stale is the model's picture of this country") is the natural test.
#
# Only "swapped" trial rows are used (source != named) -- the tracking metric is only informative
# there; "correct" trial rows (source == named) have track identically 0 by construction and would
# just dilute/attenuate the moderator's estimated slope with pure noise. (Panel B's own level
# estimate deliberately averages in the true-zero control rows -- reasonable for a *level*
# statistic, not appropriate for a slope regression like this one.)
#
# Usage:
#   Rscript helpers/build_nameswap_by_moderator.R --moderator movement
#   Rscript helpers/build_nameswap_by_moderator.R --moderator reid

suppressPackageStartupMessages({ library(tidyverse); library(glue); library(jsonlite) })

find_panel_member_root <- function() {
  up <- tryCatch(rprojroot::find_root(rprojroot::is_git_root), error = function(e) NA_character_)
  if (!is.na(up)) return(up)
  down <- file.path(getwd(), "panel-member")
  if (dir.exists(file.path(down, ".git"))) return(down)
  stop("Could not locate the panel-member project root from working dir: ", getwd())
}

model_families <- tribble(
  ~family,  ~model,       ~base_key,    ~ft_key,
  "llama",  "Llama 70B",  "llama-70b",  "llama-70b-ft-raw",
  "qwen",   "Qwen 72B",   "qwen-72b",   "qwen-72b-ft-raw",
  "gemma",  "Gemma 27B",  "gemma-27b",  "gemma-27b-ft-raw",
)
reid_base_prefix <- c(llama = "reid_base", qwen = "reid_qwen-base", gemma = "reid_gemma-base")

wls_coefs <- function(y, X, w) {
  XtW <- t(X * w)
  as.numeric(solve(XtW %*% X, XtW %*% y))
}

build_nameswap_by_moderator <- function(proj_root,
                                        moderator      = c("movement", "reid"),
                                        year           = 2023,
                                        reid_treatment = "summ",
                                        n_boot         = 2000,
                                        seed           = 42,
                                        out_dir        = file.path(proj_root, "data", "derived"),
                                        write          = TRUE) {
  moderator <- match.arg(moderator)
  source(file.path(proj_root, "helpers", "bootstrap_helpers.R"), local = TRUE)
  data_dir <- file.path(proj_root, "data", "processed")
  ns_dir   <- file.path(proj_root, "data", "output", "nameswap")
  reid_dir <- file.path(proj_root, "data", "output", "reid")

  panel_means <- read_csv(file.path(data_dir, "panel_means.csv"), show_col_types = FALSE)

  ns_files <- list.files(ns_dir, pattern = "^nameswap_swapped_.*\\.jsonl$", full.names = TRUE)
  if (length(ns_files) == 0) stop("No swapped nameswap files in ", ns_dir)
  ns <- ns_files |> map(function(f) {
    con <- file(f, "r"); on.exit(close(con))
    stream_in(con, verbose = FALSE) |> as_tibble() |>
      select(source, named, year, indicator, model_key, rating)
  }) |> bind_rows() |>
    mutate(model_key = str_remove(model_key, "-local$")) |>
    filter(year == !!year)

  track_for <- function(model_key) {
    filter(ns, model_key == !!model_key) |>
      inner_join(select(panel_means, source = country_text_id, year, indicator, source_mean = raw_mean),
                 by = c("source", "year", "indicator")) |>
      inner_join(select(panel_means, named = country_text_id, year, indicator, named_mean = raw_mean),
                 by = c("named", "year", "indicator")) |>
      transmute(country_text_id = source, indicator,
               track = abs(rating - named_mean) - abs(rating - source_mean)) |>
      filter(!is.na(track))
  }

  movement <- readRDS(file.path(proj_root, "data", "derived", glue("movement_{year}.rds")))$dpoly |>
    mutate(movement_value = rank(dpoly_abs, na.last = "keep") / sum(!is.na(dpoly_abs)))

  read_reid <- function(prefix) {
    f <- file.path(reid_dir, glue("{prefix}_{reid_treatment}_{year}.jsonl"))
    if (!file.exists(f)) stop("Missing reid file: ", f)
    con <- file(f, "r"); on.exit(close(con))
    d <- suppressWarnings(stream_in(con, verbose = FALSE)) |> as_tibble() |>
      select(iso, indicator, correct_top1)
    d |> mutate(.row = row_number()) |>
      group_by(iso, indicator) |> slice_max(.row, n = 1, with_ties = FALSE) |> ungroup() |>
      select(-.row)
  }

  fit_one <- function(model_key, family, block) {
    d <- track_for(model_key)

    if (moderator == "movement") {
      d <- d |> inner_join(select(movement, country_text_id, movement_value), by = "country_text_id")
      mod_col <- "movement_value"
    } else {
      reid <- read_reid(reid_base_prefix[[family]]) |>
        transmute(country_text_id = iso, indicator, reid = as.numeric(correct_top1))
      d <- d |> inner_join(reid, by = c("country_text_id", "indicator"))
      mod_col <- "reid"
    }
    d <- filter(d, !is.na(track), !is.na(.data[[mod_col]]))
    if (nrow(d) == 0) stop("fit_one(", model_key, "): no rows after join.")

    W <- country_boot_weights(d$country_text_id, n_boot, seed = seed)
    y <- d$track
    m <- d[[mod_col]]
    X <- cbind(1, m)

    B <- vapply(colnames(W), function(draw) {
      w <- unname(W[, draw][d$country_text_id])
      wls_coefs(y, X, w)
    }, numeric(2))
    app  <- which(colnames(W) == "Apparent")
    boot <- setdiff(seq_len(ncol(B)), app)
    tibble(est = B[2, app], lo = quantile(B[2, boot], 0.025), hi = quantile(B[2, boot], 0.975),
          n = nrow(d), block = block)
  }

  effects <- model_families |>
    pmap_dfr(function(family, model, base_key, ft_key) {
      bind_rows(
        fit_one(base_key, family, "Base")       |> mutate(model = model),
        fit_one(ft_key,   family, "Fine-Tuned") |> mutate(model = model)
      )
    }) |>
    mutate(block = factor(block, levels = c("Base", "Fine-Tuned")))

  bundle <- list(effects = effects, moderator = moderator, year = year,
                 reid_treatment = reid_treatment, n_boot = n_boot)

  if (write) {
    dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
    path <- file.path(out_dir, glue("nameswapbymoderator_{moderator}_{year}.rds"))
    saveRDS(bundle, path)
    message(glue("nameswap-by-moderator ({moderator}) bundle written: {path} · {nrow(effects)} rows"))
  }
  invisible(bundle)
}

# ── CLI ──────────────────────────────────────────────────────────────────────
parse_args <- function(a) {
  out <- list(moderator = "movement", year = 2023)
  i <- 1
  while (i <= length(a)) {
    switch(a[[i]],
      "--moderator" = { out$moderator <- a[[i + 1]]; i <- i + 2 },
      "--year"      = { out$year      <- as.integer(a[[i + 1]]); i <- i + 2 },
      stop("unknown arg: ", a[[i]]))
  }
  out
}

if (sys.nframe() == 0) {
  opt <- parse_args(commandArgs(trailingOnly = TRUE))
  proj_root <- find_panel_member_root()
  build_nameswap_by_moderator(proj_root, moderator = opt$moderator, year = opt$year)
}
