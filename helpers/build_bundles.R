# build_bundles.R — regenerate the derived bootstrap/expectation bundles WITHOUT rendering
# the analysis QMDs.
#
# analysis/06-bootstrap-metrics-2019.qmd and analysis/13-expectation-readout-2019.qmd are lab
# notebooks: they compute the bundles AND render prototype figures + diagnostic tables. But the
# paper (paper/figures-and-tables.qmd) only ever reads the two serialized bundles:
#   data/derived/bootstrap_{year}.rds     (greedy MAE landscape + rails + SESOI + movement bins)
#   data/derived/expectation_{year}.rds   (greedy vs mean readout, paired within-draw)
#
# This file lifts *only* the bundle-producing compute out of those QMDs into plain functions, so
# the bundles can be refreshed with one call — no knitr, no cache, no stale-param trap. The
# figure/table prototypes stay in the QMDs as a notebook; they are no longer on Fig 1's path.
#
# The compute is a faithful copy of the QMD chunks (same country-clustered bootstrap, seed 42,
# n_boot = 2000, min_coders = 2). build_bundles.R and the QMDs must stay in lockstep; the 2019
# reproduction check at the bottom (`--verify`) is the guard that they still agree.
#
# Usage — from the project root:
#   Rscript helpers/build_bundles.R                       # 2019 both bundles (default)
#   Rscript helpers/build_bundles.R --year 2023 --runs-subdir 2023 --exp-subdir 2023
#   Rscript helpers/build_bundles.R --which bootstrap     # greedy bundle only
#   Rscript helpers/build_bundles.R --verify              # rebuild 2019 to a temp dir & diff
# or interactively:
#   source("helpers/build_bundles.R"); build_bootstrap_bundle(proj_root, year = 2019)

suppressPackageStartupMessages({
  library(tidyverse)
  library(glue)
})

# ── project root (same robust resolution the QMDs use) ───────────────────────
find_panel_member_root <- function() {
  up <- tryCatch(rprojroot::find_root(rprojroot::is_git_root), error = function(e) NA_character_)
  if (!is.na(up)) return(up)
  down <- file.path(getwd(), "panel-member")
  if (dir.exists(file.path(down, ".git"))) return(down)
  stop("Could not locate the panel-member project root from working dir: ", getwd())
}

# ── shared reader helpers ────────────────────────────────────────────────────
# Individual-coder leave-one-out MAE per CYI (identical in both QMDs).
compute_human_loo <- function(human_ratings, year, min_coders) {
  human_ratings |>
    filter(year == !!year) |>
    group_by(country_text_id, year, indicator) |>
    filter(n() >= min_coders) |>
    mutate(
      panel_sum = sum(rating),
      n_coders  = n(),
      loo_mean  = (panel_sum - rating) / (n_coders - 1),
      loo_error = abs(rating - loo_mean)
    ) |>
    summarise(human_loo_mae = mean(loo_error), n_coders = first(n_coders), .groups = "drop")
}

# ── GREEDY bundle (mirror of analysis/06 §2–§9) ──────────────────────────────
build_bootstrap_bundle <- function(proj_root,
                                   year        = 2019,
                                   runs_subdir = "",
                                   n_boot      = 2000,
                                   min_coders  = 2,
                                   seed        = 42,
                                   out_dir     = file.path(proj_root, "data", "derived"),
                                   write       = TRUE) {
  source(file.path(proj_root, "helpers", "bootstrap_helpers.R"), local = TRUE)
  data_dir <- file.path(proj_root, "data", "processed")
  runs_dir <- file.path(proj_root, "data", "output", "runs", runs_subdir)
  if (!dir.exists(runs_dir)) stop("runs dir not found: ", runs_dir)

  needed_cols <- c("country", "year", "indicator", "condition", "model_key", "rating")
  read_run <- function(f) {
    con <- file(f, "r"); on.exit(close(con))
    jsonlite::stream_in(con, verbose = FALSE) |> as_tibble() |> select(all_of(needed_cols))
  }
  run_files <- list.files(runs_dir, pattern = "\\.jsonl$", full.names = TRUE)
  if (length(run_files) == 0) stop("No .jsonl files in ", runs_dir)
  ai_raw <- run_files |> map(read_run) |> bind_rows() |>
    mutate(model_key = str_remove(model_key, "-local$"))

  panel_means   <- read_csv(file.path(data_dir, "panel_means.csv"),   show_col_types = FALSE)
  human_ratings <- read_csv(file.path(data_dir, "human_ratings.csv"), show_col_types = FALSE)

  human_loo <- compute_human_loo(human_ratings, year, min_coders)

  ai_metrics <- ai_raw |>
    filter(year == !!year) |>
    rename(country_text_id = country) |>
    inner_join(select(panel_means, country_text_id, year, indicator, raw_mean),
               by = c("country_text_id", "year", "indicator")) |>
    inner_join(select(human_loo, country_text_id, year, indicator, human_loo_mae),
               by = c("country_text_id", "year", "indicator")) |>
    mutate(ai_error = abs(rating - raw_mean),
           col      = canon_col(condition),
           family   = recode(model_key, !!!model_family))

  # ── country-clustered bootstrap (seed 42, shared W reused by the persistence rail) ──
  cyi_pool <- ai_metrics |> distinct(country_text_id, year, indicator, human_loo_mae)
  W <- country_boot_weights(cyi_pool$country_text_id, n_boot, seed = seed)

  boot_results <- map_dfr(colnames(W), \(draw) {
    country_w <- tibble(country_text_id = rownames(W), w = W[, draw]) |> filter(w > 0)
    ai_metrics |>
      inner_join(country_w, by = "country_text_id") |>
      group_by(model_key, condition) |>
      summarise(
        ai_mae    = weighted.mean(ai_error, w),
        human_mae = weighted.mean(human_loo_mae, w),
        diff      = weighted.mean(ai_error, w) - weighted.mean(human_loo_mae, w),
        .groups   = "drop"
      ) |>
      mutate(id = draw, .before = 1)
  })

  boot_ci <- boot_results |>
    group_by(model_key, condition) |>
    summarise(
      ai_lo     = quantile(ai_mae[id != "Apparent"], 0.025),
      ai_hi     = quantile(ai_mae[id != "Apparent"], 0.975),
      diff_lo   = quantile(diff[id != "Apparent"], 0.025),
      diff_hi   = quantile(diff[id != "Apparent"], 0.975),
      p_gt_zero = mean(diff[id != "Apparent"] > 0),
      ai_mae    = mean(ai_mae[id == "Apparent"]),
      diff      = mean(diff[id == "Apparent"]),
      .groups   = "drop"
    )

  human_ref <- boot_results |>
    group_by(id) |>
    summarise(human_mae = first(human_mae), .groups = "drop") |>
    summarise(
      lo        = quantile(human_mae[id != "Apparent"], 0.025),
      hi        = quantile(human_mae[id != "Apparent"], 0.975),
      human_mae = mean(human_mae[id == "Apparent"])
    )

  # ── reference rails: persistence (year-1 copy-forward, rounded) + SESOI ──
  pm18 <- panel_means |> filter(year == !!year - 1) |>
    select(country_text_id, indicator, mean_2018 = raw_mean)
  persist_cyi <- cyi_pool |>
    left_join(panel_means |> filter(year == !!year) |>
                select(country_text_id, indicator, raw_mean),
              by = c("country_text_id", "indicator")) |>
    left_join(pm18, by = c("country_text_id", "indicator")) |>
    mutate(persist_err = abs(round(mean_2018) - raw_mean))

  rounding_floor <- mean(abs(round(persist_cyi$raw_mean) - persist_cyi$raw_mean))
  sesoi <- rounding_floor / 2

  pv <- vapply(colnames(W), \(draw) {
    wt <- W[persist_cyi$country_text_id, draw]
    ok <- wt > 0 & !is.na(persist_cyi$persist_err)
    weighted.mean(persist_cyi$persist_err[ok], wt[ok])
  }, numeric(1))
  persist_ref <- tibble(
    lo          = quantile(pv[names(pv) != "Apparent"], 0.025),
    hi          = quantile(pv[names(pv) != "Apparent"], 0.975),
    persist_mae = pv[["Apparent"]]
  )

  # ── exploratory movement bins (year-1 → year |Δ|) ──
  abs_delta_cyi <- persist_cyi |>
    filter(!is.na(mean_2018)) |>
    transmute(country_text_id, year, indicator, persist_err,
              abs_delta = abs(raw_mean - mean_2018))
  base_err_wide <- ai_metrics |>
    filter(model_key == "llama-70b", condition %in% c("codebook", "evidence")) |>
    select(country_text_id, year, indicator, condition, ai_error) |>
    pivot_wider(names_from = condition, values_from = ai_error)
  movement_bins <- abs_delta_cyi |>
    inner_join(base_err_wide, by = c("country_text_id", "year", "indicator")) |>
    mutate(bin = cut(abs_delta, breaks = c(0, 0.25, 0.5, 1, 2, Inf), right = FALSE,
                     labels = c("[0.00, 0.25)", "[0.25, 0.50)", "[0.50, 1.00)",
                                "[1.00, 2.00)", "[2.00, +)"))) |>
    group_by(bin) |>
    summarise(
      n            = n(),
      n_ev         = sum(!is.na(evidence)),
      persist_cont = mean(abs_delta),
      persist_round= mean(persist_err),
      base_cb_mae  = mean(codebook, na.rm = TRUE),
      base_ev_mae  = mean(evidence, na.rm = TRUE),
      .groups      = "drop"
    )

  bundle <- list(
    boot_ci        = boot_ci,
    boot_results   = boot_results,
    human_ref      = human_ref,
    persist_ref    = persist_ref,
    sesoi          = sesoi,
    rounding_floor = rounding_floor,
    movement_bins  = movement_bins
  )
  if (write) {
    dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
    path <- file.path(out_dir, glue("bootstrap_{year}.rds"))
    saveRDS(bundle, path)
    message(glue("bootstrap bundle written: {path} ({round(file.size(path)/1024)} KB) · ",
                 "{n_distinct(paste(boot_ci$model_key, boot_ci$condition))} cells"))
  }
  invisible(bundle)
}

# ── EXPECTATION bundle (mirror of analysis/13 §2–§11) ────────────────────────
build_expectation_bundle <- function(proj_root,
                                     year       = 2019,
                                     exp_subdir = "expectation",
                                     n_boot     = 2000,
                                     min_coders = 2,
                                     seed       = 42,
                                     out_dir    = file.path(proj_root, "data", "derived"),
                                     write      = TRUE) {
  source(file.path(proj_root, "helpers", "bootstrap_helpers.R"), local = TRUE)
  data_dir <- file.path(proj_root, "data", "processed")
  exp_dir  <- file.path(proj_root, "data", "output", "runs", exp_subdir)
  if (!dir.exists(exp_dir)) stop("expectation runs dir not found: ", exp_dir)

  needed_cols <- c("country", "year", "indicator", "condition", "model_key", "rating", "rating_dist")
  read_exp <- function(f) {
    con <- file(f, "r"); on.exit(close(con))
    df <- jsonlite::stream_in(con, simplifyMatrix = FALSE, verbose = FALSE) |> as_tibble()
    if (!"rating_dist" %in% names(df))
      stop("No 'rating_dist' in ", basename(f), " — point exp_subdir at the logprob re-run.")
    d <- df[["rating_dist"]]
    df[["rating_dist"]] <- if (is.matrix(d)) asplit(d, 1) else as.list(d)
    select(df, all_of(needed_cols))
  }
  exp_files <- list.files(exp_dir, pattern = "\\.jsonl$", full.names = TRUE)
  if (length(exp_files) == 0) stop("No .jsonl files in ", exp_dir)
  exp_raw <- exp_files |> map(read_exp) |> bind_rows() |>
    mutate(model_key = str_remove(model_key, "-local$"))

  panel_means   <- read_csv(file.path(data_dir, "panel_means.csv"),   show_col_types = FALSE)
  human_ratings <- read_csv(file.path(data_dir, "human_ratings.csv"), show_col_types = FALSE)

  human_loo <- compute_human_loo(human_ratings, year, min_coders)

  exp_rating_of <- function(d) {
    d <- suppressWarnings(as.numeric(unlist(d)))
    if (length(d) == 0 || all(is.na(d)) || sum(d, na.rm = TRUE) <= 0) return(NA_real_)
    sum((seq_along(d) - 1) * d, na.rm = TRUE) / sum(d, na.rm = TRUE)
  }

  cell_metrics_all <- exp_raw |>
    filter(year == !!year) |>
    rename(country_text_id = country) |>
    inner_join(select(panel_means, country_text_id, year, indicator, raw_mean),
               by = c("country_text_id", "year", "indicator")) |>
    inner_join(select(human_loo, country_text_id, year, indicator, human_loo_mae),
               by = c("country_text_id", "year", "indicator")) |>
    mutate(
      exp_rating   = map_dbl(rating_dist, exp_rating_of),
      greedy_error = abs(rating - raw_mean),
      exp_error    = abs(exp_rating - raw_mean),
      col          = canon_col(condition),
      family       = recode(model_key, !!!model_family)
    )

  miss_tbl <- cell_metrics_all |>
    group_by(model_key, condition) |>
    summarise(n = n(), n_missing = sum(is.na(exp_rating)),
              pct_missing = round(100 * n_missing / n, 3), .groups = "drop")
  cell_metrics <- filter(cell_metrics_all, !is.na(exp_rating))

  # rails/SESOI are readout-independent → reuse the greedy bundle
  bpath <- file.path(out_dir, glue("bootstrap_{year}.rds"))
  if (!file.exists(bpath))
    stop("greedy bundle not found: ", bpath, "\nBuild the bootstrap bundle first.")
  greedy_bundle  <- readRDS(bpath)
  sesoi          <- greedy_bundle$sesoi
  rounding_floor <- greedy_bundle$rounding_floor

  cyi_pool <- distinct(cell_metrics, country_text_id, year, indicator)
  W <- country_boot_weights(cyi_pool$country_text_id, n_boot, seed = seed)

  boot_both <- map_dfr(colnames(W), \(draw) {
    country_w <- tibble(country_text_id = rownames(W), w = W[, draw]) |> filter(w > 0)
    cell_metrics |>
      inner_join(country_w, by = "country_text_id") |>
      group_by(model_key, condition) |>
      summarise(greedy_mae = weighted.mean(greedy_error, w),
                exp_mae    = weighted.mean(exp_error, w), .groups = "drop") |>
      mutate(id = draw, .before = 1)
  })

  greedy_boot_results <- transmute(boot_both, id, model_key, condition, ai_mae = greedy_mae)
  exp_boot_results    <- transmute(boot_both, id, model_key, condition, ai_mae = exp_mae)

  boot_ci_of <- function(results) {
    results |>
      group_by(model_key, condition) |>
      summarise(
        ai_lo  = quantile(ai_mae[id != "Apparent"], 0.025),
        ai_hi  = quantile(ai_mae[id != "Apparent"], 0.975),
        ai_mae = mean(ai_mae[id == "Apparent"]),
        .groups = "drop"
      )
  }
  greedy_ci <- boot_ci_of(greedy_boot_results)
  exp_ci    <- boot_ci_of(exp_boot_results)

  gain_ci <- boot_both |>
    mutate(gain = greedy_mae - exp_mae) |>
    group_by(model_key, condition) |>
    summarise(
      greedy_mae = mean(greedy_mae[id == "Apparent"]),
      exp_mae    = mean(exp_mae[id == "Apparent"]),
      gain_lo    = quantile(gain[id != "Apparent"], 0.025),
      gain_hi    = quantile(gain[id != "Apparent"], 0.975),
      gain       = mean(gain[id == "Apparent"]),
      .groups    = "drop"
    ) |>
    mutate(model = recode(model_key, !!!model_labels), col = canon_col(condition)) |>
    arrange(model_key, condition)

  # ── Prediction 2: contrast survival (greedy vs expectation), skipping cells not captured ──
  contrast_specs <- tribble(
    ~a_mk,               ~a_cond,               ~b_mk,               ~b_cond,               ~label,               ~grp,
    "llama-70b",         "evidence",            "llama-70b",         "codebook",            "B1 · Ev−Cb",         "B",
    "llama-70b",         "anonymized",          "llama-70b",         "codebook",            "B2 · An−Cb",         "B",
    "llama-70b",         "anonymized",          "llama-70b",         "evidence",            "B3 · An−Ev",         "B",
    "llama-70b",         "summarized",          "llama-70b",         "anonymized",          "B4 · Su−An",         "B",
    "llama-70b-ft-raw",  "evidence-zeroshot",   "llama-70b",         "evidence",            "F1 · Raw",           "F1",
    "llama-70b-ft-anon", "anonymized-zeroshot", "llama-70b",         "anonymized",          "F1 · Anon",          "F1",
    "llama-70b-ft-summ", "summarized-zeroshot", "llama-70b",         "summarized",          "F1 · Summ",          "F1",
    "llama-70b-ft-raw",  "evidence-zeroshot",   "llama-70b",         "evidence-zeroshot",   "F1' · Raw (pm)",     "F1pm",
    "llama-70b-ft-anon", "anonymized-zeroshot", "llama-70b",         "anonymized-zeroshot", "F1' · Anon (pm)",    "F1pm",
    "llama-70b-ft-summ", "summarized-zeroshot", "llama-70b",         "summarized-zeroshot", "F1' · Summ (pm)",    "F1pm",
    "llama-70b-ft-anon", "evidence-zeroshot",   "llama-70b-ft-raw",  "evidence-zeroshot",   "F2 · anon−raw",      "F2",
    "llama-70b-ft-summ", "evidence-zeroshot",   "llama-70b-ft-anon", "evidence-zeroshot",   "F2 · summ−anon",     "F2",
    "llama-70b",         "evidence-zeroshot",   "llama-70b",         "codebook",            "A1 · Ev-zs−Cb",      "A1",
    "llama-70b",         "anonymized-zeroshot", "llama-70b",         "codebook",            "A1 · An-zs−Cb",      "A1",
    "llama-70b",         "summarized-zeroshot", "llama-70b",         "codebook",            "A1 · Su-zs−Cb",      "A1",
    "llama-70b",         "evidence",            "llama-70b",         "evidence-zeroshot",   "A2 · Ev gap",        "A2",
    "llama-70b",         "anonymized",          "llama-70b",         "anonymized-zeroshot", "A2 · An gap",        "A2",
    "llama-70b",         "summarized",          "llama-70b",         "summarized-zeroshot", "A2 · Su gap",        "A2",
    "llama-70b-ft-anon", "codebook",            "llama-70b-ft-raw",  "codebook",            "A3 · anon−raw",      "A3",
    "llama-70b-ft-summ", "codebook",            "llama-70b-ft-anon", "codebook",            "A3 · summ−anon",     "A3",
    "llama-70b-ft-anon", "evidence-zeroshot",   "llama-70b",         "evidence",            "A5 · FT-anon−Base",  "A5",
    "llama-70b-ft-summ", "evidence-zeroshot",   "llama-70b",         "evidence",            "A5 · FT-summ−Base",  "A5"
  )
  avail_cells <- distinct(greedy_boot_results, model_key, condition)
  has_cell <- function(mk, cond) any(avail_cells$model_key == mk & avail_cells$condition == cond)
  contrast_specs <- contrast_specs |>
    mutate(computable = pmap_lgl(list(a_mk, a_cond, b_mk, b_cond),
      \(a_mk, a_cond, b_mk, b_cond) has_cell(a_mk, a_cond) && has_cell(b_mk, b_cond)))
  specs_run  <- filter(contrast_specs, computable) |> select(-computable)
  specs_skip <- filter(contrast_specs, !computable)
  if (nrow(specs_skip) > 0)
    message("Skipped ", nrow(specs_skip), " contrast(s) needing uncaptured cells: ",
            paste(specs_skip$label, collapse = ", "))

  run_contrasts <- function(results) {
    pmap_dfr(specs_run, function(a_mk, a_cond, b_mk, b_cond, label, grp) {
      paired_delta(a_mk, a_cond, b_mk, b_cond, label, results = results, sesoi_val = sesoi) |>
        mutate(grp = grp)
    })
  }
  greedy_contr <- run_contrasts(greedy_boot_results)
  exp_contr    <- run_contrasts(exp_boot_results)
  survival <- greedy_contr |>
    select(label, grp, g_est = est, g_lo = lo, g_hi = hi, g_out = sesoi_out) |>
    inner_join(select(exp_contr, label, e_est = est, e_lo = lo, e_hi = hi, e_out = sesoi_out),
               by = "label") |>
    mutate(sign_flip = sign(g_est) != sign(e_est),
           survives  = (g_out == e_out) & !sign_flip)

  bundle <- list(
    exp_ci              = exp_ci,
    greedy_ci_rerun     = greedy_ci,
    boot_both           = boot_both,
    exp_boot_results    = exp_boot_results,
    greedy_boot_results = greedy_boot_results,
    gain_ci             = gain_ci,
    p2_survival         = survival,
    miss_tbl            = miss_tbl,
    sesoi               = sesoi,
    rounding_floor      = rounding_floor
  )
  if (write) {
    dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
    path <- file.path(out_dir, glue("expectation_{year}.rds"))
    saveRDS(bundle, path)
    message(glue("expectation bundle written: {path} ({round(file.size(path)/1024)} KB) · ",
                 "{n_distinct(paste(exp_ci$model_key, exp_ci$condition))} cells"))
  }
  invisible(bundle)
}

# ── CLI ──────────────────────────────────────────────────────────────────────
parse_args <- function(a) {
  out <- list(year = 2019, runs_subdir = "", exp_subdir = "expectation",
              n_boot = 2000, which = "both", verify = FALSE)
  i <- 1
  while (i <= length(a)) {
    switch(a[[i]],
      "--year"        = { out$year        <- as.integer(a[[i + 1]]); i <- i + 2 },
      "--runs-subdir" = { out$runs_subdir <- a[[i + 1]];             i <- i + 2 },
      "--exp-subdir"  = { out$exp_subdir  <- a[[i + 1]];             i <- i + 2 },
      "--n-boot"      = { out$n_boot      <- as.integer(a[[i + 1]]); i <- i + 2 },
      "--which"       = { out$which       <- a[[i + 1]];             i <- i + 2 },
      "--verify"      = { out$verify      <- TRUE;                   i <- i + 1 },
      stop("unknown arg: ", a[[i]])
    )
  }
  out
}

# Rebuild 2019 into a temp dir and diff against the live bundles — the drift guard between this
# script and the QMDs. Uses the live bootstrap bundle as the expectation rails source, so it is a
# clean end-to-end check.
verify_2019 <- function(proj_root) {
  tmp <- file.path(tempdir(), "bundle-verify"); dir.create(tmp, showWarnings = FALSE)
  live <- file.path(proj_root, "data", "derived")
  cmp <- function(name, live_path, new) {
    if (!file.exists(live_path)) { message(name, ": no live bundle to compare"); return(invisible()) }
    old <- readRDS(live_path)
    eq  <- isTRUE(all.equal(old[names(new)], new[names(new)], tolerance = 1e-9))
    message(name, ": ", if (eq) "MATCH (reproduces live bundle)" else "DIFFERS from live bundle")
    if (!eq) print(all.equal(old[names(new)], new[names(new)], tolerance = 1e-9))
  }
  # bootstrap: need a fresh build for exp rails, so write it into tmp first
  b <- build_bootstrap_bundle(proj_root, year = 2019, out_dir = tmp, write = TRUE)
  cmp("bootstrap_2019", file.path(live, "bootstrap_2019.rds"), b)
  e <- build_expectation_bundle(proj_root, year = 2019, out_dir = tmp, write = FALSE)
  cmp("expectation_2019", file.path(live, "expectation_2019.rds"), e)
}

if (sys.nframe() == 0) {
  opt <- parse_args(commandArgs(trailingOnly = TRUE))
  proj_root <- find_panel_member_root()
  if (opt$verify) {
    verify_2019(proj_root)
  } else {
    if (opt$which %in% c("both", "bootstrap"))
      build_bootstrap_bundle(proj_root, year = opt$year, runs_subdir = opt$runs_subdir,
                             n_boot = opt$n_boot)
    if (opt$which %in% c("both", "expectation"))
      build_expectation_bundle(proj_root, year = opt$year, exp_subdir = opt$exp_subdir,
                               n_boot = opt$n_boot)
  }
}
