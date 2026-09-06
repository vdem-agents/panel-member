# build_movement.R — per-country Δv2x_polyarchy movement bundle (the "movement" ingredient for
# the prominence-crossing figures in notes/proposed-mechanism-tests.md, Section 6).
#
# Redefined 2026-09-06 for the prominence-crossing use case. The original version (matching
# analysis/09-regime-transition-2019.qmd's `instruments` chunk exactly) measured a one-year lag —
# year vs. year-1 — which answers "did this country change right before the coding year" (does
# the source evidence reflect a recent shock). That's a different question from "how stale is the
# model's prior by the holdout year": a country that jumped in 2019-2021 and held steady in
# 2022-2023 would show zero movement under the one-year definition, despite a 2018-vintage prior
# about it being very wrong by 2023. This version instead measures cumulative drift from a fixed
# baseline year (2018, the year before this project's original 2019 panel/fine-tuning vintage) out
# to the target year — |v2x_polyarchy(year) - v2x_polyarchy(baseline)| — so a country's movement
# score reflects everything that changed since roughly when the model's "prior" would have been
# anchored, not just the most recent year's wiggle. No longer matches QMD 09's own `dpoly` (that
# was a deliberate, different measure for a deliberate, different question there).
#
# Both the absolute and signed versions are kept (2026-09-06 decision, from the discussion around
# prior-reliance/prominence-crossing): the three outcomes using "does staleness break the
# mechanism regardless of direction" (name-swap tracking, evidence-gain, difficulty-tracking
# slope) use dpoly_abs; the signed-deviation outcome, whose own value is directional, pairs with
# dpoly_signed to test lag/anchoring specifically (does the AI's rating still reflect the
# pre-baseline level when the country has since moved).
#
# Fixed, non-resampled country-level covariates — not a resampled quantity — so there is no
# bootstrap engine here; whatever interaction model consumes this downstream does its own
# country-clustered resampling. Continuous only: the binary ERT-episode flag was dropped (too few
# transition countries to be useful as a cut).
#
# Usage:
#   Rscript helpers/build_movement.R                        # 2023 vs. baseline 2018 (default)
#   Rscript helpers/build_movement.R --year 2023 --baseline-year 2018

suppressPackageStartupMessages({ library(tidyverse); library(glue) })

find_panel_member_root <- function() {
  up <- tryCatch(rprojroot::find_root(rprojroot::is_git_root), error = function(e) NA_character_)
  if (!is.na(up)) return(up)
  down <- file.path(getwd(), "panel-member")
  if (dir.exists(file.path(down, ".git"))) return(down)
  stop("Could not locate the panel-member project root from working dir: ", getwd())
}

build_movement_bundle <- function(proj_root,
                                  year         = 2023,
                                  baseline_year = 2018,
                                  out_dir      = file.path(proj_root, "data", "derived"),
                                  write        = TRUE) {
  data_dir <- file.path(proj_root, "data", "processed")
  ert <- read_csv(file.path(data_dir, "ert.csv"), show_col_types = FALSE) |>
    select(country_text_id, year, v2x_polyarchy)

  dpoly <- ert |>
    filter(year %in% c(!!baseline_year, !!year)) |>
    pivot_wider(names_from = year, values_from = v2x_polyarchy, names_prefix = "p") |>
    transmute(country_text_id,
              dpoly_signed = .data[[paste0("p", year)]] - .data[[paste0("p", baseline_year)]],
              dpoly_abs    = abs(dpoly_signed))

  n_missing <- sum(is.na(dpoly$dpoly_abs))
  bundle <- list(dpoly = dpoly, year = year, baseline_year = baseline_year)

  if (write) {
    dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
    path <- file.path(out_dir, glue("movement_{year}.rds"))
    saveRDS(bundle, path)
    message(glue("movement bundle written: {path} · {nrow(dpoly)} countries · ",
                 "{n_missing} missing (no {baseline_year} or {year} polyarchy) · ",
                 "window {baseline_year}→{year}"))
  }
  invisible(bundle)
}

# ── CLI ──────────────────────────────────────────────────────────────────────
parse_args <- function(a) {
  out <- list(year = 2023, baseline_year = 2018)
  i <- 1
  while (i <= length(a)) {
    switch(a[[i]],
      "--year"          = { out$year          <- as.integer(a[[i + 1]]); i <- i + 2 },
      "--baseline-year" = { out$baseline_year <- as.integer(a[[i + 1]]); i <- i + 2 },
      stop("unknown arg: ", a[[i]]))
  }
  out
}

if (sys.nframe() == 0) {
  opt <- parse_args(commandArgs(trailingOnly = TRUE))
  proj_root <- find_panel_member_root()
  build_movement_bundle(proj_root, year = opt$year, baseline_year = opt$baseline_year)
}
