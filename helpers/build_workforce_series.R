# build_workforce_series.R — Cross-release coder counts, separating the active
# workforce from back-coding accumulation.
#
# Motivation. Analysis 01 reads panel size off a single release and sees decline
# after 2013. That reading is confounded: V-Dem's `year` is the year being rated,
# not the year the rating was produced. A coder hired in 2022 back-codes to 2005,
# so within one release they are indistinguishable from a founding coder, and
# arrivals are invisible while departures are visible. Any single release therefore
# shows a pyramid whether or not recruitment has stopped.
#
# Identification. A published release is frozen: only coders on the roster during
# that coding round can appear in its most recent year, because no one has had the
# chance to back-code into a file already printed. Reading each release at its own
# leading edge gives one backfill-free snapshot of workforce size per release.
# Reading a FIXED historical year across releases gives the complementary quantity:
# how fast later hires accumulate into settled years.
#
# Source: data/vdem.RData from tags V10-V16 of github.com/vdeminstitute/vdemdata,
# mirrored in shared/vdem-data/vdem-release-archive/. V10 (published 2020) is the
# earliest tagged release; reaching 2013 would require requesting v3 from v-dem.net.
#
# Outputs (panel-member/data/derived/workforce_series.rds), a list of:
#   edge     — one row per release x offset: workforce at that release's leading edge
#   backfill — one row per release x fixed historical year: accumulation over time
#   meta     — the constant country and indicator sets, and release publication years
#
# Usage:
#   Rscript helpers/build_workforce_series.R

suppressPackageStartupMessages({ library(tidyverse) })

find_panel_member_root <- function() {
  up <- tryCatch(rprojroot::find_root(rprojroot::is_git_root), error = function(e) NA_character_)
  if (!is.na(up)) return(up)
  down <- file.path(getwd(), "panel-member")
  if (dir.exists(file.path(down, ".git"))) return(down)
  stop("Could not locate the panel-member project root from working dir: ", getwd())
}

# Publication year = edge year + 1. V11 was released as V11.1 in the package tags.
RELEASES <- c(V10 = 2020, "V11.1" = 2021, V12 = 2022, V13 = 2023,
              V14 = 2024, V15 = 2025, V16 = 2026)

OFFSETS   <- 0:2        # years back from each release's leading edge
FIXED_YRS <- 2005:2023  # settled years tracked across releases
MIN_FILL  <- 0.50       # a year is "covered" if >=50% of its cells are non-NA

build_workforce_series <- function(proj_root,
                                   archive = file.path(dirname(proj_root), "shared",
                                                       "vdem-data", "vdem-release-archive"),
                                   out_dir = file.path(proj_root, "data", "derived"),
                                   write   = TRUE) {

  load_release <- function(tag) {
    f <- file.path(archive, paste0("vdem_", tag, ".RData"))
    if (!file.exists(f)) stop("Missing release file: ", f)
    e <- new.env(); load(f, envir = e); e[[ls(e)[1]]]
  }

  message("Loading ", length(RELEASES), " releases from ", archive)
  rel <- set_names(map(names(RELEASES), load_release), names(RELEASES))

  # Indicator and country coverage both grow across releases (V10 carries 258 _nr
  # columns, V16 carries 294). Holding both fixed keeps the series from confounding
  # workforce change with scope expansion.
  inds <- reduce(map(rel, ~grep("_nr$", names(.x), value = TRUE)), intersect)
  ctys <- reduce(map(rel, ~unique(.x$country_text_id)), intersect)
  message("Common indicators: ", length(inds), " | common countries: ", length(ctys))

  # Mean coders per country-indicator cell in one release-year.
  panel_at <- function(z, yr) {
    v <- z |>
      filter(country_text_id %in% ctys, year == yr) |>
      select(all_of(inds)) |>
      unlist(use.names = FALSE)
    if (!any(!is.na(v))) return(NA_real_)
    mean(v[!is.na(v)])
  }

  # max(year) is unreliable — the final row-year may carry little coder data.
  edge_of <- function(z) {
    z |>
      filter(country_text_id %in% ctys) |>
      select(year, all_of(inds)) |>
      pivot_longer(all_of(inds), names_to = "ind", values_to = "nr") |>
      group_by(year) |>
      summarise(fill = mean(!is.na(nr)), .groups = "drop") |>
      filter(fill >= MIN_FILL) |>
      pull(year) |> max()
  }
  edges <- map_dbl(rel, edge_of)

  edge <- imap_dfr(rel, function(z, tag) {
    map_dfr(OFFSETS, ~tibble(
      release   = tag,
      pub_year  = RELEASES[[tag]],
      edge_year = edges[[tag]],
      offset    = .x,
      year      = edges[[tag]] - .x,
      mean_nr   = panel_at(z, edges[[tag]] - .x)
    ))
  }) |> arrange(pub_year, offset)

  backfill <- imap_dfr(rel, function(z, tag) {
    map_dfr(FIXED_YRS, ~tibble(
      release  = tag,
      pub_year = RELEASES[[tag]],
      year     = .x,
      mean_nr  = panel_at(z, .x)
    ))
  }) |>
    arrange(year, pub_year) |>
    group_by(year) |>
    mutate(increment = mean_nr - lag(mean_nr)) |>
    ungroup()

  out <- list(
    edge     = edge,
    backfill = backfill,
    meta     = list(releases = RELEASES, indicators = inds, countries = ctys,
                    offsets = OFFSETS, fixed_years = FIXED_YRS,
                    built_at = Sys.time())
  )

  if (write) {
    dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
    f <- file.path(out_dir, "workforce_series.rds")
    saveRDS(out, f)
    message("Wrote ", f)
  }
  out
}

if (sys.nframe() == 0) {
  root <- find_panel_member_root()
  res  <- build_workforce_series(root)
  cat("\n=== Workforce at each release's leading edge ===\n")
  print(as.data.frame(res$edge |>
    mutate(offset = paste0("edge_minus_", offset)) |>
    pivot_wider(id_cols = c(release, pub_year, edge_year),
                names_from = offset, values_from = mean_nr) |>
    mutate(across(starts_with("edge_minus_"), ~round(.x, 2)))), row.names = FALSE)
  cat("\n=== Back-coding accumulation into fixed year 2013 ===\n")
  print(as.data.frame(res$backfill |> filter(year == 2013) |>
    mutate(across(where(is.numeric), ~round(.x, 3)))), row.names = FALSE)
}
