# build_nameswap_rescaled.R — the name-swap tracking metric on its achievable range, 2023.
#
# build_priorreliance.R --panel B reports the raw metric
#   track = |rating - named_mean| - |rating - source_mean|
# in rating points (base +0.070 / +0.062 / +0.057), which reads as a negligible effect. But the
# metric is BOUNDED by how far apart the two countries actually are: track lies in [-gap, +gap]
# where gap = |named_mean - source_mean|. The mean gap is 0.698 and the median 0.500, so a +0.06
# estimate is ~9% of the available range, not a small deviation from "tracks content". Rescaling
# is what makes the figure readable; see notes/mockups/nameswap-rescaled-concept.md.
#
# Two rescalings, both restricted to swaps where the two countries meaningfully differ
# (gap >= 0.5, retaining 53% of rows; 6.8% of swaps have gap == 0 exactly, where the metric is
# degenerate):
#
#   position  = mean(track / gap), in [-1, +1]
#                 +1 = rating is at or PAST the TRUE country's panel mean
#                  0 = rating sits midway between the two
#                 -1 = rating is at or PAST the INJECTED country's panel mean
#   win rate  = share of swaps where the rating is strictly closer to the true country's mean
#                 0.50 = coin flip
#
# The win rate is reported alongside because the per-case position is strongly bimodal (25th
# percentile -1.00, median -0.06, 75th percentile +1.00): on an individual swap the model commits
# to one country's answer or the other, so the near-zero average is an even split rather than a
# consistent midpoint. Country-clustered bootstrap on the SOURCE country, 2000 draws, seed 42.

suppressPackageStartupMessages({ library(tidyverse); library(glue); library(jsonlite) })

proj_root <- rprojroot::find_root(rprojroot::is_git_root)
source(file.path(proj_root, "helpers", "bootstrap_helpers.R"))
year <- 2023L; n_boot <- 2000L; seed <- 42L; gap_min <- 0.5

model_families <- tribble(~model, ~base_key, ~ft_key,
  "Llama 70B", "llama-70b", "llama-70b-ft-raw",
  "Qwen 72B",  "qwen-72b",  "qwen-72b-ft-raw",
  "Gemma 27B", "gemma-27b", "gemma-27b-ft-raw")

pm <- read_csv(file.path(proj_root, "data", "processed", "panel_means.csv"), show_col_types = FALSE)
fs <- list.files(file.path(proj_root, "data", "output", "nameswap"),
                 pattern = "^nameswap_swapped_.*\\.jsonl$", full.names = TRUE)
rd <- function(f) { con <- file(f, "r"); on.exit(close(con))
  stream_in(con, verbose = FALSE) |> as_tibble() |>
    select(source, named, year, indicator, model_key, rating) }

ns <- fs |> map(rd) |> bind_rows() |>
  mutate(model_key = str_remove(model_key, "-local$")) |> filter(year == !!year) |>
  inner_join(select(pm, source = country_text_id, year, indicator, source_mean = raw_mean),
             by = c("source", "year", "indicator")) |>
  inner_join(select(pm, named = country_text_id, year, indicator, named_mean = raw_mean),
             by = c("named", "year", "indicator")) |>
  mutate(gap   = abs(named_mean - source_mean),
         track = abs(rating - named_mean) - abs(rating - source_mean))

gap_mean_all   <- mean(ns$gap, na.rm = TRUE)
retained_share <- mean(ns$gap >= gap_min, na.rm = TRUE)

ns <- ns |> filter(!is.na(track), gap >= gap_min) |>
  mutate(position = track / gap, win = as.numeric(track > 0))

fit_cell <- function(mk, model, block) {
  d <- filter(ns, model_key == mk)
  W <- country_boot_weights(d$source, n_boot, seed = seed)
  app <- which(colnames(W) == "Apparent"); bt <- setdiff(seq_len(ncol(W)), app)
  D <- vapply(colnames(W), function(dr) {
    w <- unname(W[, dr][d$source]); sw <- sum(w)
    c(position = sum(w * d$position)/sw, win = sum(w * d$win)/sw)
  }, numeric(2))
  map_dfr(c("position", "win"), \(m)
    tibble(metric = m, est = D[m, app],
           lo = quantile(D[m, bt], .025), hi = quantile(D[m, bt], .975))) |>
    mutate(model = model, block = block, n = nrow(d))
}

effects <- model_families |>
  pmap_dfr(function(model, base_key, ft_key) bind_rows(
    fit_cell(base_key, model, "Base"), fit_cell(ft_key, model, "Fine-Tuned"))) |>
  mutate(block = factor(block, levels = c("Base", "Fine-Tuned")))

out <- file.path(proj_root, "data", "derived", glue("nameswaprescaled_{year}.rds"))
saveRDS(list(effects = effects, year = year, n_boot = n_boot, gap_min = gap_min,
             gap_mean_all = gap_mean_all, retained_share = retained_share), out)
print(as.data.frame(effects), row.names = FALSE, digits = 3)
message("name-swap rescaled bundle written: ", out, " · ", nrow(effects), " rows")
