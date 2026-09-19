# ─── RETIRED ──────────────────────────────────────────────────────────────
# Superseded by helpers/build_fliprate.R when Figure 7 moved from mean shift to verdict
# flips. The figure slot named on the next line is STALE: nothing in
# paper/figures-and-tables.qmd renders this bundle any more (see its line 137). The live
# deployment figure is fig_fliprate_quad. The bundle is still built and loaded because the
# mean-shift estimator stays quotable in prose.
#
# Do not read the design below as current. It draws an OBSERVED pool and zero-references
# human churn — sound for a mean shift, which is zero in expectation when a seat is
# refilled, but not for a verdict flip, which runs 16-42%. build_fliprate.R therefore
# CONSTRUCTS thinness from >=8-coder source panels (base B=4, ranks B+1..B+KMAX held out)
# and MEASURES churn against those real held-out coders, in one parameterised script whose
# --mechanic switch drives both the augmentation and degradation arms.
# ─────────────────────────────────────────────────────────────────────────
# build_doseresponse_augmentation.R — Figure 8, Panel B. How does the augmentation
# shift (build_augmentation.R's k=1 quantity) scale as k grows? Thin 2023 panels (2-8
# coders), k=1..4 AI seats added (panel grows to n+k). Promoted from notes/mockups/
# tipping-point-augmentation-mockup.R -- called "dose-response" throughout, not
# "tipping point": the metric is a continuous shift, nothing discrete "tips".
#
# Three regimes (human churn is not one of them -- its bootstrapped shift is ~0 at
# every k, i.e. exactly the zero-reference line the other regimes are judged against;
# checked directly, see notes/mockups/augmentation-concept.md):
#   Same AI      every added seat = Qwen FT-raw Evidence-ZS (settled by cross-checking
#                the swap/add/degradation single-seat analyses -- the one cell that
#                lands indistinguishable from zero in all three, and the system type
#                (FT + evidence-reading) the paper actually proposes)
#   Mixed FT     seats drawn without replacement from the 6 FT-raw cells (3 families x
#                {Codebook, Evidence-ZS} -- the trim used throughout the paper)
#   Mixed pool   seats drawn without replacement from all 18 cells (Base ladder x 3
#                families + the 6 FT-raw cells)
#
# 30 Monte Carlo draws/panel (seat-composition randomness) averaged per panel before a
# country-clustered bootstrap (2000 draws) over panels, at each k. No SESOI band, same
# reasoning as build_augmentation.R (a difference of two integers over a panel-size
# denominator has no forced-rounding floor).
#
# Usage:
#   Rscript helpers/build_doseresponse_augmentation.R

suppressPackageStartupMessages({ library(tidyverse); library(glue); library(jsonlite) })

find_panel_member_root <- function() {
  up <- tryCatch(rprojroot::find_root(rprojroot::is_git_root), error = function(e) NA_character_)
  if (!is.na(up)) return(up)
  down <- file.path(getwd(), "panel-member")
  if (dir.exists(file.path(down, ".git"))) return(down)
  stop("Could not locate the panel-member project root from working dir: ", getwd())
}

SAME_CELL <- "qwen-72b-ft-raw|evidence-zeroshot"

build_doseresponse_augmentation <- function(proj_root,
                                            year        = 2023,
                                            min_coders  = 2L,
                                            max_coders  = 8L,
                                            kmax        = 4L,
                                            ndraw       = 30L,
                                            n_boot      = 2000L,
                                            seed        = 42,
                                            out_dir     = file.path(proj_root, "data", "derived"),
                                            write       = TRUE) {
  source(file.path(proj_root, "helpers", "bootstrap_helpers.R"), local = TRUE)
  data_dir <- file.path(proj_root, "data", "processed")
  runs_dir <- file.path(proj_root, "data", "output", "runs", as.character(year))
  set.seed(seed)

  fams <- c("llama-70b", "qwen-72b", "gemma-27b")
  pool <- bind_rows(
    expand_grid(model_key = fams, condition = c("codebook", "evidence", "anonymized", "summarized")),
    expand_grid(model_key = paste0(fams, "-ft-raw"), condition = c("codebook", "evidence-zeroshot"))
  ) |> mutate(cell = paste(model_key, condition, sep = "|"), is_ft = str_detect(model_key, "ft-raw"))
  ft_idx <- which(pool$is_ft)

  hr <- read_csv(file.path(data_dir, "human_ratings.csv"), show_col_types = FALSE) |>
    filter(year == !!year)
  panels <- hr |>
    group_by(country_text_id, indicator) |>
    summarise(n = n(), m = mean(rating), r = list(rating), .groups = "drop") |>
    filter(n >= min_coders, n <= max_coders) |>
    mutate(pid = row_number(), key = paste(country_text_id, indicator))

  needed <- c("country", "indicator", "condition", "model_key", "rating")
  read_run <- function(f) {
    con <- file(f, "r"); on.exit(close(con))
    stream_in(con, verbose = FALSE) |> as_tibble() |> select(any_of(needed))
  }
  ai <- list.files(runs_dir, pattern = "\\.jsonl$", full.names = TRUE) |>
    map(read_run) |> bind_rows() |>
    mutate(model_key = str_remove(model_key, "-local$"),
           cell = paste(model_key, condition, sep = "|")) |>
    filter(cell %in% pool$cell) |>
    rename(country_text_id = country) |>
    mutate(key = paste(country_text_id, indicator)) |>
    distinct(cell, key, .keep_all = TRUE)
  stopifnot(length(unique(ai$cell)) == nrow(pool))
  ai_mat <- ai |> select(key, cell, rating) |>
    pivot_wider(names_from = cell, values_from = rating) |>
    column_to_rownames("key") |> as.matrix()
  ai_mat <- ai_mat[, pool$cell]

  panels <- panels |> filter(key %in% rownames(ai_mat))

  run_panel <- function(pp, kmax) {
    rows <- vector("list", nrow(pp))
    for (i in seq_len(nrow(pp))) {
      r <- pp$r[[i]]; n <- pp$n[i]; m <- pp$m[i]
      av <- ai_mat[pp$key[i], ]
      ft <- av[ft_idx]; ft <- ft[!is.na(ft)]
      al <- av[!is.na(av)]
      a1 <- av[[SAME_CELL]]
      if (length(ft) < kmax || length(al) < kmax || is.na(a1)) { rows[[i]] <- NULL; next }
      sh <- sf <- sa <- matrix(NA_real_, kmax, ndraw)
      for (j in seq_len(ndraw)) {
        sh[, j] <- cumsum(sample(r, kmax, replace = TRUE))
        sf[, j] <- cumsum(sample(ft, kmax))
        sa[, j] <- cumsum(sample(al, kmax))
      }
      rows[[i]] <- tibble(pid = pp$pid[i], country_text_id = pp$country_text_id[i],
                          n = n, m = m, k = rep(1:kmax, ndraw), draw = rep(1:ndraw, each = kmax),
                          sum_human = as.vector(sh), sum_ft = as.vector(sf), sum_all = as.vector(sa),
                          a1 = a1)
    }
    bind_rows(rows)
  }

  d <- run_panel(panels, kmax) |> mutate(
    shift_sameAI = (k * a1 - k * m) / (n + k),
    shift_ft     = (sum_ft - k * m) / (n + k),
    shift_pool   = (sum_all - k * m) / (n + k)
  )

  per_panel <- d |> group_by(pid, country_text_id, k) |>
    summarise(sameAI = mean(shift_sameAI), ft = mean(shift_ft), pool = mean(shift_pool),
             .groups = "drop")

  boot_regime <- function(df, outcome_col, label) {
    df |> group_by(k) |> group_modify(~ {
      dd <- .x
      W <- country_boot_weights(dd$country_text_id, n_boot, seed = seed)
      draws <- vapply(colnames(W), function(cl) {
        w <- unname(W[, cl][dd$country_text_id])
        weighted.mean(dd[[outcome_col]], w)
      }, numeric(1))
      app  <- which(names(draws) == "Apparent")
      boot <- setdiff(seq_along(draws), app)
      tibble(est = draws[app], lo = quantile(draws[boot], 0.025), hi = quantile(draws[boot], 0.975))
    }) |> ungroup() |> mutate(regime = label)
  }

  results <- bind_rows(
    boot_regime(per_panel, "sameAI", "Same AI (Qwen FT)"),
    boot_regime(per_panel, "ft",     "Mixed FT (6 cells)"),
    boot_regime(per_panel, "pool",   "Mixed pool (18 cells)")
  ) |> mutate(regime = factor(regime, levels = c("Same AI (Qwen FT)", "Mixed FT (6 cells)",
                                                 "Mixed pool (18 cells)")))

  bundle <- list(results = results, year = year, kmax = kmax, min_coders = min_coders,
                 max_coders = max_coders, ndraw = ndraw, n_boot = n_boot, same_cell = SAME_CELL)

  if (write) {
    dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
    path <- file.path(out_dir, glue("doseresponse_augmentation_{year}.rds"))
    saveRDS(bundle, path)
    message(glue("dose-response augmentation bundle written: {path} · {nrow(results)} rows"))
  }
  invisible(bundle)
}

if (sys.nframe() == 0) {
  proj_root <- find_panel_member_root()
  build_doseresponse_augmentation(proj_root)
}
