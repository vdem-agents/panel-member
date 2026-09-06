# build_movement_module.R — per-(country, indicator) leave-one-out module movement (the granular,
# non-circular alternative to aggregate polyarchy movement; design settled 2026-09-06 — see
# notes/mockups/prominence-crossing-fig-concept.md for the full reasoning).
#
# Theory: an AI's prior about a country might be more granular than a holistic "how democratic is
# this country" impression (aggregate v2x_polyarchy) — it could know something specific about a
# country's press-freedom or minority-rights track record without that being reflected in a
# general democracy score move. Testing that means a movement measure at roughly the same
# thematic grain as the indicator being coded — but using the SAME indicator's own change is
# circular (see the conversation this note is drawn from): the naive persistence model's error
# on a case is definitionally equal to that case's own change, so "does AI error rise with this
# indicator's own change" can't distinguish genuine staleness from "big-change cases are
# mechanically harder for anyone." The fix is a *different* variable at a similar grain: for each
# indicator, take the OTHER indicators in its V-Dem codebook section/module (config/
# indicator_section_mapping.csv's `module` field — parsed directly from each indicator's own
# official V-Dem variable-name prefix, e.g. v2cl... -> "cl" "Civil liberties"; not this project's
# invention, and a different structure than V-Dem's formal index-aggregation tree), build a
# normalized composite EXCLUDING the target indicator, and measure how much that composite moved
# from the baseline year to the target year. No algebraic identity ties that to the target
# indicator's own error.
#
# Caveat carried into every consumer: module size varies (2 to 32 indicators in the current
# mapping). Indicators in tiny modules (Academic freedom (campus): 2, Sovereignty: 3, ...) barely
# escape the circularity this is meant to avoid, since leaving one out of a 2-3 indicator module
# leaves almost the same series behind. Not dropped here — left for the consuming figure/analysis
# to flag or exclude as it sees fit (`n_module` is carried in the output for exactly that filter).
#
# Indicators on very different scales (0-1, 0-4, 0-5, 0-98, 0-100 all appear in the mapping) are
# min-max normalized to [0,1] using each indicator's own documented `scale` range before being
# averaged into a module composite, so no single wide-range indicator dominates the average.
#
# Usage:
#   Rscript helpers/build_movement_module.R                        # 2023 vs. baseline 2018 (default)
#   Rscript helpers/build_movement_module.R --year 2023 --baseline-year 2018

suppressPackageStartupMessages({ library(tidyverse); library(glue) })

find_panel_member_root <- function() {
  up <- tryCatch(rprojroot::find_root(rprojroot::is_git_root), error = function(e) NA_character_)
  if (!is.na(up)) return(up)
  down <- file.path(getwd(), "panel-member")
  if (dir.exists(file.path(down, ".git"))) return(down)
  stop("Could not locate the panel-member project root from working dir: ", getwd())
}

parse_scale <- function(scale_str) {
  # "0–4" (en dash) -> (0, 4)
  parts <- str_split_fixed(scale_str, "–", 2)
  tibble(scale_min = as.numeric(parts[, 1]), scale_max = as.numeric(parts[, 2]))
}

build_movement_module_bundle <- function(proj_root,
                                         year          = 2023,
                                         baseline_year = 2018,
                                         out_dir       = file.path(proj_root, "data", "derived"),
                                         write         = TRUE) {
  data_dir   <- file.path(proj_root, "data", "processed")
  config_dir <- file.path(proj_root, "config")

  ind_map_raw <- read_csv(file.path(config_dir, "indicator_section_mapping.csv"),
                          show_col_types = FALSE) |>
    select(indicator, module, module_label, scale)
  ind_map <- bind_cols(ind_map_raw, parse_scale(ind_map_raw$scale))

  panel_means <- read_csv(file.path(data_dir, "panel_means.csv"), show_col_types = FALSE) |>
    filter(year %in% c(baseline_year, !!year)) |>
    select(country_text_id, year, indicator, raw_mean) |>
    inner_join(ind_map, by = "indicator") |>
    mutate(norm = (raw_mean - scale_min) / (scale_max - scale_min))

  # Module composite per country-year, and the sum/count needed to remove one indicator's own
  # contribution in closed form (avoids an O(indicators^2) per-country recomputation).
  mod_year <- panel_means |>
    group_by(country_text_id, year, module) |>
    summarise(sum_norm = sum(norm, na.rm = TRUE), n_present = sum(!is.na(norm)), .groups = "drop")

  # Leave-one-out composite for indicator i in module m, country c, year y:
  #   (sum_norm[c,m,y] - norm[c,i,y]) / (n_present[c,m,y] - present(i))
  # If indicator i's own value is missing for that country-year, removing it changes neither the
  # sum nor the count, so the LOO composite equals the full composite.
  loo <- panel_means |>
    left_join(mod_year, by = c("country_text_id", "year", "module")) |>
    mutate(
      has_own      = !is.na(norm),
      loo_sum      = sum_norm - coalesce(norm, 0),
      loo_n        = n_present - as.integer(has_own),
      loo_composite = if_else(loo_n > 0, loo_sum / loo_n, NA_real_)
    ) |>
    select(country_text_id, year, indicator, module, module_label, loo_composite,
           n_module = n_present)

  wide <- loo |>
    select(country_text_id, indicator, module, module_label, year, loo_composite, n_module) |>
    pivot_wider(names_from = year, values_from = c(loo_composite, n_module),
               names_glue = "{.value}_{year}")

  movement_module <- wide |>
    transmute(country_text_id, indicator, module, module_label,
             n_module = coalesce(.data[[glue("n_module_{year}")]],
                                 .data[[glue("n_module_{baseline_year}")]]),
             movement_value = abs(.data[[glue("loo_composite_{year}")]] -
                                  .data[[glue("loo_composite_{baseline_year}")]]))

  n_missing <- sum(is.na(movement_module$movement_value))
  bundle <- list(movement = movement_module, year = year, baseline_year = baseline_year)

  if (write) {
    dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
    path <- file.path(out_dir, glue("movement_module_{year}.rds"))
    saveRDS(bundle, path)
    message(glue("movement-module bundle written: {path} · {nrow(movement_module)} (country, indicator) rows · ",
                 "{n_missing} missing (no LOO composite at {baseline_year} or {year}) · ",
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
  build_movement_module_bundle(proj_root, year = opt$year, baseline_year = opt$baseline_year)
}
