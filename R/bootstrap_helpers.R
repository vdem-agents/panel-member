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

# Okabe–Ito (CVD-safe by construction) for the base-vs-FT distinction.
family_pal <- c("Base" = "#0072B2", "Fine-tuned" = "#E69F00")

canon_col <- function(condition) sub("-zeroshot$", "", condition)

# The fine-tuned diagonal (each FT model on the input it was built for), shared by every figure.
ft_diag <- tibble::tibble(
  model_key = c("llama-70b-ft-raw", "llama-70b-ft-anon", "llama-70b-ft-summ"),
  condition = c("evidence-zeroshot", "anonymized-zeroshot", "summarized-zeroshot"),
  row       = c("FT-raw", "FT-anon", "FT-summ")
)

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
