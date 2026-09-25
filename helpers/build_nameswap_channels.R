# build_nameswap_channels.R — Figure 7's two channels, 2023.
#
# Replaces build_nameswap_rescaled.R as Figure 7's source (2026-09-24). The position / win-rate
# pair it produced is retained in notes/mockups/nameswap-rescaled.* and documented in
# nameswap-rescaled-concept.md; the registered R4 raw-track metric is in build_priorreliance.R
# --panel B. Neither is rendered in the paper any more.
#
# PANEL A — cue. The within-item paired contrast the two name-swap arms were run for:
#
#     cue = rating_swapped - rating_correct
#
# The same de-identified evidence, same indicator, same model, rated twice; the only difference is
# whether the framing named the true country or a different one. No panel means enter, so it
# carries none of the oracle/coder ambiguity the track-family metrics inherit, and it is on the
# RATING-POINT scale, so the SESOI band applies. Both arms come from the same SLURM job
# (ARMS default "swapped correct"), matched row for row.
#
#     mean |cue|   average absolute move, rating points        <- plotted
#     flip rate    P(cue != 0); ratings are integers, so this is P(|cue| >= 1)
#
# PANEL B — channel share. Within the swapped arm only:
#
#     swapped_rating ~ named_mean + source_mean     (demeaned within indicator)
#     share = b_source / (b_source + b_named)
#
# The true country's name appears nowhere in a swapped prompt, so b_source can only be non-zero if
# the model is extracting country-specific information from the text. 0.50 = the two channels pull
# equally. The share is recomputed INSIDE each bootstrap draw, since a ratio of two estimates
# cannot have its interval built from the two marginal CIs.
#
# SALIENCE SPLIT. Both panels split on re-identification of that country-indicator's de-identified
# text, using the BASE model's result for both weight states -- the fixed salience partition
# documented in build_prominence.R (2026-09-06, also used for R5/A8), so Base and Fine-Tuned rows
# split identical items. build_prominence.R designates summarized-text re-id as the project's
# primary prominence measure.
#
# Also emitted: paired within-draw tests of the re-identified minus not-re-identified difference
# on all three quantities, for the appendix. Both strata use the SAME country weights in each
# draw, so the shared-country covariance is preserved rather than being treated as two
# independent samples.
#
# Country-clustered bootstrap on the source country, 2000 draws, seed 42.
#
# Usage: Rscript helpers/build_nameswap_channels.R

suppressPackageStartupMessages({ library(tidyverse); library(glue); library(jsonlite) })

proj_root <- rprojroot::find_root(rprojroot::is_git_root)
source(file.path(proj_root, "helpers", "bootstrap_helpers.R"))
year <- 2023L; n_boot <- 2000L; seed <- 42L
ns_dir <- file.path(proj_root, "data", "output", "nameswap")

pm <- read_csv(file.path(proj_root, "data", "processed", "panel_means.csv"), show_col_types = FALSE)
rd <- function(f, cols) { con <- file(f, "r"); on.exit(close(con))
  stream_in(con, verbose = FALSE) |> as_tibble() |> select(all_of(cols)) }
load_arm <- function(pat, nm) {
  list.files(ns_dir, pattern = pat, full.names = TRUE) |>
    map(\(f) rd(f, c("source","named","year","indicator","model_key","rating"))) |> bind_rows() |>
    mutate(model_key = str_remove(model_key, "-local$")) |> filter(year == !!year) |>
    rename(!!nm := rating)
}

sw <- load_arm("^nameswap_swapped_.*\\.jsonl$", "r_sw") |> rename(named_iso = named)
co <- load_arm("^nameswap_correct_.*\\.jsonl$", "r_cor") |>
  select(source, indicator, model_key, r_cor)

d <- sw |>
  inner_join(co, by = c("source", "indicator", "model_key")) |>
  inner_join(select(pm, source = country_text_id, year, indicator, source_mean = raw_mean),
             by = c("source", "year", "indicator")) |>
  inner_join(select(pm, named_iso = country_text_id, year, indicator, named_mean = raw_mean),
             by = c("named_iso", "year", "indicator")) |>
  mutate(cue = r_sw - r_cor) |>
  drop_na(cue, source_mean, named_mean)

reid_prefix <- c("Llama 70B" = "reid_base", "Qwen 72B" = "reid_qwen-base",
                 "Gemma 27B" = "reid_gemma-base")
read_reid <- function(prefix) {
  f <- file.path(proj_root, "data", "output", "reid", glue("{prefix}_summ_{year}.jsonl"))
  con <- file(f, "r"); on.exit(close(con))
  suppressWarnings(stream_in(con, verbose = FALSE)) |> as_tibble() |>
    select(iso, indicator, correct_top1) |> mutate(.r = row_number()) |>
    group_by(iso, indicator) |> slice_max(.r, n = 1, with_ties = FALSE) |> ungroup() |>
    transmute(source = iso, indicator, reid = as.numeric(correct_top1))
}

cells <- tribble(~model, ~block, ~model_key,
  "Llama 70B","Base","llama-70b", "Qwen 72B","Base","qwen-72b", "Gemma 27B","Base","gemma-27b",
  "Llama 70B","Fine-Tuned","llama-70b-ft-raw",
  "Qwen 72B", "Fine-Tuned","qwen-72b-ft-raw",
  "Gemma 27B","Fine-Tuned","gemma-27b-ft-raw")

wls <- function(y, X, w) { XtW <- t(X * w); as.numeric(solve(XtW %*% X, XtW %*% y)) }

fit_cell <- function(model, block, model_key) {
  mk <- model_key
  dd <- filter(d, .data$model_key == mk) |>
    inner_join(read_reid(reid_prefix[[model]]), by = c("source", "indicator")) |>
    group_by(indicator) |>
    mutate(dm_sw = r_sw - mean(r_sw),
           dm_nm = named_mean - mean(named_mean),
           dm_sm = source_mean - mean(source_mean)) |> ungroup()

  W <- country_boot_weights(dd$source, n_boot, seed = seed)
  app <- which(colnames(W) == "Apparent"); bt <- setdiff(seq_len(ncol(W)), app)
  i1 <- dd$reid == 1; i0 <- dd$reid == 0

  stats_for <- function(idx, w) {
    ww <- w[idx]; s <- sum(ww)
    b <- wls(dd$dm_sw[idx], cbind(1, dm_nm = dd$dm_nm[idx], dm_sm = dd$dm_sm[idx]), ww)
    den <- b[2] + b[3]
    c(shift = sum(ww * abs(dd$cue[idx])) / s,
      flip  = sum(ww * (dd$cue[idx] != 0)) / s,
      share = if (den <= 0) NA_real_ else b[3] / den)
  }

  # The `all` rows are the pooled values Section 7's prose quotes; without them the paper would
  # cite numbers that cannot be recovered from this bundle.
  ia <- rep(TRUE, nrow(dd))
  D <- vapply(colnames(W), function(dr) {
    w <- unname(W[, dr][dd$source])
    sa <- stats_for(ia, w); s1 <- stats_for(i1, w); s0 <- stats_for(i0, w)
    c(all_shift  = sa[["shift"]], all_flip  = sa[["flip"]], all_share  = sa[["share"]],
      reid_shift = s1[["shift"]], reid_flip = s1[["flip"]], reid_share = s1[["share"]],
      not_shift  = s0[["shift"]], not_flip  = s0[["flip"]], not_share  = s0[["share"]],
      d_shift = s1[["shift"]] - s0[["shift"]],
      d_flip  = s1[["flip"]]  - s0[["flip"]],
      d_share = s1[["share"]] - s0[["share"]])
  }, numeric(12))

  ci <- function(k) { v <- D[k, bt]; v <- v[is.finite(v)]
    tibble(key = k, est = D[k, app], lo = quantile(v, .025), hi = quantile(v, .975),
           p = 2 * min(mean(v <= 0), mean(v >= 0))) }
  map_dfr(rownames(D), ci) |>
    mutate(model = model, block = block, n_reid = sum(i1), n_not = sum(i0))
}

raw <- cells |> pmap_dfr(fit_cell) |>
  separate(key, into = c("grp", "metric"), sep = "_") |>
  mutate(block = factor(block, levels = c("Base", "Fine-Tuned")),
         metric = recode(metric, shift = "Mean |shift|", flip = "Flip rate",
                         share = "Text's share"))

effects <- raw |> filter(grp != "d") |>
  mutate(stratum = recode(grp, all = "All swaps", reid = "Re-identified", not = "Not re-identified")) |>
  select(metric, stratum, model, block, est, lo, hi, n_reid, n_not)

tests <- raw |> filter(grp == "d") |>
  select(metric, model, block, est, lo, hi, p, n_reid, n_not) |>
  mutate(sig = if_else(lo > 0 | hi < 0, "*", ""))

out <- file.path(proj_root, "data", "derived", glue("nameswapchannels_{year}.rds"))
saveRDS(list(effects = effects, tests = tests, year = year, n_boot = n_boot,
             n_matched = nrow(d)), out)

cat("matched swapped/correct rows:", nrow(d), "\n\n")
for (m in c("Mean |shift|", "Flip rate", "Text's share")) {
  cat("===", m, "===\n")
  effects |> filter(metric == m) |>
    mutate(v = sprintf("%.3f [%.3f, %.3f]", est, lo, hi)) |>
    select(model, block, stratum, v) |>
    pivot_wider(names_from = stratum, values_from = v) |> as.data.frame() |>
    print(row.names = FALSE)
  cat("\n")
}
cat("=== paired differences (re-identified - not) ===\n")
tests |> mutate(v = sprintf("%+.3f [%+.3f, %+.3f]%s", est, lo, hi, sig), p = round(p, 3)) |>
  select(metric, model, block, v, p) |> as.data.frame() |> print(row.names = FALSE)
message("\nname-swap channels bundle written: ", out)
