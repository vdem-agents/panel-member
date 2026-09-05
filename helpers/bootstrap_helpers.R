# Shared bootstrap vocabulary + paired-delta machinery for the 2019 analysis.
#
# Single source of truth, sourced by both the compute document
# (analysis/06-bootstrap-metrics-2019.qmd) and the paper deliverables
# (paper/results-2019.qmd, paper/appendix-2019.qmd). Keeping the pairing logic
# here means it is defined once, not copy-pasted across documents.
#
# Requires dplyr/tidyr (loaded by the caller, e.g. via library(tidyverse)).
# The paired functions read the bootstrap resamples and SESOI from the calling
# scope by default (`boot_results`, `sesoi`) — in the compute doc these are the
# live objects; in the paper docs, unpack the saved bundle into the environment
# first, e.g. `list2env(readRDS(".../bootstrap_2019.rds"), environment())`.

# ── Model / condition vocabulary (4-model × 4-condition design) ──────────────
# Base is the few-shot instrument; the three FT adapters run zero-shot (calibration
# is baked into the weights). FT conditions carry a "-zeroshot" suffix that maps
# back to the same Cb/Ev/An/Su columns as the base row.
model_labels <- c(
  "llama-70b"          = "Base",
  "llama-70b-ft-raw"   = "FT-raw",
  "llama-70b-ft-anon"  = "FT-anon",
  "llama-70b-ft-summ"  = "FT-summ"
)

model_family <- c(
  "llama-70b"          = "Base",
  "llama-70b-ft-raw"   = "Fine-tuned",
  "llama-70b-ft-anon"  = "Fine-tuned",
  "llama-70b-ft-summ"  = "Fine-tuned"
)

# Canonical grid column, suffix-stripped: codebook/evidence/anonymized/summarized → Cb/Ev/An/Su
col_labels <- c(
  "codebook"   = "Cb",
  "evidence"   = "Ev",
  "anonymized" = "An",
  "summarized" = "Su"
)

# Paper palette — Okabe-Ito (CVD-safe by construction; validated with the dataviz
# skill's checker). Two categorical dimensions, colors keyed to the ENTITY (never by
# palette position, so a dropped/reordered series never repaints). The blue = the
# plain/registered role (Base; greedy readout); the warm hue = the enhanced role.
#   family_pal  — model identity (base-vs-FT figures + the human-coder reference)
#   readout_pal — greedy (mode) vs expectation (mean); vermillion, kept distinct from
#                 family orange so the two dimensions never look identical.
family_pal  <- c("Base" = "#0072B2", "Fine-tuned" = "#E69F00", "Human coder" = "grey25")
readout_pal <- c("Greedy (mode)" = "#0072B2", "Expectation (mean)" = "#D55E00")

# model_pal — model-FAMILY identity for the cross-family Fig 1 (Llama/Qwen/Gemma). Okabe-Ito,
# keyed to entity; validated with the dataviz checker (worst-pair CVD ΔE 11.4, both modes). In
# that figure color encodes MODEL only — base-vs-FT is the row block and greedy-vs-mean is the
# point shape — so the blue/orange reuse from family_pal/readout_pal never collides within it.
model_pal <- c("Llama 70B" = "#0072B2", "Qwen 72B" = "#E69F00", "Gemma 27B" = "#009E73")

# readout_shape — greedy vs mean when a figure spends COLOR on model (the cross-model Fig 1),
# so readout has to ride the shape channel instead. SOLID (16) = greedy (mode), the panel-member
# readout carried into the distribution tests; OPEN (1) = expectation (mean), the consensus
# estimate. Single source of truth so the fill convention can't drift across figures.
readout_shape <- c("Greedy (mode)" = 16, "Expectation (mean)" = 1)

canon_col <- function(condition) sub("-zeroshot$", "", condition)

# The fine-tuned diagonal (each FT model on the input it was built for), shared by every figure.
ft_diag <- tibble::tibble(
  model_key = c("llama-70b-ft-raw", "llama-70b-ft-anon", "llama-70b-ft-summ"),
  condition = c("evidence-zeroshot", "anonymized-zeroshot", "summarized-zeroshot"),
  row       = c("FT-raw", "FT-anon", "FT-summ")
)

# ── Country-clustered bootstrap weights (shared draw step) ───────────────────
# The single resampling primitive for the 2019 analysis bundle. Resamples
# COUNTRIES with replacement — each drawn country carries its whole ~200-indicator
# block — which is the honest independent unit: a country's indicators are
# correlated, so the prereg's CYI resample treated correlated draws as independent
# and produced anti-conservative (too-narrow) level CIs. See
# notes/bootstrap-clustering-figures-check.qmd for the derivation.
#
# Returns a (countries) x (n_boot + 1) integer weight matrix. rownames are
# country_text_id; column 1 ("Apparent") is the all-ones point-estimate draw and
# the remaining columns are the resamples. Each document keeps its own aggregation
# and just broadcasts a column's per-country weight onto its rows — e.g.
#   w <- W[df$country_text_id, draw]      # broadcast by country
# or join `tibble(country_text_id = rownames(W), w = W[, draw])`. A country drawn
# k times gets weight k, i.e. counts k× — the multiplicity a bootstrap requires.
country_boot_weights <- function(country_ids, n_boot, seed = 42) {
  countries <- sort(unique(country_ids))
  nc <- length(countries)
  set.seed(seed)
  W <- cbind(
    rep(1L, nc),
    replicate(n_boot, tabulate(sample.int(nc, nc, replace = TRUE), nc))
  )
  rownames(W) <- countries
  colnames(W) <- c(
    "Apparent",
    paste0("Bootstrap", formatC(seq_len(n_boot), width = nchar(n_boot), flag = "0"))
  )
  W
}

# ── Paired within-draw delta between two grid cells ──────────────────────────
# Read off the shared bootstrap resamples in `boot_results`. Pairing is preserved
# (difference formed per draw, then quantiled), so these CIs are the honest test —
# not something to eyeball off overlapping level bars.
cell_series <- function(mk, cond, results = boot_results) {
  results |>
    dplyr::filter(model_key == mk, condition == cond) |>
    dplyr::select(id, ai_mae)
}

paired_delta <- function(a_mk, a_cond, b_mk, b_cond, label,
                         results = boot_results, sesoi_val = sesoi) {
  d <- dplyr::inner_join(cell_series(a_mk, a_cond, results),
                         cell_series(b_mk, b_cond, results),
                         by = "id", suffix = c("_a", "_b")) |>
    dplyr::mutate(delta = ai_mae_a - ai_mae_b)
  if (nrow(d) == 0) stop("paired_delta: no matched draws for '", label,
                         "' — check model_key/condition strings.")
  tibble::tibble(
    label = label,
    est   = d$delta[d$id == "Apparent"],
    lo    = quantile(d$delta[d$id != "Apparent"], 0.025),
    hi    = quantile(d$delta[d$id != "Apparent"], 0.975),
    p_gt  = mean(d$delta[d$id != "Apparent"] > 0)
  ) |>
    dplyr::mutate(sesoi_out = abs(est) > sesoi_val)
}

# ── Model-coverage guard ──────────────────────────────────────────────────────
# Every JSONL row is self-describing — model_key is set from whichever model actually served
# the request, not from what a job was meant to run — so a row can't be silently mislabeled.
# But two things CAN slip through silently:
#   1. A whole family goes missing — a job meant to produce it ran as a different one instead
#      (e.g. a dropped BASE= env var defaulting to Llama; see notes/proposed-mechanism-tests.md,
#      2026-09-05). Caught by comparing loaded model_keys against `expect_models`.
#   2. A cell (model_key × condition) is present but SHORT — a run that timed out, was cancelled,
#      or was pulled from the wrong archive folder half-finished. Every cell codes the same
#      country-year-indicator grid, so row counts should cluster tightly (a few rows' spread from
#      parse failures is normal); a cell far below its siblings is a partial run. Caught by
#      flagging any cell under `min_frac` of the median cell row count.
# Both checks are gated on `expect_models` being supplied (opt-in), so ad-hoc / single-model /
# --verify builds don't false-positive. `min_frac` default 0.9.
check_model_coverage <- function(df, expect_models, label = "", min_frac = 0.9) {
  if (is.null(expect_models)) return(invisible(df))

  present <- unique(df$model_key)
  missing <- setdiff(expect_models, present)
  if (length(missing) > 0) {
    stop(glue::glue(
      "{label}: expected model_key(s) missing entirely from the loaded runs: ",
      "{paste(missing, collapse = ', ')}. Present: {paste(sort(present), collapse = ', ')}. ",
      "Check the coding/name-swap job for that family actually ran (and didn't silently ",
      "fall back to a default) before trusting this bundle."
    ))
  }

  counts <- df |>
    dplyr::count(model_key, condition, name = "n") |>
    dplyr::filter(model_key %in% expect_models)
  med <- stats::median(counts$n)
  short <- dplyr::filter(counts, n < min_frac * med)
  if (nrow(short) > 0) {
    rows <- paste(sprintf("  %s / %s: %d rows (%.0f%% of median %d)",
                          short$model_key, short$condition, short$n,
                          100 * short$n / med, round(med)), collapse = "\n")
    stop(glue::glue(
      "{label}: cell(s) present but far shorter than the rest of the grid — likely a ",
      "partial run (timeout / cancel / wrong-folder pull):\n{rows}\n",
      "Median cell is {round(med)} rows. Resubmit or re-pull the short cell(s) before trusting ",
      "this bundle, or lower min_frac if the imbalance is expected."
    ))
  }

  invisible(df)
}
