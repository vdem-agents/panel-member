# build_panelsize.R — the paper's two motivating figures, as one bundle.
#
# Figures 1 and 2 of the manuscript are descriptive: they establish that V-Dem cells
# are thin where the paper proposes to help, and that thinness has a measurable price
# in V-Dem's own uncertainty units. Both were developed in the analysis notebooks and
# are ported here so the paper reads a frozen bundle like every other figure.
#
#   Figure 1  "how thin, and when"   <- analysis/14-coder-workforce-cross-release.qmd
#             A. panel-size distribution across V-Dem's five eras
#             B. share of cells below five at first publication vs. as V16 reports it
#
#   Figure 2  "what a coder buys"    <- analysis/01-panel-degradation-pathologies.qmd
#             A. posterior SD at each panel size
#             B. change in posterior SD contributed by each added coder
#
# Two notes on what these are NOT.
#
# 1. Figure 1B is not an attrition series. V-Dem's `year` is the year being RATED, not
#    the year a rating was produced, and contemporary recruits back-code to 2005. So a
#    single release always slopes downward toward recent years whether or not the
#    workforce changed. Panel B reads each year at first publication (no back-coding
#    possible yet) and again in the current release, which separates "arrived thin" from
#    "shrank". The leading-edge series is roughly FLAT -- every year arrives about
#    equally thin -- so the decline in a within-release profile is fill-in that has not
#    happened yet, not coders leaving. build_workforce_series.R carries the full
#    identification argument.
#
# 2. Figure 2's left end is selected, not just noisy. Contemporary cells with 1-4 coders
#    are disproportionately leading-edge years and hard-to-recruit countries. The fixed
#    effects absorb country, indicator and year MAIN effects but not their interaction,
#    and "this country in this year lost a coder" is exactly an interaction. The n=4
#    estimate in particular sits where N jumps from 3,038 to 19,463; treat the 3-4-5
#    wobble as composition rather than dose-response.
#
# Estimation (Figure 2). Panel-size dummies in one regression, so the levels and the
# marginals come from a single fit and a single country-clustered vcov:
#
#   posterior_sd ~ i(nrf, ref = "5") | indicator + country_text_id + year
#
# The marginal series is a difference of adjacent coefficients, so its SE needs the
# covariance between them -- V[a,a] + V[b,b] - 2*V[a,b], not a sum of squares. Adjacent
# coefficients here correlate ~0.76, so dropping the covariance term inflates the SE by
# ~1.6x on average and close to 2x above six coders. `mv_marginal()` does it properly.
# The raw (no fixed effects) series is carried alongside for the appendix and because
# the two together show how much of the level curve is composition.
#
# Sources
#   vdemdata::vdem (v16)                         _nr and _sd columns, 205 scored indicators
#   data/derived/analysis_indicators.rds         the scored set  (build_analysis_indicators.R)
#   data/derived/coder_attrition.rds             fill-in trajectory (build_coder_attrition.R)
#
# Outputs (panel-member/data/derived/panelsize.rds), a list of:
#   era          share of cells in each panel-size band, by era, + share below five
#   pairs        share below five at first publication vs. current release, by year
#   settled_ref  the share below five in fully settled years, as one number
#   mv_levels    posterior SD at each panel size, raw and adjusted
#   mv_marginal  change in posterior SD per added coder, raw and adjusted
#   mv_n         cells at each panel size
#   meta         thresholds, windows, indicator set, build time
#
# Usage:
#   Rscript helpers/build_panelsize.R

suppressPackageStartupMessages({
  library(tidyverse)
  library(fixest)
  library(vdemdata)
})

find_panel_member_root <- function() {
  up <- tryCatch(rprojroot::find_root(rprojroot::is_git_root), error = function(e) NA_character_)
  if (!is.na(up)) return(up)
  down <- file.path(getwd(), "panel-member")
  if (dir.exists(file.path(down, ".git"))) return(down)
  stop("Could not locate the panel-member project root from working dir: ", getwd())
}

# V-Dem's own published lines (v15 codebook p. 35). The <=3 warning has a stated (though
# unpublished) empirical basis; the floor of five is a RECRUITMENT QUOTA the methodology
# describes as a staffing target (p. 13, p. 16) and the codebook calls an assumption.
# Neither was derived from posterior SD, so Figure 2 is a check on them, not a restatement.
THRESHOLDS  <- c(advise_against = 3L, recommended_floor = 5L)

ERA_CUTS    <- c(-Inf, 1899, 1944, 1989, 2004, Inf)
ERA_LABELS  <- c("19th c.\n1789–1899", "Pre-war\n1900–44", "Cold War\n1945–89",
                 "Post-Cold War\n1990–2004", "Contemporary\n2005–2025")
BAND_CUTS   <- c(0, 1, 2, 3, 4, 8, Inf)
BAND_LABELS <- c("1", "2", "3", "4", "5–8", "9+")

NRMAX       <- 15L    # panel sizes above this are too sparse to estimate separately
MV_FROM     <- 2005L  # contemporary panel only -- see note below
MV_TO       <- 2024L

build_panelsize <- function(proj_root,
                            indicators = NULL,
                            out_dir    = file.path(proj_root, "data", "derived"),
                            write      = TRUE) {

  if (is.null(indicators)) {
    ai_path <- file.path(out_dir, "analysis_indicators.rds")
    if (!file.exists(ai_path))
      stop("analysis_indicators.rds not found; run helpers/build_analysis_indicators.R first")
    indicators <- readRDS(ai_path)$with_nr
    message("Using the paper's scored set: ", length(indicators), " indicators")
  }

  # ── 1. Figure 1A: the distribution across eras ──────────────────────────────
  # No year filter: the point of this panel is that the contemporary era is the good
  # one by V-Dem's own standard, which only reads if the rest of the history is shown.
  message("Building era distribution...")
  era_dat <- vdemdata::vdem |>
    select(country_text_id, year, any_of(paste0(indicators, "_nr"))) |>
    pivot_longer(-c(country_text_id, year), names_to = "indicator", values_to = "n_coders") |>
    filter(!is.na(n_coders)) |>
    mutate(era  = cut(year, ERA_CUTS, labels = ERA_LABELS),
           band = cut(n_coders, BAND_CUTS, labels = BAND_LABELS))

  era <- era_dat |>
    count(era, band) |>
    group_by(era) |>
    mutate(prop = n / sum(n)) |>
    ungroup() |>
    left_join(
      era_dat |>
        group_by(era) |>
        summarise(cells = n(), pct_lt5 = mean(n_coders < THRESHOLDS[["recommended_floor"]]) * 100,
                  .groups = "drop"),
      by = "era"
    )

  # The 19th-century column rests on a narrower indicator set -- most series do not reach
  # back that far -- so record how many indicators actually carry pre-1900 data.
  n_ind_pre1900 <- n_distinct(era_dat$indicator[era_dat$year < 1900])

  # ── 2. Figure 1B: the same year, before and after back-coding ───────────────
  # Read from build_coder_attrition.R rather than recomputed: the trajectory needs all
  # seven archived releases, and duplicating that load here would be both slow and a
  # second place for the release map to drift.
  message("Reading fill-in trajectory...")
  attr_path <- file.path(out_dir, "coder_attrition.rds")
  if (!file.exists(attr_path))
    stop("coder_attrition.rds not found; run helpers/build_coder_attrition.R first")
  attr_dat <- readRDS(attr_path)

  # cycle 0 = as first published; max(cycle) = as the current release reports it. The most
  # recent year has only cycle 0, so its two bars are equal -- a year that has had no
  # opportunity to fill, which is the correct reading and not a plotting artifact.
  pairs <- attr_dat$trajectory |>
    group_by(cohort_year) |>
    summarise(`At first publication` = pct_lt_5[cycle == 0],
              `As V16 reports it`    = pct_lt_5[cycle == max(cycle)],
              cycles = max(cycle), .groups = "drop") |>
    pivot_longer(c(`At first publication`, `As V16 reports it`),
                 names_to = "when", values_to = "pct") |>
    mutate(when = factor(when, levels = c("At first publication", "As V16 reports it")))

  # ── 3. Figure 2: posterior SD against panel size ────────────────────────────
  message("Building posterior-SD series...")
  unc_long <- vdemdata::vdem |>
    select(country_text_id, year,
           any_of(c(paste0(indicators, "_nr"), paste0(indicators, "_sd")))) |>
    filter(year >= 1990, year <= MV_TO) |>
    pivot_longer(cols = -c(country_text_id, year),
                 names_to = c("indicator", ".value"),
                 names_pattern = "^(.+)_(nr|sd)$") |>
    rename(n_coders = nr, posterior_sd = sd) |>
    filter(!is.na(n_coders), !is.na(posterior_sd), n_coders >= 1,
           indicator %in% indicators)

  # Restricted to 2005 onward. Before 2005 the contemporary panel does not operate: those
  # country-years are covered by the retrospective historical programme, where one or two
  # specialists coded a country's whole political history at once. Pooling the two puts
  # ~80% of all 1-3 coder cells into the left end of the figure, where they would read as
  # solid anchors while actually describing a different coding process.
  mv_dat <- unc_long |>
    filter(year >= MV_FROM, n_coders >= 1, n_coders <= NRMAX) |>
    mutate(nrf = factor(n_coders))

  mv_raw_fit <- feols(posterior_sd ~ 0 + nrf, data = mv_dat, cluster = ~country_text_id)
  mv_adj_fit <- feols(posterior_sd ~ i(nrf, ref = "5") | indicator + country_text_id + year,
                      data = mv_dat, cluster = ~country_text_id)

  # The raw fit gives group means directly; the adjusted fit gives contrasts against
  # n = 5, re-anchored onto the raw mean at n = 5 so both series sit on one scale.
  mv_anchor <- unname(coef(mv_raw_fit)[["nrf5"]])

  mv_raw_lvl <- tibble(
    n_coders = as.integer(sub("^nrf", "", names(coef(mv_raw_fit)))),
    est      = unname(coef(mv_raw_fit)),
    se       = unname(sqrt(diag(vcov(mv_raw_fit))))
  ) |> arrange(n_coders)

  mv_adj_cf <- coef(mv_adj_fit)
  mv_adj_V  <- vcov(mv_adj_fit)
  mv_adj_lv <- as.integer(sub(".*::", "", names(mv_adj_cf)))
  mv_adj_lvl <- tibble(n_coders = c(mv_adj_lv, 5L),
                       est = c(unname(mv_adj_cf) + mv_anchor, mv_anchor),
                       se  = c(unname(sqrt(diag(mv_adj_V))), 0)) |>
    arrange(n_coders)

  # Marginal change per added coder. A difference of two coefficients, so the variance
  # carries a covariance term: Var(b_k - b_{k-1}) = V[k,k] + V[k-1,k-1] - 2*V[k,k-1].
  # The reference category (n = 5 in the adjusted fit) is fixed at zero with no variance,
  # which is why `gk()` returns NULL for it rather than an index.
  mv_marginal <- function(cf, V, levels_vec, ref = NA_integer_) {
    idx <- setNames(seq_along(cf), levels_vec)
    bind_rows(lapply(2:NRMAX, function(k) {
      gk <- function(j) if (!is.na(ref) && j == ref) NULL else idx[[as.character(j)]]
      a <- gk(k); b <- gk(k - 1)
      d <- (if (is.null(a)) 0 else cf[a]) - (if (is.null(b)) 0 else cf[b])
      v <- (if (is.null(a)) 0 else V[a, a]) + (if (is.null(b)) 0 else V[b, b]) -
           2 * (if (is.null(a) || is.null(b)) 0 else V[a, b])
      tibble(n_coders = k, d = unname(d), se = sqrt(max(v, 0)))
    }))
  }

  mv_marg_raw <- mv_marginal(coef(mv_raw_fit), vcov(mv_raw_fit),
                             as.integer(sub("^nrf", "", names(coef(mv_raw_fit)))))
  mv_marg_adj <- mv_marginal(mv_adj_cf, mv_adj_V, mv_adj_lv, ref = 5L)

  mv_levels <- bind_rows(
    mutate(mv_raw_lvl, series = "raw"),
    mutate(mv_adj_lvl, series = "adjusted")
  )
  mv_marginal_tbl <- bind_rows(
    mutate(mv_marg_raw, series = "raw"),
    mutate(mv_marg_adj, series = "adjusted")
  )

  # ── 4. Appendix A1: where the variation comes from, by country and regime ───
  # Contemporary window only. Cross-sectional variation in the historical era is a
  # property of the retrospective coding programme, not of panel recruitment.
  message("Building country and regime cuts...")
  var_dat <- vdemdata::vdem |>
    select(country_text_id, year, any_of(paste0(indicators, "_nr"))) |>
    filter(year >= MV_FROM, year <= MV_TO) |>
    pivot_longer(-c(country_text_id, year), names_to = "indicator", values_to = "n_coders") |>
    filter(!is.na(n_coders)) |>
    mutate(survey = substr(sub("_nr$", "", indicator), 1, 4))

  country_names <- read_csv(file.path(proj_root, "data", "processed", "ert.csv"),
                            show_col_types = FALSE) |>
    distinct(country_text_id, country_name)

  # Mean panel size and the share of cells under the floor are related but not redundant
  # (r = -0.54), so the ranking carries the level and the colour carries the tail.
  country <- var_dat |>
    group_by(country_text_id) |>
    summarise(mean_n = mean(n_coders),
              pct_lt5 = mean(n_coders < THRESHOLDS[["recommended_floor"]]) * 100,
              .groups = "drop") |>
    left_join(country_names, by = "country_text_id") |>
    mutate(country_name = coalesce(country_name, country_text_id)) |>
    arrange(mean_n) |>
    mutate(rank = row_number(),
           lt5_bin = cut(pct_lt5, c(-Inf, 1, 5, 10, 20, Inf),
                         labels = c("<1%", "1–5%", "5–10%", "10–20%", ">20%")))

  # Regime comes from vdem directly so this uses the same scored set as everything else.
  regime <- vdemdata::vdem |>
    select(country_text_id, year, v2x_regime, any_of(paste0(indicators, "_nr"))) |>
    filter(year >= 1990, year <= MV_TO, !is.na(v2x_regime)) |>
    pivot_longer(-c(country_text_id, year, v2x_regime),
                 names_to = "indicator", values_to = "n_coders") |>
    filter(!is.na(n_coders)) |>
    mutate(regime = factor(v2x_regime, 0:3,
                           labels = c("Closed autocracy", "Electoral autocracy",
                                      "Electoral democracy", "Liberal democracy"))) |>
    group_by(year, regime) |>
    summarise(mean_n = mean(n_coders), .groups = "drop")

  # ── 5. Appendix A2: by survey, and a variance decomposition ─────────────────
  # V-Dem recruits at the SURVEY level, not the indicator level: experts "code at least
  # one cluster" and "most code one to two clusters" (methodology p. 16). So indicator
  # variation is largely survey variation, and the survey is the unit that corresponds to
  # an actual recruitment decision.
  message("Building survey cut and variance decomposition...")
  survey_labels <- c(
    v2el = "Elections",       v2ps = "Political Parties", v2ex = "Executive",
    v2lg = "Legislature",     v2dl = "Deliberation",      v2ju = "Judiciary",
    v2cl = "Civil Liberty",   v2sv = "Sovereignty",       v2st = "The State",
    v2cs = "Civil Society",   v2me = "Media",             v2pe = "Political Equality",
    v2ca = "Civic & Academic Space", v2sm = "Digital Society"
  )

  # A survey's first year matters: one introduced in 2000 has had fewer recruitment rounds
  # to accumulate coders than one running from 1789, so youth and thinness are confounded.
  survey_start <- vdemdata::vdem |>
    select(country_text_id, year, any_of(paste0(indicators, "_nr"))) |>
    pivot_longer(-c(country_text_id, year), names_to = "indicator", values_to = "n_coders") |>
    filter(!is.na(n_coders)) |>
    mutate(survey = substr(sub("_nr$", "", indicator), 1, 4)) |>
    group_by(survey) |>
    summarise(first_year = min(year), .groups = "drop")

  survey <- var_dat |>
    group_by(survey) |>
    summarise(mean_n = mean(n_coders), n_ind = n_distinct(indicator), .groups = "drop") |>
    left_join(survey_start, by = "survey") |>
    mutate(name = paste0(survey_labels[survey], " (", n_ind, ")"),
           later_start = first_year > 1789) |>
    arrange(mean_n)

  # One-way R-squared per grouping, plus two nested fits. These are NOT orthogonal shares:
  # the single-predictor bars sum to more than the cumulative fit because country and year
  # overlap. R-squared is also mechanically increasing in the number of levels (country
  # 179, indicator 205, year 20, survey 14), so the ranking is partly a degrees-of-freedom
  # artifact -- per level, year is by far the strongest. Both caveats belong in the caption.
  r2_of <- function(f) fixest::r2(feols(f, var_dat), "r2")
  var_r2 <- tibble(
    source = c("Country", "Year", "Survey", "Indicator", "Country + indicator", "+ year"),
    r2 = c(r2_of(n_coders ~ 1 | country_text_id),
           r2_of(n_coders ~ 1 | year),
           r2_of(n_coders ~ 1 | survey),
           r2_of(n_coders ~ 1 | indicator),
           r2_of(n_coders ~ 1 | country_text_id + indicator),
           r2_of(n_coders ~ 1 | country_text_id + indicator + year)),
    kind = c(rep("one predictor", 4), rep("cumulative", 2)),
    n_levels = c(n_distinct(var_dat$country_text_id), n_distinct(var_dat$year),
                 n_distinct(var_dat$survey), n_distinct(var_dat$indicator), NA, NA)
  )

  out <- list(
    era         = era,
    pairs       = pairs,
    settled_ref = attr_dat$settled_ref,
    mv_levels   = mv_levels,
    mv_marginal = mv_marginal_tbl,
    mv_n        = count(mv_dat, n_coders, name = "cells"),
    country     = country,
    regime      = regime,
    survey      = survey,
    var_r2      = var_r2,
    meta = list(
      thresholds      = THRESHOLDS,
      era_cuts        = ERA_CUTS,
      era_labels      = ERA_LABELS,
      band_cuts       = BAND_CUTS,
      band_labels     = BAND_LABELS,
      n_indicators    = length(indicators),
      indicators      = indicators,
      n_ind_pre1900   = n_ind_pre1900,
      mv_window       = c(MV_FROM, MV_TO),
      mv_max          = NRMAX,
      mv_cells        = nrow(mv_dat),
      var_window      = c(MV_FROM, MV_TO),
      n_countries     = nrow(country),
      settled_years   = attr_dat$meta$settled_years,
      release         = "V16 (vdemdata 16.0)",
      attrition_built = attr_dat$meta$built_at,
      built_at        = Sys.time()
    )
  )

  if (write) {
    dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
    f <- file.path(out_dir, "panelsize.rds")
    saveRDS(out, f)
    message("Wrote ", f)
  }
  out
}

if (sys.nframe() == 0) {
  res <- build_panelsize(find_panel_member_root())

  cat("\n=== Figure 1A: share below five, by era ===\n")
  print(as.data.frame(res$era |> distinct(era, cells, pct_lt5) |>
                        mutate(era = gsub("\n", " ", era), pct_lt5 = round(pct_lt5, 1))),
        row.names = FALSE)

  cat("\n=== Figure 1B: share below five, first published vs. now ===\n")
  print(as.data.frame(res$pairs |>
                        pivot_wider(names_from = when, values_from = pct) |>
                        mutate(across(where(is.numeric), ~round(.x, 1)))), row.names = FALSE)
  cat("settled reference (", paste(res$meta$settled_years, collapse = "-"), "): ",
      res$settled_ref, "%\n", sep = "")

  cat("\n=== Figure 2: what each added coder buys (adjusted) ===\n")
  print(as.data.frame(
    res$mv_marginal |>
      filter(series == "adjusted") |>
      left_join(res$mv_n, by = "n_coders") |>
      transmute(`panel size` = n_coders, cells,
                delta = round(d, 4), se = round(se, 4),
                lo = round(d - 1.96 * se, 4), hi = round(d + 1.96 * se, 4),
                excl_zero = ifelse((d - 1.96 * se) * (d + 1.96 * se) > 0, "*", ""))),
    row.names = FALSE)

  cat("\n=== Appendix A1: thinnest and thickest countries ===\n")
  print(as.data.frame(res$country |>
                        filter(rank <= 4 | rank > n() - 4) |>
                        transmute(rank, country_name, mean_n = round(mean_n, 2),
                                  pct_lt5 = round(pct_lt5, 1))), row.names = FALSE)

  cat("\n=== Appendix A2: variance decomposition ===\n")
  print(as.data.frame(res$var_r2 |> mutate(r2 = round(r2, 3))), row.names = FALSE)
}
