# build_temperature_ladder.R — Appendix A9. What a SAMPLED rating would do to the three outcomes,
# function of decoding temperature, for the fine-tuned models on 2023.
#
# NO NEW INFERENCE. Every rating in the study was produced at temperature 0 (greedy), but
# code_country_year.py also stored `rating_dist` — the model's full probability distribution over
# the five rating categories, i.e. the T=1 softmax. Temperature scaling is a closed-form reweighting
# of that stored distribution, q_T(y) ∝ p(y)^(1/T), so the EXPECTED behaviour of a sampled coder at
# any T is computable exactly rather than simulated:
#
#   expected MAE at T        E_q|Y - m|        = sum_y q(y)|y - m|
#   expected signed dev at T E_q[Y] - m        = sum_y q(y)y - m
#   expected slope at T      OLS is linear in the outcome, so regressing E_q|Y-m| on case
#                            difficulty h IS the expected sampled slope, not an approximation.
#
# T = 0 is the greedy mode actually used in the paper and is handled separately (argmax).
#
# Case difficulty h_c = within-cell human leave-one-out MAE, >= 2 coders, identical to
# helpers/build_distmatch.R. Human references: MAE 0.725, slope 1.00, signed deviation 0.00.
#
# Bootstrap is country-clustered via country_boot_weights(), matching every other figure.
#
# Writes temperature-ladder.rds; plotted by temperature-ladder-mockup.R.

suppressPackageStartupMessages({ library(tidyverse); library(jsonlite) })

proj_root <- rprojroot::find_root(rprojroot::is_git_root)
out_dir   <- file.path(proj_root, "data", "derived")
source(file.path(proj_root, "helpers", "bootstrap_helpers.R"))

YEAR    <- 2023
TEMPS   <- c(0, seq(0.1, 1.0, by = 0.1))
N_BOOT  <- 200
CONDS   <- c("codebook", "evidence-zeroshot")

# ── case difficulty h_c (human LOO MAE within cell) ──────────────────────────
human_h <- read_csv(file.path(proj_root, "data", "processed", "human_ratings.csv"),
                    show_col_types = FALSE) |>
  filter(year == YEAR) |>
  group_by(country_text_id, year, indicator) |>
  filter(n() >= 2) |>
  mutate(loo_mean = (sum(rating) - rating) / (n() - 1), e = abs(rating - loo_mean)) |>
  summarise(h = mean(e), .groups = "drop")

panel_means <- read_csv(file.path(proj_root, "data", "processed", "panel_means.csv"),
                        show_col_types = FALSE) |>
  select(country_text_id, year, indicator, raw_mean)

# ── read the fine-tuned runs, keeping the stored distribution ────────────────
run_files <- list.files(file.path(proj_root, "data", "output", "runs", as.character(YEAR)),
                        pattern = "^ft_.*\\.jsonl$", full.names = TRUE)
read_run <- function(f) {
  df <- stream_in(file(f), verbose = FALSE)
  d  <- df[["rating_dist"]]
  df[["rating_dist"]] <- if (is.matrix(d)) asplit(d, 1) else as.list(d)
  as_tibble(df) |>
    select(country, year, indicator, condition, model_key, rating, rating_dist, raw_mean)
}
ai <- run_files |> map(read_run) |> bind_rows() |>
  filter(condition %in% CONDS) |>
  mutate(model_key = str_remove(model_key, "-local$")) |>
  rename(country_text_id = country) |>
  select(-raw_mean) |>
  inner_join(panel_means, by = c("country_text_id", "year", "indicator")) |>
  inner_join(human_h,     by = c("country_text_id", "year", "indicator")) |>
  # rating_dist length = number of categories for that INDICATOR, which varies (not always 5),
  # so keep every row whose stored distribution is a valid simplex and group by length below.
  filter(map_lgl(rating_dist, ~ length(.x) >= 2 && abs(sum(.x) - 1) < 0.05))

stopifnot(nrow(ai) > 0)

# ── temperature-scaled outcomes, one column per T ────────────────────────────
scale_temp <- function(p, T) {
  if (T == 0) { q <- numeric(length(p)); q[which.max(p)] <- 1; return(q) }
  lp <- log(pmax(p, 1e-12)) / T
  e  <- exp(lp - max(lp))
  e / sum(e)
}

cells <- ai |> distinct(model_key, condition)
W_all <- country_boot_weights(ai$country_text_id, N_BOOT)

out <- pmap_dfr(cells, function(model_key, condition) {
  d  <- ai |> filter(model_key == !!model_key, condition == !!condition)
  rm <- d$raw_mean; h <- d$h
  nc <- lengths(d$rating_dist)

  # A[, k] = expected |Y - m| at TEMPS[k];  S[, k] = expected Y - m.
  # Indicators differ in how many categories they have, so the stored distributions are ragged;
  # block by length and do each block as a matrix.
  A <- matrix(0, nrow(d), length(TEMPS)); S <- A
  for (L in sort(unique(nc))) {
    idx <- which(nc == L)
    P   <- do.call(rbind, d$rating_dist[idx])
    ys  <- seq_len(L) - 1
    D   <- abs(outer(rm[idx], ys, function(a, b) b - a))
    for (k in seq_along(TEMPS)) {
      Q <- t(apply(P, 1, scale_temp, T = TEMPS[k]))
      A[idx, k] <- rowSums(Q * D)
      S[idx, k] <- as.vector(Q %*% ys) - rm[idx]
    }
  }

  W  <- W_all[d$country_text_id, , drop = FALSE]      # n x (N_BOOT+1)
  sw <- colSums(W)
  mA <- crossprod(W, A) / sw; mS <- crossprod(W, S) / sw
  mH <- as.vector(crossprod(W, h) / sw)
  # weighted OLS slope of A on h, per draw and temperature
  num <- crossprod(W, h * A) / sw - mH * mA
  den <- as.vector(crossprod(W, h^2) / sw) - mH^2
  SL  <- num / den

  q <- function(M) tibble(
    est = M[1, ],
    lo  = apply(M[-1, , drop = FALSE], 2, quantile, 0.025),
    hi  = apply(M[-1, , drop = FALSE], 2, quantile, 0.975))

  bind_rows(
    q(mA) |> mutate(outcome = "MAE"),
    q(SL) |> mutate(outcome = "Difficulty slope"),
    q(mS) |> mutate(outcome = "Signed deviation")
  ) |> mutate(temp = rep(TEMPS, 3), model_key = model_key, condition = condition, n = nrow(d))
})

saveRDS(list(ladder = out, temps = TEMPS, n_boot = N_BOOT, year = YEAR,
             refs = c(MAE = 0.725, `Difficulty slope` = 1, `Signed deviation` = 0)),
        file.path(out_dir, paste0("temperature_ladder_", YEAR, ".rds")))
cat("wrote temperature_ladder bundle —", nrow(out), "rows\n")
