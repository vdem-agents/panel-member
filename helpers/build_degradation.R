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
# build_degradation.R — Figure 8, Panel B. Does replacing one human coder with the AI
# on a healthy 2023 panel (n>=9, matching the panel-degradation pathologies analysis's
# own pool split) shift the panel mean? Panel size held FIXED — models attrition: a
# healthy panel loses a coder and an AI fills the seat, rather than a thin panel
# getting help (that's build_augmentation.R's Panel A). Every coder-in-panel is used as
# the swapped-out seat (not one arbitrary pick), pooled into the bootstrap. Promoted
# from notes/mockups/degradation-swap-mockup.R — see notes/mockups/
# augmentation-concept.md for the full design history.
#
# Outcome: signed shift = (ai_rating - coder's rating) / n_coders, country-clustered
# bootstrap mean per model x condition. No SESOI band, same reasoning as
# build_augmentation.R — a difference of two integers over panel size has no forced-
# rounding floor.
#
# Usage:
#   Rscript helpers/build_degradation.R

suppressPackageStartupMessages({ library(tidyverse); library(glue); library(jsonlite) })

find_panel_member_root <- function() {
  up <- tryCatch(rprojroot::find_root(rprojroot::is_git_root), error = function(e) NA_character_)
  if (!is.na(up)) return(up)
  down <- file.path(getwd(), "panel-member")
  if (dir.exists(file.path(down, ".git"))) return(down)
  stop("Could not locate the panel-member project root from working dir: ", getwd())
}

model_families <- tribble(
  ~family,  ~model,       ~base_key,    ~ft_key,
  "llama",  "Llama 70B",  "llama-70b",  "llama-70b-ft-raw",
  "qwen",   "Qwen 72B",   "qwen-72b",   "qwen-72b-ft-raw",
  "gemma",  "Gemma 27B",  "gemma-27b",  "gemma-27b-ft-raw",
)
# Bottom-to-top factor order (Figures 6-7's convention), same as build_augmentation.R.
conditions_base <- c(Summarized = "summarized", Anonymized = "anonymized",
                     `Raw Text` = "evidence", Codebook = "codebook")
conditions_ft   <- c(`Raw Text` = "evidence-zeroshot", Codebook = "codebook")

build_degradation <- function(proj_root,
                              year        = 2023,
                              min_coders  = 9L,   # "healthy" panel
                              n_boot      = 2000,
                              seed        = 42,
                              out_dir     = file.path(proj_root, "data", "derived"),
                              write       = TRUE) {
  source(file.path(proj_root, "helpers", "bootstrap_helpers.R"), local = TRUE)
  data_dir <- file.path(proj_root, "data", "processed")
  runs_dir <- file.path(proj_root, "data", "output", "runs", as.character(year))

  panel_means   <- read_csv(file.path(data_dir, "panel_means.csv"),   show_col_types = FALSE)
  human_ratings <- read_csv(file.path(data_dir, "human_ratings.csv"), show_col_types = FALSE)

  healthy_pool <- panel_means |>
    filter(year == !!year, n_coders >= min_coders) |>
    select(country_text_id, year, indicator, n_coders)

  healthy_ratings <- human_ratings |>
    filter(year == !!year) |>
    inner_join(healthy_pool, by = c("country_text_id", "year", "indicator"))

  needed_cols <- c("country", "year", "indicator", "condition", "model_key", "rating")
  read_run <- function(f) {
    con <- file(f, "r"); on.exit(close(con))
    stream_in(con, verbose = FALSE) |> as_tibble() |> select(all_of(needed_cols))
  }
  run_files <- list.files(runs_dir, pattern = "\\.jsonl$", full.names = TRUE)
  if (length(run_files) == 0) stop("No .jsonl files in ", runs_dir)

  ai <- run_files |> map(read_run) |> bind_rows() |>
    mutate(model_key = str_remove(model_key, "-local$")) |>
    filter(year == !!year) |> rename(country_text_id = country, ai_rating = rating) |>
    inner_join(healthy_pool, by = c("country_text_id", "year", "indicator"))

  swap_divergence <- ai |>
    select(country_text_id, year, indicator, model_key, condition, ai_rating, n_coders) |>
    inner_join(healthy_ratings |> select(country_text_id, year, indicator, coder_id, rating),
               by = c("country_text_id", "year", "indicator"), relationship = "many-to-many") |>
    mutate(divergence = (ai_rating - rating) / n_coders)

  boot_divergence <- function(mk, cond_value) {
    d <- filter(swap_divergence, model_key == mk, condition == cond_value)
    if (nrow(d) == 0) return(NULL)
    W <- country_boot_weights(d$country_text_id, n_boot, seed = seed)
    draws <- vapply(colnames(W), function(draw) {
      w <- unname(W[, draw][d$country_text_id])
      weighted.mean(d$divergence, w)
    }, numeric(1))
    app  <- which(names(draws) == "Apparent")
    boot <- setdiff(seq_along(draws), app)
    tibble(est = draws[app], lo = quantile(draws[boot], 0.025), hi = quantile(draws[boot], 0.975),
          n_swaps = nrow(d), n_countries = n_distinct(d$country_text_id))
  }

  fit_block <- function(mk, model, family, block, conds) {
    imap_dfr(conds, function(cond_value, cond_label) {
      r <- boot_divergence(mk, cond_value)
      if (is.null(r)) return(NULL)
      r |> mutate(model = model, family = family, block = block, condition = cond_label)
    })
  }

  effects <- model_families |>
    pmap_dfr(function(family, model, base_key, ft_key) {
      bind_rows(
        fit_block(base_key, model, family, "Base",       conditions_base),
        fit_block(ft_key,   model, family, "Fine-Tuned", conditions_ft)
      )
    }) |>
    mutate(condition = factor(condition, levels = names(conditions_base)),
          block     = factor(block, levels = c("Base", "Fine-Tuned")))

  bundle <- list(effects = effects, year = year, min_coders = min_coders, n_boot = n_boot)

  if (write) {
    dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
    path <- file.path(out_dir, glue("degradation_{year}.rds"))
    saveRDS(bundle, path)
    message(glue("degradation bundle written: {path} · {nrow(effects)} rows"))
  }
  invisible(bundle)
}

if (sys.nframe() == 0) {
  proj_root <- find_panel_member_root()
  build_degradation(proj_root)
}
