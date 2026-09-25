# build_prominence.R — per-CYI prominence x movement mechanism regression (the prominence-
# crossing figures, notes/proposed-mechanism-tests.md Section 6; design settled 2026-09-06).
#
# For a given outcome Y, fits, per model family x weight-state (Base / Fine-Tuned):
#   Y_c ~ reid_c + movement_country + reid_c:movement_country
# via closed-form weighted least squares, country-clustered bootstrap (seed 42, matching every
# other bootstrap in this project) — reusing country_boot_weights() from bootstrap_helpers.R.
#
# `reid_c` is a fixed per-CYI prominence flag (`correct_top1`), taken from that family's
# BASE-model re-identification — a stable partition that does not shift between that family's
# Base and Fine-Tuned cells (matches the existing "fixed salience partition" convention this
# project already uses for R5/A8). 2026-09-06 decision: Summarized-text re-id is the primary
# prominence measure for the main text (harder to leak identity through compression, so a
# stricter test of genuine salience); Anonymized-text re-id is the appendix companion
# (`reid_treatment = "anon"`).
#
# `movement_country` is the country-level |v2x_polyarchy(year) - v2x_polyarchy(baseline_year)|
# (`dpoly_abs` from movement_{year}.rds, built with the 2018-2023 window) — broadcast to every
# CYI row for that country. The signed version (`dpoly_signed`) is available in the same bundle
# for outcomes where direction matters (signed deviation), but isn't used by this WLS by default —
# pass the outcome's own moderator column name via `movement_col` if a different outcome needs it.
#
# Outcomes (two implemented so far; difficulty-tracking slope and signed deviation from Section 6
# follow the same shape but reuse build_distmatch.R/build_signeddev.R's per-CYI computation):
#   evidence_gain     — err(Evidence) - err(Codebook) per CYI. Positive = evidence made this
#                       specific case WORSE (matches the paper's existing MAE(Ev)-MAE(Cb) sign).
#   nameswap_tracking — |rating_sw - named_mean| - |rating_sw - source_mean| per swapped-arm CYI
#                       (analysis/10-nameswap-2019.qmd's Metric 1). Positive = the rating tracks
#                       the true source country's content over the injected fake name ("reads");
#                       near-zero/negative = follows the fake name ("recites"). Prominence and
#                       movement are keyed on the SOURCE country (is the true content country
#                       identifiable/has it moved), not the fake named one.
#   difficulty_slope  — a genuinely different shape from the other two: this is a per-CYI
#                       regression of AI error `a` on case difficulty `h` (`fig-crossmodel-slope`'s own
#                       variables — human LOO error as the difficulty proxy, min_coders=2, same
#                       as the main text), not a single scalar outcome. Prominence/movement enter
#                       as slope-modifiers, not level-shifters:
#                         a ~ h + reid + movement + h:reid + h:movement + reid:movement + h:reid:movement
#                       The three reported rows are the slope-modifying terms — h:reid
#                       ("Re-identified": does prominence change how well AI error tracks
#                       difficulty), h:movement ("Movement"), h:reid:movement ("Interaction") —
#                       not the level terms, which aren't the question this figure asks.
#   signed_deviation  — rating - raw_mean per CYI, Evidence condition (the directional-bias measure;
#                       positive = AI rates the case more generously than the panel, negative =
#                       harsher). Paired with SIGNED movement (`movement_source =
#                       "polyarchy_signed"`, dpoly_signed — NOT the absolute version the other
#                       three outcomes use), since this is a lag/anchoring test, not a magnitude
#                       test: a NEGATIVE Movement coefficient means the AI's rating lags behind
#                       real change (still-generous on a country that backslid, i.e. negative
#                       movement paired with positive signed deviation; still-harsh on one that
#                       improved) — anchoring on a pre-baseline impression. Same 4-term shape as
#                       evidence_gain/nameswap_tracking (no slope interaction, unlike
#                       difficulty_slope). "rank" here is a SIGNED rank (sign(x) * percentile
#                       rank of |x|) to tame outlier leverage without destroying the direction
#                       the whole test depends on — a plain unsigned rank would be meaningless.
#
# Usage:
#   Rscript helpers/build_prominence.R --outcome evidence_gain
#   Rscript helpers/build_prominence.R --outcome nameswap_tracking --movement-transform rank
#   Rscript helpers/build_prominence.R --outcome difficulty_slope --movement-transform rank
#   Rscript helpers/build_prominence.R --outcome signed_deviation --movement-source polyarchy_signed --movement-transform rank
#   Rscript helpers/build_prominence.R --outcome evidence_gain --reid-treatment anon  # appendix

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

# Closed-form weighted least squares: y ~ X (X's first column should be the intercept).
wls_coefs <- function(y, X, w) {
  XtW <- t(X * w)
  as.numeric(solve(XtW %*% X, XtW %*% y))
}

build_prominence_bundle <- function(proj_root,
                                    outcome        = "evidence_gain",
                                    year           = 2023,
                                    reid_treatment = c("summ", "anon"),
                                    movement_source    = c("polyarchy", "module", "polyarchy_signed"),
                                    movement_transform = c("raw", "log", "rank"),
                                    n_boot         = 2000,
                                    seed           = 42,
                                    out_dir        = file.path(proj_root, "data", "derived"),
                                    write          = TRUE) {
  reid_treatment <- match.arg(reid_treatment)
  movement_source <- match.arg(movement_source)
  movement_transform <- match.arg(movement_transform)
  valid_outcomes <- c("evidence_gain", "nameswap_tracking", "difficulty_slope", "signed_deviation")
  if (!outcome %in% valid_outcomes) {
    stop("Unknown outcome: ", outcome, " (want one of: ", paste(valid_outcomes, collapse = ", "), ")")
  }
  is_slope <- outcome == "difficulty_slope"

  source(file.path(proj_root, "helpers", "bootstrap_helpers.R"), local = TRUE)
  data_dir <- file.path(proj_root, "data", "processed")
  reid_dir <- file.path(proj_root, "data", "output", "reid")
  panel_means <- read_csv(file.path(data_dir, "panel_means.csv"), show_col_types = FALSE)

  read_jsonl_dir <- function(dir, cols) {
    files <- list.files(dir, pattern = "\\.jsonl$", full.names = TRUE)
    if (length(files) == 0) stop("No .jsonl files in ", dir)
    files |> map(function(f) {
      con <- file(f, "r"); on.exit(close(con))
      stream_in(con, verbose = FALSE) |> as_tibble() |> select(all_of(cols))
    }) |> bind_rows() |> mutate(model_key = str_remove(model_key, "-local$"))
  }

  # outcome_df(model_key) -> tibble(country_text_id, indicator, outcome_value), one row per CYI,
  # for whichever outcome was requested. This is the only outcome-specific piece; everything
  # downstream (reid/movement join, WLS, bootstrap) is shared.
  if (outcome == "evidence_gain") {
    runs_dir <- file.path(proj_root, "data", "output", "runs", as.character(year))
    ai <- read_jsonl_dir(runs_dir, c("country", "year", "indicator", "condition", "model_key", "rating")) |>
      filter(year == !!year) |> rename(country_text_id = country) |>
      inner_join(select(panel_means, country_text_id, year, indicator, raw_mean),
                 by = c("country_text_id", "year", "indicator")) |>
      mutate(err = abs(rating - raw_mean))

    outcome_df <- function(model_key) {
      ev <- filter(ai, model_key == !!model_key, condition %in% c("evidence", "evidence-zeroshot")) |>
        select(country_text_id, indicator, err_ev = err)
      cb <- filter(ai, model_key == !!model_key, condition == "codebook") |>
        select(country_text_id, indicator, err_cb = err)
      inner_join(ev, cb, by = c("country_text_id", "indicator")) |>
        transmute(country_text_id, indicator, outcome_value = err_ev - err_cb)
    }
  } else if (outcome == "nameswap_tracking") {
    ns_dir <- file.path(proj_root, "data", "output", "nameswap")
    ns <- read_jsonl_dir(ns_dir, c("source", "named", "year", "indicator", "model_key", "rating")) |>
      # Swapped arm only: correct-arm rows (source == named) have track
      # identically 0 and would dilute the outcome toward zero.
      filter(source != named) |>
      filter(year == !!year)

    outcome_df <- function(model_key) {
      d <- filter(ns, model_key == !!model_key) |>
        inner_join(select(panel_means, source = country_text_id, year, indicator, source_mean = raw_mean),
                   by = c("source", "year", "indicator")) |>
        inner_join(select(panel_means, named = country_text_id, year, indicator, named_mean = raw_mean),
                   by = c("named", "year", "indicator"))
      d |> transmute(country_text_id = source, indicator,
                     outcome_value = abs(rating - named_mean) - abs(rating - source_mean))
    }
  } else if (outcome == "signed_deviation") {
    runs_dir <- file.path(proj_root, "data", "output", "runs", as.character(year))
    ai <- read_jsonl_dir(runs_dir, c("country", "year", "indicator", "condition", "model_key", "rating")) |>
      filter(year == !!year, condition %in% c("evidence", "evidence-zeroshot")) |>
      rename(country_text_id = country) |>
      inner_join(select(panel_means, country_text_id, year, indicator, raw_mean),
                 by = c("country_text_id", "year", "indicator"))

    outcome_df <- function(model_key) {
      filter(ai, model_key == !!model_key) |>
        transmute(country_text_id, indicator, outcome_value = rating - raw_mean)
    }
  } else {
    # difficulty_slope: same h_c (case difficulty) as analysis/09/build_distmatch.R's own
    # min_coders=2 pool, on the Evidence condition only (`fig-crossmodel-slope`'s featured input).
    min_coders <- 2L
    human_ratings <- read_csv(file.path(data_dir, "human_ratings.csv"), show_col_types = FALSE)
    human_h <- human_ratings |>
      filter(year == !!year) |>
      group_by(country_text_id, year, indicator) |>
      filter(n() >= min_coders) |>
      mutate(loo_mean = (sum(rating) - rating) / (n() - 1), e = abs(rating - loo_mean)) |>
      ungroup() |>
      group_by(country_text_id, year, indicator) |>
      summarise(h = mean(e), .groups = "drop")

    runs_dir <- file.path(proj_root, "data", "output", "runs", as.character(year))
    ai <- read_jsonl_dir(runs_dir, c("country", "year", "indicator", "condition", "model_key", "rating")) |>
      filter(year == !!year, condition %in% c("evidence", "evidence-zeroshot")) |>
      rename(country_text_id = country) |>
      inner_join(select(panel_means, country_text_id, year, indicator, raw_mean),
                 by = c("country_text_id", "year", "indicator")) |>
      inner_join(human_h, by = c("country_text_id", "year", "indicator")) |>
      mutate(a = abs(rating - raw_mean))

    outcome_df <- function(model_key) {
      filter(ai, model_key == !!model_key) |>
        transmute(country_text_id, indicator, h, outcome_value = a)
    }
  }

  # movement_source = "polyarchy": country-level |Δv2x_polyarchy|, broadcast to every CYI row for
  # that country (movement_{year}.rds). "module": per-(country, indicator) leave-one-out module
  # composite movement (movement_module_{year}.rds) — the granular, non-circular alternative; see
  # notes/mockups/prominence-crossing-fig-concept.md for why the same-indicator's own change
  # can't be used directly. join_keys tells fit_cell whether to join movement by country alone or
  # by (country, indicator).
  if (movement_source == "polyarchy") {
    movement <- readRDS(file.path(proj_root, "data", "derived", glue("movement_{year}.rds")))$dpoly
    # Tame the leverage of a handful of extreme-mover countries (Burkina Faso, Myanmar, ...) under
    # country-clustered resampling (2026-09-06 finding). "raw" keeps dpoly_abs as-is; "log" is
    # log1p() (found to barely help at this scale — max dpoly_abs is 0.46); "rank" is the
    # percentile rank (0-1), which tightened bootstrap CIs roughly 5-8x in testing.
    movement <- movement |>
      mutate(movement_value = switch(movement_transform,
        raw  = dpoly_abs,
        log  = log1p(dpoly_abs),
        rank = rank(dpoly_abs, na.last = "keep") / sum(!is.na(dpoly_abs))
      ))
    join_keys <- "country_text_id"
  } else if (movement_source == "polyarchy_signed") {
    movement <- readRDS(file.path(proj_root, "data", "derived", glue("movement_{year}.rds")))$dpoly
    # For signed_deviation only — direction carries the theory (lag/anchoring), so "rank" here is
    # a SIGNED rank (sign preserved, percentile taken on the magnitude) rather than the plain
    # unsigned rank the other outcomes use, which would destroy the direction entirely.
    movement <- movement |>
      mutate(movement_value = switch(movement_transform,
        raw  = dpoly_signed,
        log  = sign(dpoly_signed) * log1p(abs(dpoly_signed)),
        rank = sign(dpoly_signed) * rank(abs(dpoly_signed), na.last = "keep") / sum(!is.na(dpoly_signed))
      ))
    join_keys <- "country_text_id"
  } else {
    movement <- readRDS(file.path(proj_root, "data", "derived", glue("movement_module_{year}.rds")))$movement
    # Same transform menu, applied to the module-based measure (built already non-circular, so a
    # rank transform here is purely about resampling stability, not correctness).
    movement <- movement |>
      mutate(movement_value = switch(movement_transform,
        raw  = movement_value,
        log  = log1p(movement_value),
        rank = rank(movement_value, na.last = "keep") / sum(!is.na(movement_value))
      ))
    join_keys <- c("country_text_id", "indicator")
  }

  # Same de-duplication treatment as build_reidrates.R (keep the most recently written row per
  # (iso, indicator) pair) — a no-op on files that are already clean.
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

  fit_cell <- function(model_key, model, block, family) {
    d <- outcome_df(model_key)

    reid <- read_reid(reid_base_prefix[[family]]) |>
      transmute(country_text_id = iso, indicator, reid = as.numeric(correct_top1))

    d <- d |> inner_join(reid, by = c("country_text_id", "indicator")) |>
      inner_join(select(movement, all_of(join_keys), movement_value), by = join_keys) |>
      filter(!is.na(outcome_value), !is.na(reid), !is.na(movement_value))
    if (is_slope) d <- filter(d, !is.na(h))
    if (nrow(d) == 0) stop("fit_cell(", model_key, "): no rows survived the join — check keys.")

    W <- country_boot_weights(d$country_text_id, n_boot, seed = seed)
    y <- d$outcome_value
    if (is_slope) {
      # a ~ h + reid + movement + h:reid + h:movement + reid:movement + h:reid:movement.
      # Reported rows are the slope-modifying terms (cols 5, 6, 8); the level terms (2-4, 7)
      # aren't the question this figure asks and are dropped from the output.
      h <- d$h; r <- d$reid; m <- d$movement_value
      X <- cbind(1, h, r, m, h * r, h * m, r * m, h * r * m)
      row_idx <- c(`Re-identified` = 5, Movement = 6, Interaction = 8)
    } else {
      X <- cbind(1, d$reid, d$movement_value, d$reid * d$movement_value)
      row_idx <- c(`Re-identified` = 2, Movement = 3, Interaction = 4)
    }

    B <- vapply(colnames(W), function(draw) {
      w <- unname(W[, draw][d$country_text_id])
      wls_coefs(y, X, w)
    }, numeric(ncol(X)))

    app  <- which(colnames(W) == "Apparent")
    boot <- setdiff(seq_len(ncol(B)), app)
    tibble(
      term = factor(names(row_idx), levels = c("Interaction", "Movement", "Re-identified")),
      est  = B[row_idx, app],
      lo   = apply(B[row_idx, boot, drop = FALSE], 1, quantile, 0.025),
      hi   = apply(B[row_idx, boot, drop = FALSE], 1, quantile, 0.975)
    ) |>
      mutate(model = model, block = block, n = nrow(d))
  }

  effects <- model_families |>
    pmap_dfr(function(family, model, base_key, ft_key) {
      bind_rows(
        fit_cell(base_key, model, "Base",        family),
        fit_cell(ft_key,   model, "Fine-Tuned",  family)
      )
    }) |>
    mutate(block = factor(block, levels = c("Base", "Fine-Tuned")))

  bundle <- list(effects = effects, outcome = outcome, year = year,
                 reid_treatment = reid_treatment, movement_source = movement_source,
                 movement_transform = movement_transform, n_boot = n_boot)

  if (write) {
    dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
    path <- file.path(out_dir, glue(
      "prominence_{outcome}_{year}_{reid_treatment}_{movement_source}_{movement_transform}.rds"))
    saveRDS(bundle, path)
    message(glue("prominence bundle written: {path} · {nrow(effects)} rows"))
  }
  invisible(bundle)
}

# ── CLI ──────────────────────────────────────────────────────────────────────
parse_args <- function(a) {
  out <- list(outcome = "evidence_gain", year = 2023, reid_treatment = "summ",
             movement_source = "polyarchy", movement_transform = "raw")
  i <- 1
  while (i <= length(a)) {
    switch(a[[i]],
      "--outcome"            = { out$outcome            <- a[[i + 1]]; i <- i + 2 },
      "--year"               = { out$year               <- as.integer(a[[i + 1]]); i <- i + 2 },
      "--reid-treatment"     = { out$reid_treatment      <- a[[i + 1]]; i <- i + 2 },
      "--movement-source"    = { out$movement_source     <- a[[i + 1]]; i <- i + 2 },
      "--movement-transform" = { out$movement_transform  <- a[[i + 1]]; i <- i + 2 },
      stop("unknown arg: ", a[[i]]))
  }
  out
}

if (sys.nframe() == 0) {
  opt <- parse_args(commandArgs(trailingOnly = TRUE))
  proj_root <- find_panel_member_root()
  build_prominence_bundle(proj_root, outcome = opt$outcome, year = opt$year,
                          reid_treatment = opt$reid_treatment,
                          movement_source = opt$movement_source,
                          movement_transform = opt$movement_transform)
}
