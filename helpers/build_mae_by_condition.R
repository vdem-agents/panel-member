# build_mae_by_condition.R — does movement / prominence's effect on raw AI error (MAE) hold up
# across the de-identification ladder? This is the direct test of the original Figs 1-3 puzzle
# that Figs 6/7 never actually ran: does a country's movement or prominence explain the MAE-level
# gap between Evidence and Anonymized/Summarized, not just the difficulty-tracking slope or
# signed deviation. Same shape as build_signeddev_by_condition.R -- two SEPARATE models, no
# interaction, no h term:
#
#   err ~ movement   (movement-only; drops reid)
#   err ~ reid       (reid-only; drops movement)
#
# where err = |rating - raw_mean|. UNLIKE the signed-deviation version, movement here uses the
# plain UNSIGNED rank transform (matching Fig 6's difficulty-slope convention, not Fig 7's signed
# one) -- this is a magnitude question ("does moving a lot hurt accuracy, regardless of
# direction"), not a directional lag/anchoring question.
#
# Usage:
#   Rscript helpers/build_mae_by_condition.R --moderator movement
#   Rscript helpers/build_mae_by_condition.R --moderator reid

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
reid_base_prefix <- c(llama = "reid_base", qwen = "reid_qwen-base", gemma = "reid_gemma-base")

# Listed bottom-to-top (ggplot puts the first factor level at the bottom of a discrete axis) so
# the rendered order reads Codebook/Raw Text/Anonymized/Summarized top-to-bottom, matching Figure
# 1's convention.
conditions_base <- c(Summarized = "summarized", Anonymized = "anonymized",
                     `Raw Text` = "evidence", Codebook = "codebook")
conditions_ft   <- c(`Raw Text` = "evidence-zeroshot", Codebook = "codebook")

wls_coefs <- function(y, X, w) {
  XtW <- t(X * w)
  as.numeric(solve(XtW %*% X, XtW %*% y))
}

build_mae_by_condition <- function(proj_root,
                                   moderator      = c("movement", "reid"),
                                   year           = 2023,
                                   reid_treatment = "summ",
                                   n_boot         = 2000,
                                   seed           = 42,
                                   out_dir        = file.path(proj_root, "data", "derived"),
                                   write          = TRUE) {
  moderator <- match.arg(moderator)
  source(file.path(proj_root, "helpers", "bootstrap_helpers.R"), local = TRUE)
  data_dir <- file.path(proj_root, "data", "processed")
  runs_dir <- file.path(proj_root, "data", "output", "runs", as.character(year))
  reid_dir <- file.path(proj_root, "data", "output", "reid")

  panel_means <- read_csv(file.path(data_dir, "panel_means.csv"), show_col_types = FALSE)

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
    inner_join(select(panel_means, country_text_id, year, indicator, raw_mean),
               by = c("country_text_id", "year", "indicator")) |>
    mutate(err = abs(rating - raw_mean))

  movement <- readRDS(file.path(proj_root, "data", "derived", glue("movement_{year}.rds")))$dpoly |>
    mutate(movement_value = rank(dpoly_abs, na.last = "keep") / sum(!is.na(dpoly_abs)))

  read_reid <- function(prefix) {
    f <- file.path(reid_dir, glue("{prefix}_{reid_treatment}_{year}.jsonl"))
    if (!file.exists(f)) stop("Missing reid file: ", f)
    con <- file(f, "r"); on.exit(close(con))
    d <- suppressWarnings(stream_in(con, verbose = FALSE)) |> as_tibble() |>
      select(iso, indicator, correct_top1)
    d |> mutate(.row = row_number()) |>
      group_by(iso, indicator) |> slice_max(.row, n = 1, with_ties = FALSE) |> ungroup() |>
      select(-.row)
  }

  fit_one <- function(model_key, family, cond_value) {
    d <- filter(ai, model_key == !!model_key, condition == cond_value) |>
      select(country_text_id, indicator, err)

    if (moderator == "movement") {
      d <- d |> inner_join(select(movement, country_text_id, movement_value), by = "country_text_id")
      mod_col <- "movement_value"
    } else {
      reid <- read_reid(reid_base_prefix[[family]]) |>
        transmute(country_text_id = iso, indicator, reid = as.numeric(correct_top1))
      d <- d |> inner_join(reid, by = c("country_text_id", "indicator"))
      mod_col <- "reid"
    }
    d <- filter(d, !is.na(err), !is.na(.data[[mod_col]]))
    if (nrow(d) == 0) stop("fit_one(", model_key, ", ", cond_value, "): no rows after join.")

    W <- country_boot_weights(d$country_text_id, n_boot, seed = seed)
    y <- d$err
    m <- d[[mod_col]]
    X <- cbind(1, m)

    B <- vapply(colnames(W), function(draw) {
      w <- unname(W[, draw][d$country_text_id])
      wls_coefs(y, X, w)
    }, numeric(2))
    app  <- which(colnames(W) == "Apparent")
    boot <- setdiff(seq_len(ncol(B)), app)
    tibble(est = B[2, app], lo = quantile(B[2, boot], 0.025), hi = quantile(B[2, boot], 0.975),
          n = nrow(d))
  }

  fit_block <- function(model_key, family, model, block, conds) {
    imap_dfr(conds, function(cond_value, cond_label) {
      fit_one(model_key, family, cond_value) |> mutate(model = model, block = block, condition = cond_label)
    })
  }

  effects <- model_families |>
    pmap_dfr(function(family, model, base_key, ft_key) {
      bind_rows(
        fit_block(base_key, family, model, "Base",       conditions_base),
        fit_block(ft_key,   family, model, "Fine-Tuned", conditions_ft)
      )
    }) |>
    mutate(condition = factor(condition, levels = names(conditions_base)),
          block     = factor(block, levels = c("Base", "Fine-Tuned")))

  bundle <- list(effects = effects, moderator = moderator, year = year,
                 reid_treatment = reid_treatment, n_boot = n_boot)

  if (write) {
    dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
    path <- file.path(out_dir, glue("maebycondition_{moderator}_{year}.rds"))
    saveRDS(bundle, path)
    message(glue("MAE-by-condition ({moderator}) bundle written: {path} · {nrow(effects)} rows"))
  }
  invisible(bundle)
}

# ── CLI ──────────────────────────────────────────────────────────────────────
parse_args <- function(a) {
  out <- list(moderator = "movement", year = 2023)
  i <- 1
  while (i <= length(a)) {
    switch(a[[i]],
      "--moderator" = { out$moderator <- a[[i + 1]]; i <- i + 2 },
      "--year"      = { out$year      <- as.integer(a[[i + 1]]); i <- i + 2 },
      stop("unknown arg: ", a[[i]]))
  }
  out
}

if (sys.nframe() == 0) {
  opt <- parse_args(commandArgs(trailingOnly = TRUE))
  proj_root <- find_panel_member_root()
  build_mae_by_condition(proj_root, moderator = opt$moderator, year = opt$year)
}
