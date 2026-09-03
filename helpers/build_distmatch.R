# build_distmatch.R — regenerate the derived distributional-match bundle WITHOUT rendering
# analysis/07-distributional-match-2019.qmd.
#
# This lifts the Test-3 (difficulty-tracking slope) compute out of QMD 07 into a plain function
# and generalizes it past QMD 07's Llama-only cell list to all three model families
# (Llama 70B / Qwen 72B / Gemma 27B). It is the compute layer behind paper Figure 2 — the twin
# of Figure 1 that disaggregates the greedy-readout cluster along the dimension MAE can't see:
# does the synthetic coder err on the same cases a human finds hard?
#
#   difficulty  h_c = within-cell human LOO MAE (how much real coders disagreed on that CYI)
#   AI error    a_c = |greedy rating − panel mean|      (the panel-member readout)
#   Test 3      slope of a_c on h_c, weighted OLS; humans = 1 by construction; <1 = flatter
#               than a coder (leaning on a prior instead of reading each case).
#
# GREEDY ONLY by design: the slope is a panel-member question, so it is read off the emitted
# `rating`. The mean readout is the consensus estimator, a different object, and is not computed
# here.
#
# Source of cells: data/output/runs/<runs-subdir>/. For 2019 that is `expectation` — the only
# directory that carries every Fig-1 cell (Llama base+FT, Qwen/Gemma FT-raw) in one place; the
# greedy `rating` lives in those files alongside `rating_dist`, which is ignored here. Qwen/Gemma
# BASE cells are pending reruns, so Fig 2's base block shows Llama until they land (== Fig 1).
#
# Faithfulness: the point estimates reproduce QMD 07's dm_slope exactly (a cell's slope uses only
# that cell's rows on the all-ones apparent draw), and the CIs match when the country universe is
# the same. `--verify` checks the seven Llama cells against the live distmatch_2019.rds.
#
# Usage — from the project root:
#   Rscript helpers/build_distmatch.R                    # 2019 (reads runs/expectation)
#   Rscript helpers/build_distmatch.R --year 2023 --runs-subdir 2023
#   Rscript helpers/build_distmatch.R --verify           # rebuild 2019 & diff Llama cells
# or interactively:
#   source("helpers/build_distmatch.R"); build_distmatch_bundle(proj_root, year = 2019)

suppressPackageStartupMessages({
  library(tidyverse)
  library(glue)
})

find_panel_member_root <- function() {
  up <- tryCatch(rprojroot::find_root(rprojroot::is_git_root), error = function(e) NA_character_)
  if (!is.na(up)) return(up)
  down <- file.path(getwd(), "panel-member")
  if (dir.exists(file.path(down, ".git"))) return(down)
  stop("Could not locate the panel-member project root from working dir: ", getwd())
}

build_distmatch_bundle <- function(proj_root,
                                   year        = 2019,
                                   runs_subdir = "expectation",
                                   n_boot      = 2000,
                                   min_coders  = 2,
                                   seed        = 42,
                                   out_dir     = file.path(proj_root, "data", "derived"),
                                   write       = TRUE) {
  source(file.path(proj_root, "helpers", "bootstrap_helpers.R"), local = TRUE)
  data_dir <- file.path(proj_root, "data", "processed")
  runs_dir <- file.path(proj_root, "data", "output", "runs", runs_subdir)
  if (!dir.exists(runs_dir)) stop("runs dir not found: ", runs_dir)

  # scalar greedy fields only; tolerate (and drop) the nested rating_dist blob these files carry
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

  # ── human per-coder LOO error e_ic and per-cell difficulty h_c (== QMD 07 §3) ──
  human_e <- human_ratings |>
    filter(year == !!year) |>
    group_by(country_text_id, year, indicator) |>
    filter(n() >= min_coders) |>
    mutate(loo_mean = (sum(rating) - rating) / (n() - 1),
           e        = abs(rating - loo_mean)) |>
    ungroup() |>
    select(country_text_id, year, indicator, coder_id, e)
  human_h <- human_e |>
    group_by(country_text_id, year, indicator) |>
    summarise(h = mean(e), .groups = "drop")

  # ── AI greedy error a_c, restricted to CYIs carrying a human floor ──
  ai <- ai_raw |>
    filter(year == !!year) |>
    rename(country_text_id = country) |>
    inner_join(select(panel_means, country_text_id, year, indicator, raw_mean),
               by = c("country_text_id", "year", "indicator")) |>
    inner_join(human_h, by = c("country_text_id", "year", "indicator")) |>
    mutate(a = abs(rating - raw_mean), cell = paste(model_key, condition, sep = "|"))

  # ── shared CYI index + country-clustered draws (seed 42; == QMD 07 §3–§4) ──
  cyi_pool <- ai |> distinct(country_text_id, year, indicator, h) |>
    mutate(cyi = row_number(), k = paste(country_text_id, indicator))
  ai <- ai |>
    mutate(k = paste(country_text_id, indicator),
           cyi = cyi_pool$cyi[match(k, cyi_pool$k)]) |>
    filter(!is.na(cyi), !is.na(h), !is.na(a))

  cell_lv   <- sort(unique(ai$cell))
  ai_cell_i <- as.integer(factor(ai$cell, levels = cell_lv))
  ncell     <- length(cell_lv)

  W <- country_boot_weights(cyi_pool$country_text_id, n_boot, seed = seed)
  draw_id <- colnames(W)

  # scatter a rowsum() result (rownames = group id) into a fixed-length vector (== QMD 07)
  scatter <- function(tab, len) { v <- numeric(len); v[as.integer(rownames(tab))] <- tab; v }

  # per draw: weighted OLS slope of a on h, per cell, closed form (== QMD 07 Test-3 block)
  ah <- ai$h; aa <- ai$a
  slope_of_draw <- function(draw) {
    w_by_cyi <- unname(W[, draw][cyi_pool$country_text_id])
    w   <- w_by_cyi[ai$cyi]
    sw   <- scatter(rowsum(w,           ai_cell_i, reorder = FALSE), ncell)
    swh  <- scatter(rowsum(w * ah,      ai_cell_i, reorder = FALSE), ncell)
    swa  <- scatter(rowsum(w * aa,      ai_cell_i, reorder = FALSE), ncell)
    swhh <- scatter(rowsum(w * ah^2,    ai_cell_i, reorder = FALSE), ncell)
    swha <- scatter(rowsum(w * ah * aa, ai_cell_i, reorder = FALSE), ncell)
    (swha - swh * swa / sw) / (swhh - swh * swh / sw)
  }
  slope_draws <- do.call(rbind, map(draw_id, slope_of_draw))
  colnames(slope_draws) <- cell_lv

  app  <- which(draw_id == "Apparent")
  boot <- setdiff(seq_len(nrow(slope_draws)), app)
  dm_slope <- tibble(
    cell      = cell_lv,
    model_key = sub("\\|.*$", "", cell_lv),
    condition = sub("^[^|]*\\|", "", cell_lv),
    est = slope_draws[app, ],
    lo  = apply(slope_draws[boot, , drop = FALSE], 2, quantile, 0.025),
    hi  = apply(slope_draws[boot, , drop = FALSE], 2, quantile, 0.975)
  )

  # ── fine difficulty curves (mean error vs h_c, 20 equal-count bins) ──────────
  # The illustrative "slope as a shape" panel: per cell, mean AI error in each difficulty bin,
  # plus the human reference curve (which lies on y = x by construction). Cross-model, shared
  # bins. Same country-clustered draws (reuse W) as the slope, so CIs are consistent.
  NF  <- 20L
  # equal-count difficulty bins by rank — robust to ties in h (which break quantile-cut on pools
  # with many repeated difficulty values, e.g. the 2023 holdout); each bin holds ~1/NF of the CYIs.
  cyi_pool$binf <- pmin(ceiling(rank(cyi_pool$h, ties.method = "first") / nrow(cyi_pool) * NF), NF)
  xbin    <- as.numeric(tapply(cyi_pool$h, cyi_pool$binf, mean))   # mean h per bin (x position)
  ai_binf <- cyi_pool$binf[ai$cyi]

  # human per-coder errors mapped to the shared CYI index + bin (for the y = x reference curve)
  he <- human_e |>
    dplyr::mutate(k = paste(country_text_id, indicator),
                  cyi = cyi_pool$cyi[match(k, cyi_pool$k)]) |>
    dplyr::filter(!is.na(cyi))
  he$binf <- cyi_pool$binf[he$cyi]

  scf  <- function(tab, len) { v <- rep(NA_real_, len); v[as.integer(rownames(tab))] <- tab; v }
  g_ai <- (ai_cell_i - 1L) * NF + ai_binf
  he_e <- he$e; he_bin <- he$binf; he_cyi <- he$cyi
  fine_of_draw <- function(draw) {
    w_by_cyi <- unname(W[, draw][cyi_pool$country_text_id])
    w_ai <- w_by_cyi[ai$cyi]; w_he <- w_by_cyi[he_cyi]
    aim <- scf(rowsum(w_ai * aa, g_ai, reorder = FALSE), ncell * NF) /
           scf(rowsum(w_ai,      g_ai, reorder = FALSE), ncell * NF)
    hem <- scf(rowsum(w_he * he_e, he_bin, reorder = FALSE), NF) /
           scf(rowsum(w_he,        he_bin, reorder = FALSE), NF)
    c(aim, hem)
  }
  Mf   <- do.call(rbind, map(draw_id, fine_of_draw))
  estf <- Mf[app, ]
  lof  <- apply(Mf[boot, , drop = FALSE], 2, quantile, 0.025, na.rm = TRUE)
  hif  <- apply(Mf[boot, , drop = FALSE], 2, quantile, 0.975, na.rm = TRUE)

  dm_fine <- tibble(
    cell      = rep(cell_lv, each = NF),
    model_key = sub("\\|.*$", "", rep(cell_lv, each = NF)),
    condition = sub("^[^|]*\\|", "", rep(cell_lv, each = NF)),
    bin = rep(1:NF, ncell), x = xbin[rep(1:NF, ncell)],
    est = estf[1:(ncell * NF)], lo = lof[1:(ncell * NF)], hi = hif[1:(ncell * NF)]
  )
  he_fine <- tibble(bin = 1:NF, x = xbin,
                    est = estf[ncell * NF + 1:NF],
                    lo  = lof[ncell * NF + 1:NF],
                    hi  = hif[ncell * NF + 1:NF])

  sesoi <- tryCatch(readRDS(file.path(out_dir, glue("bootstrap_{year}.rds")))$sesoi,
                    error = function(e) NA_real_)

  bundle <- list(
    dm_slope    = dm_slope,      # per-cell difficulty-tracking slope + 95% CI
    slope_draws = slope_draws,   # [draw x cell] — for paired cell-vs-cell deltas
    dm_fine     = dm_fine,       # per-cell mean error vs h_c (20 bins) + CI — the curve panel
    he_fine     = he_fine,       # human reference curve (≈ y = x) + CI
    draw_id     = draw_id,
    cell_lv     = cell_lv,
    n_boot      = n_boot,
    sesoi       = sesoi          # carried for continuity (slope is dimensionless; not banded)
  )
  if (write) {
    dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
    # NB: distinct from analysis/07's Llama-only distmatch_{year}.rds (rich: W1, strata, curves).
    # This is the cross-model slope bundle the paper's Fig 2 reads; keep the names separate so a
    # rebuild here never clobbers QMD 07's frozen archive.
    path <- file.path(out_dir, glue("distmatch_slope_{year}.rds"))
    saveRDS(bundle, path)
    message(glue("distmatch bundle written: {path} ({round(file.size(path)/1024)} KB) · ",
                 "{ncell} cells"))
  }
  invisible(bundle)
}

# ── CLI ──────────────────────────────────────────────────────────────────────
parse_args <- function(a) {
  out <- list(year = 2019, runs_subdir = "expectation", n_boot = 2000, verify = FALSE)
  i <- 1
  while (i <= length(a)) {
    switch(a[[i]],
      "--year"        = { out$year        <- as.integer(a[[i + 1]]); i <- i + 2 },
      "--runs-subdir" = { out$runs_subdir <- a[[i + 1]];             i <- i + 2 },
      "--n-boot"      = { out$n_boot      <- as.integer(a[[i + 1]]); i <- i + 2 },
      "--verify"      = { out$verify      <- TRUE;                   i <- i + 1 },
      stop("unknown arg: ", a[[i]])
    )
  }
  out
}

# Rebuild 2019 and check the seven Llama cells against the live distmatch_2019.rds (QMD 07's
# dm_slope, whose labels are the short Base:Cb … names). Point estimates must match; CIs match
# when the country universe is unchanged.
verify_2019 <- function(proj_root) {
  live <- readRDS(file.path(proj_root, "data", "derived", "distmatch_2019.rds"))$dm_slope
  new  <- build_distmatch_bundle(proj_root, year = 2019, write = FALSE)$dm_slope
  key <- tibble::tribble(
    ~cell,                                    ~lbl,
    "llama-70b|codebook",                     "Base:Cb",
    "llama-70b|evidence",                     "Base:Ev",
    "llama-70b|anonymized",                   "Base:An",
    "llama-70b|summarized",                   "Base:Su",
    "llama-70b-ft-raw|evidence-zeroshot",     "FT-raw:Ev",
    "llama-70b-ft-anon|anonymized-zeroshot",  "FT-anon:An",
    "llama-70b-ft-summ|summarized-zeroshot",  "FT-summ:Su"
  )
  cmp <- key |>
    dplyr::left_join(dplyr::select(new, cell, n_est = est, n_lo = lo, n_hi = hi), by = "cell") |>
    dplyr::left_join(dplyr::select(live, lbl = cell, l_est = est, l_lo = lo, l_hi = hi),
                     by = "lbl") |>
    dplyr::mutate(d_est = abs(n_est - l_est),
                  d_ci  = pmax(abs(n_lo - l_lo), abs(n_hi - l_hi)))
  print(dplyr::transmute(cmp, lbl, new_slope = round(n_est, 4), live_slope = round(l_est, 4),
                         d_est = signif(d_est, 3), d_ci = signif(d_ci, 3)))
  message(if (max(cmp$d_est) < 1e-9) "point estimates: MATCH (< 1e-9)"
          else glue("point estimates DIFFER (max {signif(max(cmp$d_est),3)})"))
  message(if (max(cmp$d_ci) < 1e-9) "CIs: MATCH (< 1e-9)"
          else glue("CIs differ by up to {signif(max(cmp$d_ci),3)} (country universe differs — expected if Qwen/Gemma add countries)"))
}

if (sys.nframe() == 0) {
  opt <- parse_args(commandArgs(trailingOnly = TRUE))
  proj_root <- find_panel_member_root()
  if (opt$verify) verify_2019(proj_root)
  else build_distmatch_bundle(proj_root, year = opt$year, runs_subdir = opt$runs_subdir,
                              n_boot = opt$n_boot)
}
