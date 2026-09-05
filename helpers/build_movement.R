# build_movement.R — per-country |Δv2x_polyarchy| movement bundle (the "movement" ingredient for
# the prominence-crossing figures in notes/proposed-mechanism-tests.md, Section 6), without
# rendering analysis/09-regime-transition-2019.qmd.
#
# Lifts the continuous moderator out of QMD 09's `instruments` chunk. It's a fixed, year-over-year
# country-level covariate (year vs. year-1 v2x_polyarchy) — not a resampled quantity — so there is
# no bootstrap engine here; whatever interaction model consumes it downstream does its own
# country-clustered resampling. Continuous only: the binary ERT-episode flag was dropped (too few
# transition countries to be useful as a cut).
#
# Usage:
#   Rscript helpers/build_movement.R                 # 2019 (vs. 2018)
#   Rscript helpers/build_movement.R --year 2023      # 2023 (vs. 2022)

suppressPackageStartupMessages({ library(tidyverse); library(glue) })

find_panel_member_root <- function() {
  up <- tryCatch(rprojroot::find_root(rprojroot::is_git_root), error = function(e) NA_character_)
  if (!is.na(up)) return(up)
  down <- file.path(getwd(), "panel-member")
  if (dir.exists(file.path(down, ".git"))) return(down)
  stop("Could not locate the panel-member project root from working dir: ", getwd())
}

build_movement_bundle <- function(proj_root,
                                  year    = 2019,
                                  out_dir = file.path(proj_root, "data", "derived"),
                                  write   = TRUE) {
  data_dir <- file.path(proj_root, "data", "processed")
  ert <- read_csv(file.path(data_dir, "ert.csv"), show_col_types = FALSE) |>
    select(country_text_id, year, v2x_polyarchy)

  dpoly <- ert |>
    filter(year %in% c(!!year - 1L, !!year)) |>
    pivot_wider(names_from = year, values_from = v2x_polyarchy, names_prefix = "p") |>
    transmute(country_text_id,
              dpoly = abs(.data[[paste0("p", year)]] - .data[[paste0("p", year - 1L)]]))

  n_missing <- sum(is.na(dpoly$dpoly))
  bundle <- list(dpoly = dpoly, year = year, prior_year = year - 1L)

  if (write) {
    dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
    path <- file.path(out_dir, glue("movement_{year}.rds"))
    saveRDS(bundle, path)
    message(glue("movement bundle written: {path} · {nrow(dpoly)} countries · ",
                 "{n_missing} missing (no {year - 1} or {year} polyarchy)"))
  }
  invisible(bundle)
}

# ── CLI ──────────────────────────────────────────────────────────────────────
parse_args <- function(a) {
  out <- list(year = 2019)
  i <- 1
  while (i <= length(a)) {
    switch(a[[i]],
      "--year" = { out$year <- as.integer(a[[i + 1]]); i <- i + 2 },
      stop("unknown arg: ", a[[i]]))
  }
  out
}

if (sys.nframe() == 0) {
  opt <- parse_args(commandArgs(trailingOnly = TRUE))
  proj_root <- find_panel_member_root()
  build_movement_bundle(proj_root, year = opt$year)
}
