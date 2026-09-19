# build_identity_effect.R — Test B from the "what explains Figs 1-3's de-identification pattern"
# discussion (2026-09-06). Not a moderator-crossing test like build_mae_by_condition.R (Test A) --
# a direct condition CONTRAST: does removing identity from the evidence, holding text length
# fixed, change MAE? Two simple effects, both at once, using the same shared bootstrap draws:
#
#   Identity at full text  = MAE(Anonymized) - MAE(Evidence)
#   Identity at compressed = MAE(Summarized)  - MAE(Summarized-Identified)
#
# This is a simplified, corrected slice of the old Panel A 2x2 (helpers/build_priorreliance.R) --
# same four conditions, same shared-draw logic -- but drops Compression and the Interaction term
# entirely (the two things that made the original dense and hard to explain). Base models only,
# 2023, three families.
#
# Usage:
#   Rscript helpers/build_identity_effect.R

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

build_identity_effect <- function(proj_root,
                                  year    = 2023,
                                  n_boot  = 2000,
                                  seed    = 42,
                                  out_dir = file.path(proj_root, "data", "derived"),
                                  write   = TRUE) {
  source(file.path(proj_root, "helpers", "bootstrap_helpers.R"), local = TRUE)
  data_dir      <- file.path(proj_root, "data", "processed")
  runs_dir      <- file.path(proj_root, "data", "output", "runs", as.character(year))
  runs_flat_dir <- file.path(proj_root, "data", "output", "runs")

  panel_means <- read_csv(file.path(data_dir, "panel_means.csv"), show_col_types = FALSE)

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
    mutate(err = abs(rating - raw_mean))

  fit_family <- function(model_key, model) {
    ev   <- filter(ai, model_key == !!model_key, condition == "evidence") |>
      select(country_text_id, indicator, Evidence = err)
    an   <- filter(ai, model_key == !!model_key, condition == "anonymized") |>
      select(country_text_id, indicator, Anonymized = err)
    su   <- filter(ai, model_key == !!model_key, condition == "summarized") |>
      select(country_text_id, indicator, Summarized = err)
    suid <- filter(ai, model_key == !!model_key, condition == "summarized-identified") |>
      select(country_text_id, indicator, SummarizedIdentified = err)

    wide <- ev |>
      inner_join(an,   by = c("country_text_id", "indicator")) |>
      inner_join(su,   by = c("country_text_id", "indicator")) |>
      inner_join(suid, by = c("country_text_id", "indicator"))
    if (nrow(wide) == 0) stop("fit_family(", model_key, "): no CYIs common to all four conditions.")

    W <- country_boot_weights(wide$country_text_id, n_boot, seed = seed)
    Ev <- wide$Evidence; An <- wide$Anonymized; Su <- wide$Summarized; SuID <- wide$SummarizedIdentified

    effect_of_draw <- function(draw) {
      w  <- unname(W[, draw][wide$country_text_id])
      sw <- sum(w)
      mEv <- sum(w * Ev) / sw; mAn <- sum(w * An) / sw
      mSu <- sum(w * Su) / sw; mSuID <- sum(w * SuID) / sw
      full_text <- mAn - mEv; compressed <- mSu - mSuID
      # Compression: the compressed rewrite with identity KEPT on both sides, so the only thing
      # that moves is the compression. Added 2026-09-18 -- the one contrast in this family that
      # touches raw text with names intact, which neither identity contrast does.
      compression <- mSuID - mEv
      # Paired contrast (same draw, same weights): if the Full Text identity effect is reliably
      # bigger than the Compressed one, that's suggestive evidence the raw-vs-LLM-rewrite
      # confound in the Full Text comparison (Evidence is unprocessed; Anonymized is itself an
      # LLM rewrite) is adding something beyond pure identity removal -- since the Compressed
      # comparison holds "is this a rewrite" constant (both Summarized and Summarized-Identified
      # are LLM-generated) and only Full Text doesn't. Suggestive, not decisive (2026-09-06).
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

  bundle <- list(effects = effects, year = year, n_boot = n_boot)

  if (write) {
    dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
    path <- file.path(out_dir, glue("identityeffect_{year}.rds"))
    saveRDS(bundle, path)
    message(glue("identity-effect bundle written: {path} · {nrow(effects)} rows"))
  }
  invisible(bundle)
}

if (sys.nframe() == 0) {
  proj_root <- find_panel_member_root()
  build_identity_effect(proj_root)
}
