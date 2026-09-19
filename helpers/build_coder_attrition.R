# build_coder_attrition.R — Coder turnover and threshold-shortfall series.
#
# Companion to build_workforce_series.R. That helper answers "how big is the active
# roster"; this one answers the two questions that turned out to matter more:
#
#   1. TURNOVER  — how many coders stop each year, as a rate on the standing pool.
#   2. SHORTFALL — what share of country-indicator cells fall below the thresholds
#                  V-Dem itself publishes.
#
# Why shortfall beats mean panel size. The V-Dem codebook names two thresholds:
#   "We strongly advise against using observations based on three or fewer coders."
#   "...we suggest that users primarily base analyses on observations based on five
#    or more coders."
# Those are V-Dem's own lines, so a share crossing them is directly interpretable in a
# way a mean is not. A mean panel of 6 can look healthy while the bottom of the
# distribution drops under 5 — the mean averages the tail away, and the tail is where
# the measurement model loses precision.
#
# On "departure". A coder's exit is inferred, not recorded: it is the last rating-year
# they ever produced. Because the archive is additive and contemporary recruits
# back-code to 2005, a coder present in year Y and absent from every later year has
# genuinely stopped contributing at the leading edge. (Arrivals are NOT recoverable
# this way — a new recruit enters at 2005 alongside the originals. See
# build_workforce_series.R, which recovers arrivals by comparing releases.)
#
# Sources
#   turnover   shared/vdem-data/V-Dem-Coder-Level-v15_rds/Coder-Level-Dataset-v15.rds
#   shortfall  shared/vdem-data/vdem-release-archive/vdem_<TAG>.RData (V10-V16)
#   NOTE these are different releases. The turnover series is v15; the shortfall
#   series defaults to V16. They are not one snapshot.
#
# Outputs (panel-member/data/derived/coder_attrition.rds), a list of:
#   turnover        coders whose last active year is Y, and the rate on the pool
#   shortfall_year  share of cells under each threshold, by year, in one release
#   shortfall_edge  the same share at each release's own leading edge, V10-V16
#   meta            thresholds, indicator set, release map, build time
#
# Usage:
#   Rscript helpers/build_coder_attrition.R
#   # or, to match an analysis that uses a restricted indicator set:
#   #   build_coder_attrition(root, indicators = working_indicators)

suppressPackageStartupMessages({ library(tidyverse) })

find_panel_member_root <- function() {
  up <- tryCatch(rprojroot::find_root(rprojroot::is_git_root), error = function(e) NA_character_)
  if (!is.na(up)) return(up)
  down <- file.path(getwd(), "panel-member")
  if (dir.exists(file.path(down, ".git"))) return(down)
  stop("Could not locate the panel-member project root from working dir: ", getwd())
}

THRESHOLDS <- c(advise_against = 3L, recommended_floor = 5L)
RELEASES   <- c(V10 = 2020, "V11.1" = 2021, V12 = 2022, V13 = 2023,
                V14 = 2024, V15 = 2025, V16 = 2026)
MIN_FILL   <- 0.50   # a year counts as covered if >=50% of its cells are populated

build_coder_attrition <- function(proj_root,
                                  shortfall_release = "V16",
                                  indicators   = NULL,      # NULL = every _nr column
                                  first_year   = 2005L,     # contemporary era only
                                  last_year    = 2024L,
                                  shared_dir   = file.path(dirname(proj_root), "shared", "vdem-data"),
                                  out_dir      = file.path(proj_root, "data", "derived"),
                                  write        = TRUE) {

  archive   <- file.path(shared_dir, "vdem-release-archive")
  coder_rds <- file.path(shared_dir, "V-Dem-Coder-Level-v15_rds", "Coder-Level-Dataset-v15.rds")

  load_release <- function(tag) {
    f <- file.path(archive, paste0("vdem_", tag, ".RData"))
    if (!file.exists(f)) stop("Missing release file: ", f)
    e <- new.env(); load(f, envir = e); e[[ls(e)[1]]]
  }

  # ── 1. Turnover ─────────────────────────────────────────────────────────────
  message("Loading v15 coder-level data for turnover...")
  cl <- read_rds(coder_rds) |>
    transmute(coder_id, year = as.integer(format(as.Date(historical_date), "%Y")))

  # Contemporary coders only. Dropping coders whose span ends around 1920 removes the
  # V-Dem Historical programme, which is a separate coding effort on a separate
  # timeline and would otherwise swamp the exit counts.
  spans <- cl |>
    group_by(coder_id) |>
    summarise(last_active = max(year), first_active = min(year), .groups = "drop") |>
    filter(last_active >= first_year)

  pool_size <- nrow(spans)

  turnover <- spans |>
    count(last_active, name = "coders_stopping") |>
    filter(last_active >= first_year, last_active <= last_year) |>
    mutate(
      # The final year is not an exit cohort: those coders are still active.
      still_active   = last_active == max(last_active),
      pool           = pool_size,
      pct_of_pool    = round(coders_stopping / pool_size * 100, 2)
    ) |>
    rename(year = last_active)

  # ── 2. Shortfall by year, within one release ────────────────────────────────
  message("Computing threshold shortfall by year (", shortfall_release, ")...")
  rel  <- load_release(shortfall_release)
  nrc  <- if (is.null(indicators)) grep("_nr$", names(rel), value = TRUE)
          else intersect(paste0(indicators, "_nr"), names(rel))

  cells_of <- function(z, cols, yrs) {
    z |>
      filter(year %in% yrs) |>
      select(country_text_id, year, all_of(cols)) |>
      pivot_longer(all_of(cols), names_to = "indicator", values_to = "n_coders") |>
      filter(!is.na(n_coders))
  }

  shortfall_of <- function(cells) {
    cells |>
      group_by(year) |>
      summarise(
        cells        = n(),
        mean_n       = mean(n_coders),
        median_n     = median(n_coders),
        pct_le_3     = mean(n_coders <= THRESHOLDS[["advise_against"]])    * 100,
        pct_lt_5     = mean(n_coders <  THRESHOLDS[["recommended_floor"]]) * 100,
        .groups      = "drop"
      ) |>
      mutate(across(c(mean_n, median_n, pct_le_3, pct_lt_5), ~round(.x, 3)))
  }

  shortfall_year <- shortfall_of(cells_of(rel, nrc, first_year:last_year)) |>
    mutate(release = shortfall_release, .before = 1)

  # ── 3. Shortfall at each release's own leading edge ─────────────────────────
  # A release is frozen at publication, so its most recent year has had no chance to
  # accumulate back-coders. Reading each release there gives a shortfall figure that is
  # comparable across releases rather than confounded with how long a year has had to
  # fill in. See build_workforce_series.R for the same identification argument.
  message("Computing shortfall at each release's leading edge...")
  rels <- set_names(map(names(RELEASES), load_release), names(RELEASES))
  inds <- reduce(map(rels, ~grep("_nr$", names(.x), value = TRUE)), intersect)
  if (!is.null(indicators)) inds <- intersect(paste0(indicators, "_nr"), inds)
  ctys <- reduce(map(rels, ~unique(.x$country_text_id)), intersect)

  edge_of <- function(z) {
    z |>
      filter(country_text_id %in% ctys) |>
      select(year, all_of(inds)) |>
      pivot_longer(all_of(inds), names_to = "i", values_to = "nr") |>
      group_by(year) |>
      summarise(fill = mean(!is.na(nr)), .groups = "drop") |>
      filter(fill >= MIN_FILL) |>
      pull(year) |> max()
  }

  shortfall_edge <- imap_dfr(rels, function(z, tag) {
    e <- edge_of(z)
    z |>
      filter(country_text_id %in% ctys, year == e) |>
      select(all_of(inds)) |>
      pivot_longer(everything(), names_to = "i", values_to = "n_coders") |>
      filter(!is.na(n_coders)) |>
      summarise(
        release   = tag,
        pub_year  = RELEASES[[tag]],
        edge_year = e,
        cells     = n(),
        mean_n    = round(mean(n_coders), 3),
        pct_le_3  = round(mean(n_coders <= THRESHOLDS[["advise_against"]])    * 100, 3),
        pct_lt_5  = round(mean(n_coders <  THRESHOLDS[["recommended_floor"]]) * 100, 3)
      )
  }) |> arrange(pub_year)

  out <- list(
    turnover       = turnover,
    shortfall_year = shortfall_year,
    shortfall_edge = shortfall_edge,
    meta = list(
      thresholds        = THRESHOLDS,
      releases          = RELEASES,
      shortfall_release = shortfall_release,
      n_indicators      = length(nrc),
      indicators        = sub("_nr$", "", nrc),
      contemporary_pool = pool_size,
      year_range        = c(first_year, last_year),
      built_at          = Sys.time()
    )
  )

  if (write) {
    dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
    f <- file.path(out_dir, "coder_attrition.rds")
    saveRDS(out, f)
    message("Wrote ", f)
  }
  out
}

if (sys.nframe() == 0) {
  res <- build_coder_attrition(find_panel_member_root())
  cat("\n=== Coder turnover (v15 coder-level; final row = still active) ===\n")
  print(as.data.frame(res$turnover |> filter(year >= 2013)), row.names = FALSE)
  cat("\nmedian annual exits 2014-2023: ",
      median(res$turnover$coders_stopping[res$turnover$year %in% 2014:2023]),
      " of a ", res$meta$contemporary_pool, "-coder pool\n", sep = "")
  cat("\n=== Threshold shortfall by year (", res$meta$shortfall_release, ") ===\n", sep = "")
  print(as.data.frame(res$shortfall_year |> filter(year %in% c(2005, 2010, 2015, 2019:2024))),
        row.names = FALSE)
  cat("\n=== Shortfall at each release's own leading edge ===\n")
  print(as.data.frame(res$shortfall_edge), row.names = FALSE)
}
