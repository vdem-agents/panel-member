# build_leakage_rails.R — "what would a memorizer actually score?" rails, for the data-leakage
# section (notes/leakage-vs-prior-assessment.md).
#
# The leakage objection to Figures 3-5 is that the base models score well in Codebook because the
# country name lets them retrieve a stored V-Dem score, and that de-identification hurts because it
# takes the retrieval key away. That objection is only answerable against a benchmark: how well
# would a model that HAD memorized the answer actually do on this metric? This helper computes that
# benchmark on the same CYI pool, with the same country-clustered bootstrap, as the MAE landscape.
#
# Four rails, from strongest to most realistic form of memorization:
#
#   rounding_floor  |round(raw_mean) - raw_mean|            knows THIS year's panel mean exactly,
#                                                           pays only the integer-output cost
#   persist         |round(raw_mean[y-1]) - raw_mean|       knows LAST year's panel mean exactly
#   ord             |ord[y]   - raw_mean|                   perfectly recites V-Dem's PUBLISHED
#                                                           ordinal for that exact CYI
#   ord_prev        |ord[y-1] - raw_mean|                   perfectly recites the published ordinal
#                                                           from the last pre-cutoff release
#
# `ord` is the rail that matters for the argument: the coder-level ratings that define `raw_mean`
# are access-controlled tabular data with no prose presence, so the published `_ord` is the only
# version of the answer that could plausibly sit in a pretraining corpus. `ord_prev` is the
# realistic version of the same story for a model whose cutoff predates the release carrying the
# focal year (Llama 3.3 / 2023, for instance).
#
# rounding_floor and persist duplicate build_bundles.R's rails by construction and are recomputed
# here as a cross-check — `--verify` diffs them against bootstrap_{year}.rds and errors on drift.
#
# The CYI pool, min_coders, n_boot and seed all mirror build_bootstrap_bundle() so the rails land on
# exactly the same denominator as the AI MAE cells they are read against. Observed base Codebook
# MAE is carried into the bundle from bootstrap_{year}.rds for the same reason.
#
# Usage — from the project root:
#   Rscript helpers/build_leakage_rails.R                       # 2019 (default)
#   Rscript helpers/build_leakage_rails.R --year 2023 --runs-subdir 2023
#   Rscript helpers/build_leakage_rails.R --year 2024 --runs-subdir 2024-fhonly
#   Rscript helpers/build_leakage_rails.R --year 2023 --runs-subdir 2023 --verify

suppressPackageStartupMessages({ library(tidyverse); library(glue); library(jsonlite) })

find_panel_member_root <- function() {
  up <- tryCatch(rprojroot::find_root(rprojroot::is_git_root), error = function(e) NA_character_)
  if (!is.na(up)) return(up)
  down <- file.path(getwd(), "panel-member")
  if (dir.exists(file.path(down, ".git"))) return(down)
  stop("Could not locate the panel-member project root from working dir: ", getwd())
}

build_leakage_rails <- function(proj_root,
                                year        = 2019,
                                runs_subdir = "",
                                n_boot      = 2000,
                                min_coders  = 2,
                                seed        = 42,
                                out_dir     = file.path(proj_root, "data", "derived"),
                                write       = TRUE,
                                verify      = FALSE) {
  source(file.path(proj_root, "helpers", "bootstrap_helpers.R"), local = TRUE)
  source(file.path(proj_root, "helpers", "build_bundles.R"), local = TRUE)  # compute_human_loo
  data_dir <- file.path(proj_root, "data", "processed")
  runs_dir <- file.path(proj_root, "data", "output", "runs", runs_subdir)
  if (!dir.exists(runs_dir)) stop("runs dir not found: ", runs_dir)

  # ── the CYI pool, built exactly as build_bootstrap_bundle() builds it ──────
  read_run <- function(f) {
    con <- file(f, "r"); on.exit(close(con))
    jsonlite::stream_in(con, verbose = FALSE) |> as_tibble() |>
      select(all_of(c("country", "year", "indicator")))
  }
  run_files <- list.files(runs_dir, pattern = "\\.jsonl$", full.names = TRUE)
  if (length(run_files) == 0) stop("No .jsonl files in ", runs_dir)
  ai_cyi <- run_files |> map(read_run) |> bind_rows() |>
    filter(year == !!year) |> rename(country_text_id = country) |> distinct()

  panel_means   <- read_csv(file.path(data_dir, "panel_means.csv"),   show_col_types = FALSE)
  human_ratings <- read_csv(file.path(data_dir, "human_ratings.csv"), show_col_types = FALSE)
  vdem_ord      <- read_csv(file.path(data_dir, "vdem_ord.csv"),      show_col_types = FALSE)

  human_loo <- compute_human_loo(human_ratings, year, min_coders)

  cyi_pool <- ai_cyi |>
    inner_join(select(panel_means, country_text_id, year, indicator, raw_mean),
               by = c("country_text_id", "year", "indicator")) |>
    inner_join(select(human_loo, country_text_id, year, indicator, human_loo_mae),
               by = c("country_text_id", "year", "indicator"))

  # ── the four memorization rails, per CYI ──────────────────────────────────
  pm_prev  <- panel_means |> filter(year == !!year - 1) |>
    select(country_text_id, indicator, raw_mean_prev = raw_mean)
  ord_cur  <- vdem_ord |> filter(year == !!year) |>
    select(country_text_id, indicator, ord)
  ord_prev <- vdem_ord |> filter(year == !!year - 1) |>
    select(country_text_id, indicator, ord_prev = ord)

  rails_cyi <- cyi_pool |>
    left_join(pm_prev,  by = c("country_text_id", "indicator")) |>
    left_join(ord_cur,  by = c("country_text_id", "indicator")) |>
    left_join(ord_prev, by = c("country_text_id", "indicator")) |>
    mutate(
      err_rounding = abs(round(raw_mean)      - raw_mean),
      err_persist  = abs(round(raw_mean_prev) - raw_mean),
      err_ord      = abs(ord                  - raw_mean),
      err_ord_prev = abs(ord_prev             - raw_mean)
    )

  rail_cols <- c(rounding_floor = "err_rounding", persist = "err_persist",
                 ord = "err_ord", ord_prev = "err_ord_prev")

  # ── country-clustered bootstrap, same primitive/seed as the MAE landscape ──
  W <- country_boot_weights(cyi_pool$country_text_id, n_boot, seed = seed)

  rail_ci <- imap_dfr(rail_cols, \(col, nm) {
    e  <- rails_cyi[[col]]
    bv <- vapply(colnames(W), \(draw) {
      wt <- W[rails_cyi$country_text_id, draw]
      ok <- wt > 0 & !is.na(e)
      weighted.mean(e[ok], wt[ok])
    }, numeric(1))
    tibble(
      rail = nm,
      mae  = bv[["Apparent"]],
      lo   = unname(quantile(bv[names(bv) != "Apparent"], 0.025)),
      hi   = unname(quantile(bv[names(bv) != "Apparent"], 0.975)),
      n    = sum(!is.na(e)),
      coverage = mean(!is.na(e))
    )
  })

  ord_ok  <- !is.na(rails_cyi$ord)
  ord_cor <- if (sum(ord_ok) > 2) cor(rails_cyi$ord[ord_ok], rails_cyi$raw_mean[ord_ok]) else NA_real_

  # ── observed cells, carried over so the comparison is on one denominator ──
  boot_path <- file.path(out_dir, glue("bootstrap_{year}.rds"))
  observed <- human_ref <- NULL
  if (file.exists(boot_path)) {
    bb <- readRDS(boot_path)
    observed <- bb$boot_ci |>
      select(model_key, condition, ai_mae, ai_lo, ai_hi) |>
      mutate(ratio_ord = ai_mae / rail_ci$mae[rail_ci$rail == "ord"])
    human_ref <- bb$human_ref

    if (verify) {
      chk <- c(rounding_floor = bb$rounding_floor, persist = bb$persist_ref$persist_mae)
      for (nm in names(chk)) {
        got <- rail_ci$mae[rail_ci$rail == nm]
        if (!isTRUE(all.equal(got, unname(chk[[nm]]), tolerance = 1e-6)))
          stop(glue("rail drift on {nm}: leakage_rails {round(got, 6)} vs ",
                    "bootstrap_{year}.rds {round(chk[[nm]], 6)}"))
      }
      message(glue("verify OK ({year}): rounding_floor and persist match bootstrap_{year}.rds"))
    }
  } else if (verify) {
    stop("--verify needs ", boot_path)
  }

  bundle <- list(rails = rail_ci, ord_cor = ord_cor, observed = observed,
                 human_ref = human_ref, year = year,
                 meta = list(n_cyi = nrow(cyi_pool), n_boot = n_boot,
                             min_coders = min_coders, seed = seed,
                             runs_dir = runs_dir, built_at = Sys.time()))

  if (write) {
    dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
    path <- file.path(out_dir, glue("leakage_rails_{year}.rds"))
    saveRDS(bundle, path)
    message(glue("leakage rails written: {path} · {nrow(cyi_pool)} CYIs"))
  }

  cat(glue("\n── leakage rails, {year} (n = {nrow(cyi_pool)} CYIs, ",
           "cor(ord, panel mean) = {round(ord_cor, 3)}) ──\n\n"))
  print(rail_ci |> mutate(across(c(mae, lo, hi, coverage), \(x) round(x, 3))), n = Inf)
  if (!is.null(observed)) {
    cat("\n── observed base Codebook cells against the `ord` rail ──\n\n")
    print(observed |> filter(condition == "codebook", !str_detect(model_key, "-ft-")) |>
            mutate(across(c(ai_mae, ai_lo, ai_hi, ratio_ord), \(x) round(x, 3))), n = Inf)
    cat(glue("\nhuman LOO reference: {round(human_ref$human_mae, 3)}\n\n"))
  }

  invisible(bundle)
}

# ── CLI ──────────────────────────────────────────────────────────────────────
parse_args <- function(a) {
  out <- list(year = 2019, runs_subdir = "", verify = FALSE)
  i <- 1
  while (i <= length(a)) {
    switch(a[[i]],
      "--year"        = { out$year        <- as.integer(a[[i + 1]]); i <- i + 2 },
      "--runs-subdir" = { out$runs_subdir <- a[[i + 1]];             i <- i + 2 },
      "--verify"      = { out$verify      <- TRUE;                   i <- i + 1 },
      stop("unknown arg: ", a[[i]]))
  }
  out
}

if (sys.nframe() == 0) {
  opt <- parse_args(commandArgs(trailingOnly = TRUE))
  proj_root <- find_panel_member_root()
  build_leakage_rails(proj_root, year = opt$year, runs_subdir = opt$runs_subdir,
                      verify = opt$verify)
}
