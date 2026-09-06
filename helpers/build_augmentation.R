# build_augmentation.R — Figure 8, Panel A. Does adding one AI rating to a thin 2023
# panel (2-8 coders) shift the panel mean, and in which direction? Panel size GROWS
# (n -> n+1) -- the true augmentation mechanic, matching D2's registered language
# ("adding one AI rating to a thin panel"). Companion to build_degradation.R (Panel B:
# healthy panels, panel size held fixed). Promoted from notes/mockups/
# augmentation-add-mockup.R after the round-4 augmentation/degradation split — see
# notes/mockups/augmentation-concept.md for the full design history.
#
# Outcome: signed shift = (ai_rating - raw_mean) / (n_coders + 1), country-clustered
# bootstrap mean per model x condition. No coder-level join needed (unlike
# build_degradation.R) since adding a seat doesn't require picking who "left". No SESOI
# band: this quantity is a difference of two integers over a panel-size denominator,
# with no forced-rounding floor the way a single rating vs. a fractional mean has.
#
# Usage:
#   Rscript helpers/build_augmentation.R

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
# Bottom-to-top factor order (Figures 6-7's convention): first level = bottom of a
# discrete y-axis, so the rendered order reads Codebook/Raw Text/Anonymized/Summarized
# top-to-bottom.
conditions_base <- c(Summarized = "summarized", Anonymized = "anonymized",
                     `Raw Text` = "evidence", Codebook = "codebook")
conditions_ft   <- c(`Raw Text` = "evidence-zeroshot", Codebook = "codebook")

build_augmentation <- function(proj_root,
                               year        = 2023,
                               min_coders  = 2L,
                               max_coders  = 8L,
                               n_boot      = 2000,
                               seed        = 42,
                               out_dir     = file.path(proj_root, "data", "derived"),
                               write       = TRUE) {
  source(file.path(proj_root, "helpers", "bootstrap_helpers.R"), local = TRUE)
  data_dir <- file.path(proj_root, "data", "processed")
  runs_dir <- file.path(proj_root, "data", "output", "runs", as.character(year))

  panel_means <- read_csv(file.path(data_dir, "panel_means.csv"), show_col_types = FALSE)
  thin_pool <- panel_means |>
    filter(year == !!year, n_coders >= min_coders, n_coders <= max_coders) |>
    select(country_text_id, year, indicator, raw_mean, n_coders)

  needed_cols <- c("country", "year", "indicator", "condition", "model_key", "rating")
  read_run <- function(f) {
    con <- file(f, "r"); on.exit(close(con))
    stream_in(con, verbose = FALSE) |> as_tibble() |> select(all_of(needed_cols))
  }
  run_files <- list.files(runs_dir, pattern = "\\.jsonl$", full.names = TRUE)
  if (length(run_files) == 0) stop("No .jsonl files in ", runs_dir)

  ai <- run_files |> map(read_run) |> bind_rows() |>
    mutate(model_key = str_remove(model_key, "-local$")) |>
    filter(year == !!year) |> rename(country_text_id = country) |>
    inner_join(thin_pool, by = c("country_text_id", "year", "indicator")) |>
    mutate(shift = (rating - raw_mean) / (n_coders + 1))

  boot_shift <- function(mk, cond_value) {
    d <- filter(ai, model_key == mk, condition == cond_value)
    if (nrow(d) == 0) return(NULL)
    W <- country_boot_weights(d$country_text_id, n_boot, seed = seed)
    draws <- vapply(colnames(W), function(draw) {
      w <- unname(W[, draw][d$country_text_id])
      weighted.mean(d$shift, w)
    }, numeric(1))
    app  <- which(names(draws) == "Apparent")
    boot <- setdiff(seq_along(draws), app)
    tibble(est = draws[app], lo = quantile(draws[boot], 0.025), hi = quantile(draws[boot], 0.975),
          n_cells = nrow(d), n_countries = n_distinct(d$country_text_id))
  }

  fit_block <- function(mk, model, family, block, conds) {
    imap_dfr(conds, function(cond_value, cond_label) {
      r <- boot_shift(mk, cond_value)
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

  bundle <- list(effects = effects, year = year, min_coders = min_coders,
                 max_coders = max_coders, n_boot = n_boot)

  if (write) {
    dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
    path <- file.path(out_dir, glue("augmentation_{year}.rds"))
    saveRDS(bundle, path)
    message(glue("augmentation bundle written: {path} · {nrow(effects)} rows"))
  }
  invisible(bundle)
}

if (sys.nframe() == 0) {
  proj_root <- find_panel_member_root()
  build_augmentation(proj_root)
}
