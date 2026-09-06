# build_reidrates.R — top-1 and top-3 re-identification rate bundle, base + FT-raw x Anonymized +
# Summarized, all three model families (the standalone Question-5 figure — top-1 in the main
# text, top-3 as an appendix companion — and one of the four prominence-crossing ingredients in
# notes/proposed-mechanism-tests.md, Section 6).
#
# Each reid JSONL row already carries precomputed `correct_top1`/`correct_top3` booleans (set by
# pipeline/run_reid_batch.py at inference time), so this is a plain aggregation — no bootstrap,
# no hand-correction of individual guesses (that was specific to the older single-file 2019
# prototype in analysis/03-reidentification-analysis.qmd). Plain bars, no CI (2026-09-05 decision
# — matches this figure's "small, simple bar chart" framing in the design note, unlike the
# CI-bearing figures elsewhere in the paper).
#
# De-duplication (2026-09-05 finding — see notes/mockups/reid-rates-fig-concept.md).
# `reid_ft-raw_{anon,summ}_2023.jsonl` each contain ~2-3x the expected row count: three
# concurrent 2026-09-03 job submissions (73630938/939/940, meant to be Llama/Qwen/Gemma but all
# three silently defaulted to Llama on a BASE= env-var propagation bug) raced against the same
# output file. The resume/checkpoint check fires once at each job's own startup, not
# continuously, so depending on the accident of relative timing, a given (iso, indicator) case
# ended up written 1-3 times rather than exactly once. jsonlite::stream_in already silently
# drops the one fully-corrupted (embedded-NUL) line in the summ file; every other row parses
# fine. On ~1.4% of the duplicated pairs, the copies disagree on `correct_top1` (real run-to-run
# nondeterminism in batched vLLM inference at temperature=0, not a scoring bug) — there's no
# principled way to pick a "right" one, so this treats the file as an append-only log and keeps
# the most recently written copy of each pair. Every other reid file loaded here is already
# exactly one row per (iso, indicator); the dedup is a no-op there.
#
# Usage:
#   Rscript helpers/build_reidrates.R                 # 2023 (the only year this exists for)
#   Rscript helpers/build_reidrates.R --year 2023

suppressPackageStartupMessages({ library(tidyverse); library(glue); library(jsonlite) })

find_panel_member_root <- function() {
  up <- tryCatch(rprojroot::find_root(rprojroot::is_git_root), error = function(e) NA_character_)
  if (!is.na(up)) return(up)
  down <- file.path(getwd(), "panel-member")
  if (dir.exists(file.path(down, ".git"))) return(down)
  stop("Could not locate the panel-member project root from working dir: ", getwd())
}

# family -> (display label, filename prefix for base weights / FT-raw adapter)
reid_families <- tribble(
  ~family,   ~model,       ~base_prefix,        ~ft_prefix,
  "llama",   "Llama 70B",  "reid_base",         "reid_ft-raw",
  "qwen",    "Qwen 72B",   "reid_qwen-base",    "reid_qwen-ft-raw",
  "gemma",   "Gemma 27B",  "reid_gemma-base",   "reid_gemma-ft-raw",
)

build_reidrates_bundle <- function(proj_root,
                                   year    = 2023,
                                   reid_dir = file.path(proj_root, "data", "output", "reid"),
                                   out_dir  = file.path(proj_root, "data", "derived"),
                                   write    = TRUE) {
  if (!dir.exists(reid_dir)) stop("reid dir not found: ", reid_dir)

  needed_cols <- c("iso", "indicator", "correct_top1", "correct_top3", "model_key")
  read_reid <- function(f) {
    if (!file.exists(f)) stop("Missing reid file: ", f)
    con <- file(f, "r"); on.exit(close(con))
    d <- suppressWarnings(stream_in(con, verbose = FALSE)) |> as_tibble() |> select(all_of(needed_cols))
    n_raw <- nrow(d)
    # Keep the last-written copy of each (iso, indicator) pair — see the de-duplication note
    # above. A no-op on the (typical) file that's already one row per pair.
    d <- d |> mutate(.row = row_number()) |>
      group_by(iso, indicator) |>
      slice_max(.row, n = 1, with_ties = FALSE) |>
      ungroup() |>
      select(-.row)
    if (nrow(d) < n_raw) {
      message(glue("  {basename(f)}: deduplicated {n_raw} rows -> {nrow(d)} ",
                   "({n_raw - nrow(d)} duplicate (iso, indicator) copies dropped)"))
    }
    d
  }

  cell <- function(prefix, modelvar, model, treatment_tag, condition) {
    f <- file.path(reid_dir, glue("{prefix}_{treatment_tag}_{year}.jsonl"))
    d <- read_reid(f)
    tibble(model = model, modelvar = modelvar, condition = condition,
           rate = mean(d$correct_top1), rate_top3 = mean(d$correct_top3),
           n = nrow(d), n_countries = n_distinct(d$iso))
  }

  rates <- reid_families |>
    pmap_dfr(function(family, model, base_prefix, ft_prefix) {
      bind_rows(
        cell(base_prefix, "base",   model, "anon", "Anonymized"),
        cell(base_prefix, "base",   model, "summ", "Summarized"),
        cell(ft_prefix,   "ft-raw", model, "anon", "Anonymized"),
        cell(ft_prefix,   "ft-raw", model, "summ", "Summarized")
      )
    })

  # Chance-level reference: 1 / (size of the country universe the model could have named),
  # taken from the pooled data itself rather than hardcoded, so it tracks whatever year/pool
  # this bundle was actually built from.
  n_universe <- reid_families$base_prefix[1] |>
    (\(prefix) file.path(reid_dir, glue("{prefix}_anon_{year}.jsonl")))() |>
    read_reid() |> pull(iso) |> n_distinct()
  chance_rate <- 1 / n_universe

  bundle <- list(rates = rates, chance_rate = chance_rate, year = year)

  if (write) {
    dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
    path <- file.path(out_dir, glue("reidrates_{year}.rds"))
    saveRDS(bundle, path)
    message(glue("reidrates bundle written: {path} · {nrow(rates)} cells · ",
                 "chance rate {round(chance_rate, 4)} (1/{n_universe})"))
  }
  invisible(bundle)
}

# ── CLI ──────────────────────────────────────────────────────────────────────
parse_args <- function(a) {
  out <- list(year = 2023)
  i <- 1
  while (i <= length(a)) {
    switch(a[[i]],
      "--year" = { out$year <- as.integer(a[[i + 1]]); i <- i + 2 },
      stop("unknown arg: ", a[[i]]))
  }
  out
}

if (sys.nframe() == 0) {
  opt <- parse_args(commandArgs(trailingOnly = TRUE))
  proj_root <- find_panel_member_root()
  build_reidrates_bundle(proj_root, year = opt$year)
}
