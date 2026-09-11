# build_priorreliance.R — Figure 4 (prior reliance): Panel A (Identity x Compression 2x2,
# base models) + Panel B (name-swap tracking, base + fine-tuned). See
# notes/mockups/prior-reliance-fig-concept.md for the full design rationale.
#
# Panel A — Identity x Compression 2x2, base models only, 2023, three families. Four cells per
# family: Evidence (full text + identified, the baseline), Anonymized (full text, de-identified),
# Summarized (compressed, de-identified), Summarized-Identified (compressed, identified -- the
# new condition). Same interaction-contrast logic as the existing 07/08 2x2 (Base/FT-raw x
# Codebook/Evidence), applied to this different crossing:
#   Compression = MAE(Summarized-Identified) - MAE(Evidence)   [identity held constant]
#   Identity    = MAE(Anonymized)             - MAE(Evidence)  [compression held constant]
#   Interaction = MAE(Summarized) - MAE(Anonymized) - MAE(Summarized-Identified) + MAE(Evidence)
# All four cells' per-draw means come from the SAME shared country-clustered bootstrap draws
# (seed 42) on the CYI pool common to all four conditions, so the derived effects are paired
# within-draw, not independent deltas.
#
# Panel B — plain tracking level, not a regression. Unlike the prominence-crossing
# nameswap_tracking outcome in build_prominence.R (which regresses tracking on prominence and
# movement), this is just the country-clustered bootstrap mean of the tracking metric itself, per
# model family x weight-state (Base / Fine-Tuned) -- 6 cells, no crossing. Reuses the same
# tracking formula (analysis/10-nameswap-2019.qmd's Metric 1):
#   track = |rating_sw - named_mean| - |rating_sw - source_mean|
# positive = the rating tracks the true source country's content over the injected fake name
# ("reads"); near-zero/negative = follows the fake name ("recites").
#
# Usage:
#   Rscript helpers/build_priorreliance.R --panel A
#   Rscript helpers/build_priorreliance.R --panel B

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

build_panelA_2x2 <- function(proj_root,
                             year    = 2023,
                             n_boot  = 2000,
                             seed    = 42,
                             out_dir = file.path(proj_root, "data", "derived"),
                             write   = TRUE) {
  source(file.path(proj_root, "helpers", "bootstrap_helpers.R"), local = TRUE)
  data_dir      <- file.path(proj_root, "data", "processed")
  runs_dir      <- file.path(proj_root, "data", "output", "runs", as.character(year))
  runs_flat_dir <- file.path(proj_root, "data", "output", "runs")

  panel_means <- read_csv(file.path(data_dir, "panel_means.csv"), show_col_types = FALSE)

  needed_cols <- c("country", "year", "indicator", "condition", "model_key", "rating")
  read_run <- function(f) {
    con <- file(f, "r"); on.exit(close(con))
    stream_in(con, verbose = FALSE) |> as_tibble() |> select(all_of(needed_cols))
  }
  main_files <- list.files(runs_dir, pattern = "\\.jsonl$", full.names = TRUE)
  # Summarized-Identified landed in the flat runs/ dir (no OUTPUT_DIR override on that job),
  # unlike the other three 2023 conditions -- see notes/proposed-mechanism-tests.md's
  # "archive-folder gotcha" note.
  si_files <- list.files(runs_flat_dir, pattern = "^summarized-identified.*\\.jsonl$", full.names = TRUE)
  if (length(main_files) == 0) stop("No .jsonl files in ", runs_dir)
  if (length(si_files) == 0) stop("No summarized-identified files in ", runs_flat_dir)

  ai_raw <- c(main_files, si_files) |> map(read_run) |> bind_rows() |>
    mutate(model_key = str_remove(model_key, "-local$"))

  ai <- ai_raw |> filter(year == !!year) |> rename(country_text_id = country) |>
    inner_join(select(panel_means, country_text_id, year, indicator, raw_mean),
               by = c("country_text_id", "year", "indicator")) |>
    mutate(err = abs(rating - raw_mean))

  fit_family <- function(model_key, model) {
    ev   <- filter(ai, model_key == !!model_key, condition == "evidence") |>
      select(country_text_id, indicator, Evidence = err)
    an   <- filter(ai, model_key == !!model_key, condition == "anonymized") |>
      select(country_text_id, indicator, Anonymized = err)
    su   <- filter(ai, model_key == !!model_key, condition == "summarized") |>
      select(country_text_id, indicator, Summarized = err)
    suid <- filter(ai, model_key == !!model_key, condition == "summarized-identified") |>
      select(country_text_id, indicator, SummarizedIdentified = err)

    wide <- ev |>
      inner_join(an,   by = c("country_text_id", "indicator")) |>
      inner_join(su,   by = c("country_text_id", "indicator")) |>
      inner_join(suid, by = c("country_text_id", "indicator"))
    if (nrow(wide) == 0) stop("fit_family(", model_key, "): no CYIs common to all four conditions.")

    W <- country_boot_weights(wide$country_text_id, n_boot, seed = seed)
    Ev <- wide$Evidence; An <- wide$Anonymized; Su <- wide$Summarized; SuID <- wide$SummarizedIdentified

    effect_of_draw <- function(draw) {
      w  <- unname(W[, draw][wide$country_text_id])
      sw <- sum(w)
      mEv <- sum(w * Ev) / sw; mAn <- sum(w * An) / sw
      mSu <- sum(w * Su) / sw; mSuID <- sum(w * SuID) / sw
      c(Compression = mSuID - mEv, Identity = mAn - mEv,
        Interaction = mSu - mAn - mSuID + mEv)
    }
    M <- vapply(colnames(W), effect_of_draw, numeric(3))
    rownames(M) <- c("Compression", "Identity", "Interaction")

    app  <- which(colnames(W) == "Apparent")
    boot <- setdiff(seq_len(ncol(M)), app)
    tibble(
      effect = rownames(M),
      est    = M[, app],
      lo     = apply(M[, boot, drop = FALSE], 1, quantile, 0.025),
      hi     = apply(M[, boot, drop = FALSE], 1, quantile, 0.975)
    ) |> mutate(model = model, n = nrow(wide))
  }

  effects <- model_families |>
    pmap_dfr(function(family, model, base_key, ft_key) fit_family(base_key, model)) |>
    mutate(effect = factor(effect, levels = c("Interaction", "Identity", "Compression")))

  bundle <- list(effects = effects, year = year, n_boot = n_boot)

  if (write) {
    dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
    path <- file.path(out_dir, glue("priorreliance_panelA_{year}.rds"))
    saveRDS(bundle, path)
    message(glue("panelA (2x2) bundle written: {path} · {nrow(effects)} rows"))
  }
  invisible(bundle)
}

build_panelB_tracking <- function(proj_root,
                                  year    = 2023,
                                  n_boot  = 2000,
                                  seed    = 42,
                                  out_dir = file.path(proj_root, "data", "derived"),
                                  write   = TRUE) {
  source(file.path(proj_root, "helpers", "bootstrap_helpers.R"), local = TRUE)
  data_dir <- file.path(proj_root, "data", "processed")
  ns_dir   <- file.path(proj_root, "data", "output", "nameswap")

  panel_means <- read_csv(file.path(data_dir, "panel_means.csv"), show_col_types = FALSE)

  # Swapped arm only. Correct-arm rows have source == named, so track is
  # identically 0 by construction and pooling them halves every estimate.
  ns_files <- list.files(ns_dir, pattern = "^nameswap_swapped_.*\\.jsonl$", full.names = TRUE)
  if (length(ns_files) == 0) stop("No .jsonl files in ", ns_dir)
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
      transmute(country_text_id = source,
               track = abs(rating - named_mean) - abs(rating - source_mean)) |>
      filter(!is.na(track))
  }

  fit_cell <- function(model_key, model, block) {
    d <- track_for(model_key)
    if (nrow(d) == 0) stop("build_panelB_tracking(", model_key, "): no rows after join.")

    W <- country_boot_weights(d$country_text_id, n_boot, seed = seed)
    est_of_draw <- vapply(colnames(W), function(draw) {
      w <- unname(W[, draw][d$country_text_id])
      sum(w * d$track) / sum(w)
    }, numeric(1))

    app  <- which(colnames(W) == "Apparent")
    boot <- setdiff(seq_len(length(est_of_draw)), app)
    tibble(model = model, block = block,
          est = est_of_draw[app],
          lo  = quantile(est_of_draw[boot], 0.025),
          hi  = quantile(est_of_draw[boot], 0.975),
          n   = nrow(d))
  }

  effects <- model_families |>
    pmap_dfr(function(family, model, base_key, ft_key) {
      bind_rows(
        fit_cell(base_key, model, "Base"),
        fit_cell(ft_key,   model, "Fine-Tuned")
      )
    }) |>
    mutate(block = factor(block, levels = c("Base", "Fine-Tuned")))

  bundle <- list(effects = effects, year = year, n_boot = n_boot)

  if (write) {
    dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
    path <- file.path(out_dir, glue("priorreliance_panelB_{year}.rds"))
    saveRDS(bundle, path)
    message(glue("panelB (tracking) bundle written: {path} · {nrow(effects)} rows"))
  }
  invisible(bundle)
}

# ── CLI ──────────────────────────────────────────────────────────────────────
parse_args <- function(a) {
  out <- list(panel = "B", year = 2023)
  i <- 1
  while (i <= length(a)) {
    switch(a[[i]],
      "--panel" = { out$panel <- a[[i + 1]]; i <- i + 2 },
      "--year"  = { out$year  <- as.integer(a[[i + 1]]); i <- i + 2 },
      stop("unknown arg: ", a[[i]]))
  }
  out
}

if (sys.nframe() == 0) {
  opt <- parse_args(commandArgs(trailingOnly = TRUE))
  proj_root <- find_panel_member_root()
  if (opt$panel == "B") {
    build_panelB_tracking(proj_root, year = opt$year)
  } else if (opt$panel == "A") {
    build_panelA_2x2(proj_root, year = opt$year)
  } else {
    stop("Unknown panel: ", opt$panel, " (want 'A' or 'B')")
  }
}
