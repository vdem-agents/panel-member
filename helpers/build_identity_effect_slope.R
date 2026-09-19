# build_identity_effect_slope.R — the A8 identity-removal contrast, run on the DIFFICULTY-TRACKING
# SLOPE (weighted OLS slope of AI error a_c on human case difficulty h_c) instead of MAE.
# Companion to build_identity_effect.R / build_identity_effect_signeddev.R: same four conditions,
# same shared-draw paired-contrast logic, base models only, 2023, three families.
#
#   Identity at full text  = slope(Anonymized) - slope(Evidence)
#   Identity at compressed = slope(Summarized)  - slope(Summarized-Identified)
#
# Negative = removing the country's name FLATTENS difficulty tracking (the model leans harder on a
# prior), holding text length (Full Text) or compression (Compressed) fixed. h_c is the within-cell
# human leave-one-out MAE (min 2 coders), matched to build_slope_by_condition.R / build_distmatch.R.
# Each family's four conditions are restricted to the CYIs common to all four, and every draw
# recomputes all four slopes on the same resampled countries, so the two contrasts are honest
# paired differences. The Compressed contrast is the clean one (both sides are LLM rewrites); the
# Full Text contrast carries the raw-vs-rewrite confound flagged in build_identity_effect.R.
#
# Usage:
#   Rscript helpers/build_identity_effect_slope.R

suppressPackageStartupMessages({ library(tidyverse); library(glue); library(jsonlite) })

find_panel_member_root <- function() {
  up <- tryCatch(rprojroot::find_root(rprojroot::is_git_root), error = function(e) NA_character_)
  if (!is.na(up)) return(up)
  down <- file.path(getwd(), "panel-member")
  if (dir.exists(file.path(down, ".git"))) return(down)
  stop("Could not locate the panel-member project root from working dir: ", getwd())
}

model_families <- tribble(
  ~family,  ~model,       ~base_key,
  "llama",  "Llama 70B",  "llama-70b",
  "qwen",   "Qwen 72B",   "qwen-72b",
  "gemma",  "Gemma 27B",  "gemma-27b",
)

# Closed-form weighted OLS slope of a on h (same form as build_distmatch.R).
wls_slope <- function(h, a, w) {
  sw  <- sum(w)
  shw <- sum(w * h); saw <- sum(w * a)
  num <- sum(w * h * a) - shw * saw / sw
  den <- sum(w * h * h) - shw * shw / sw
  num / den
}

build_identity_effect_slope <- function(proj_root,
                                        year       = 2023,
                                        min_coders = 2L,
                                        n_boot     = 2000,
                                        seed       = 42,
                                        out_dir    = file.path(proj_root, "data", "derived"),
                                        write      = TRUE) {
  source(file.path(proj_root, "helpers", "bootstrap_helpers.R"), local = TRUE)
  data_dir      <- file.path(proj_root, "data", "processed")
  runs_dir      <- file.path(proj_root, "data", "output", "runs", as.character(year))
  runs_flat_dir <- file.path(proj_root, "data", "output", "runs")

  panel_means   <- read_csv(file.path(data_dir, "panel_means.csv"),   show_col_types = FALSE)
  human_ratings <- read_csv(file.path(data_dir, "human_ratings.csv"), show_col_types = FALSE)

  human_h <- human_ratings |>
    filter(year == !!year) |>
    group_by(country_text_id, year, indicator) |>
    filter(n() >= min_coders) |>
    mutate(loo_mean = (sum(rating) - rating) / (n() - 1), e = abs(rating - loo_mean)) |>
    ungroup() |>
    group_by(country_text_id, year, indicator) |>
    summarise(h = mean(e), .groups = "drop")

  needed_cols <- c("country", "year", "indicator", "condition", "model_key", "rating")
  read_run <- function(f) {
    con <- file(f, "r"); on.exit(close(con))
    stream_in(con, verbose = FALSE) |> as_tibble() |> select(all_of(needed_cols))
  }
  main_files <- list.files(runs_dir, pattern = "\\.jsonl$", full.names = TRUE)
  si_files   <- list.files(runs_flat_dir, pattern = "^summarized-identified.*\\.jsonl$", full.names = TRUE)
  if (length(main_files) == 0) stop("No .jsonl files in ", runs_dir)
  if (length(si_files) == 0) stop("No summarized-identified files in ", runs_flat_dir)

  ai <- c(main_files, si_files) |> map(read_run) |> bind_rows() |>
    mutate(model_key = str_remove(model_key, "-local$")) |>
    filter(year == !!year) |> rename(country_text_id = country) |>
    inner_join(select(panel_means, country_text_id, year, indicator, raw_mean),
               by = c("country_text_id", "year", "indicator")) |>
    inner_join(human_h, by = c("country_text_id", "year", "indicator")) |>
    mutate(a = abs(rating - raw_mean))

  fit_family <- function(model_key, model) {
    pick <- function(cond, nm) filter(ai, model_key == !!model_key, condition == cond) |>
      select(country_text_id, indicator, h, !!nm := a)
    ev   <- pick("evidence",              "aEv")
    an   <- pick("anonymized",            "aAn")
    su   <- pick("summarized",            "aSu")
    suid <- pick("summarized-identified", "aSuID")

    wide <- ev |>
      inner_join(select(an,   -h), by = c("country_text_id", "indicator")) |>
      inner_join(select(su,   -h), by = c("country_text_id", "indicator")) |>
      inner_join(select(suid, -h), by = c("country_text_id", "indicator"))
    if (nrow(wide) == 0) stop("fit_family(", model_key, "): no CYIs common to all four conditions.")

    W <- country_boot_weights(wide$country_text_id, n_boot, seed = seed)
    h <- wide$h; aEv <- wide$aEv; aAn <- wide$aAn; aSu <- wide$aSu; aSuID <- wide$aSuID

    effect_of_draw <- function(draw) {
      w   <- unname(W[, draw][wide$country_text_id])
      sEv   <- wls_slope(h, aEv,   w)
      sAn   <- wls_slope(h, aAn,   w)
      sSu   <- wls_slope(h, aSu,   w)
      sSuID <- wls_slope(h, aSuID, w)
      full_text <- sAn - sEv; compressed <- sSu - sSuID
      # Compression: compressed rewrite, identity KEPT on both sides (see build_identity_effect.R).
      compression <- sSuID - sEv
      c(Compression = compression, `Full Text` = full_text, Compressed = compressed,
        `Full Text - Compressed` = full_text - compressed)
    }
    M <- vapply(colnames(W), effect_of_draw, numeric(4))
    rownames(M) <- c("Compression", "Full Text", "Compressed", "Full Text - Compressed")

    app  <- which(colnames(W) == "Apparent")
    boot <- setdiff(seq_len(ncol(M)), app)
    tibble(
      level = rownames(M),
      est   = M[, app],
      lo    = apply(M[, boot, drop = FALSE], 1, quantile, 0.025),
      hi    = apply(M[, boot, drop = FALSE], 1, quantile, 0.975)
    ) |> mutate(model = model, n = nrow(wide))
  }

  effects <- model_families |>
    pmap_dfr(function(family, model, base_key) fit_family(base_key, model)) |>
    mutate(level = factor(level, levels = c("Full Text - Compressed", "Compressed", "Full Text", "Compression")))

  bundle <- list(effects = effects, year = year, min_coders = min_coders,
                 n_boot = n_boot, outcome = "difficulty_slope")

  if (write) {
    dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
    path <- file.path(out_dir, glue("identityeffect_slope_{year}.rds"))
    saveRDS(bundle, path)
    message(glue("identity-effect (difficulty slope) bundle written: {path} · {nrow(effects)} rows"))
  }
  invisible(bundle)
}

if (sys.nframe() == 0) {
  proj_root <- find_panel_member_root()
  build_identity_effect_slope(proj_root)
}
