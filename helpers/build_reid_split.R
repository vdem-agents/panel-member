# build_reid_split.R — does the task-framing leg concentrate where the model CANNOT re-identify
# the country? Appendix companion to build_summarization_arms.R.
#
# The tension this resolves: the re-identification figure says the base model names the country
# 24-29% of the time from summarized text, yet naming it in the task framing still moves the
# rating. Two readings, with opposite predictions:
#
#   partial leak           identity really is gone for ~3/4 of cases, so the aggregate effect is
#                          real and no puzzle arises.
#                          PREDICTS: framing leg LARGER among CYIs the model could NOT name.
#   framing-only attention the model attends to the task-framing slot and does not spontaneously
#                          condition on identity it could extract from the evidence body -- it can
#                          name the country under interrogation without using it while rating.
#                          PREDICTS: framing leg FLAT across the two groups.
#
# Framing leg = nameswap_correct_summarized - summarized (C - D): the SAME de-identified evidence
# text on both sides, with only {FOCAL_COUNTRY}/{FOCAL_YEAR} moving. Split by the base model's
# correct_top1 on the summarized re-identification probe, deduped by iso x indicator.
#
# This is NOT a compression/identity decomposition -- that is `fig-identity-and-compression`, built off
# helpers/build_identity_effect*.R. This script adds only the re-identification split.
#
# Convention: identified - de-identified (house convention, matching `fig-identity-and-compression` and the
# summarization-arms bundle). Shared country-clustered draws, 2000, seed 42, so the subgroup
# contrasts and their difference are computed within draw.
# See notes/mockups/reid-split-framing-leg-concept.md.

suppressPackageStartupMessages({ library(tidyverse); library(glue); library(jsonlite) })

proj_root <- rprojroot::find_root(rprojroot::is_git_root)
source(file.path(proj_root, "helpers", "bootstrap_helpers.R"))
year <- 2023L; n_boot <- 2000L; seed <- 42L

runs_dir <- file.path(proj_root, "data", "output", "runs")
ns_dir   <- file.path(proj_root, "data", "output", "nameswap")
reid_dir <- file.path(proj_root, "data", "output", "reid")

families <- tribble(~model,       ~base_key,    ~reid_prefix,
                    "Llama 70B",  "llama-70b",  "reid_base",
                    "Qwen 72B",   "qwen-72b",   "reid_qwen-base",
                    "Gemma 27B",  "gemma-27b",  "reid_gemma-base")

pm <- read_csv(file.path(proj_root,"data","processed","panel_means.csv"),   show_col_types = FALSE)
hr <- read_csv(file.path(proj_root,"data","processed","human_ratings.csv"), show_col_types = FALSE)
human_h <- hr |> filter(year == !!year) |>
  group_by(country_text_id, year, indicator) |> filter(n() >= 2L) |>
  mutate(loo = (sum(rating) - rating)/(n()-1), e = abs(rating - loo)) |> ungroup() |>
  group_by(country_text_id, year, indicator) |> summarise(h = mean(e), .groups = "drop")

rd <- function(f, cols) { con <- file(f,"r"); on.exit(close(con))
  stream_in(con, verbose = FALSE) |> as_tibble() |> select(all_of(cols)) }
base_cols <- c("country","year","indicator","model_key","rating")

load_arm <- function(files, arm) {
  files |> map(\(f) rd(f, base_cols)) |> bind_rows() |>
    mutate(model_key = str_remove(model_key, "-local$"), arm = arm) |>
    filter(year == !!year) |> rename(country_text_id = country)
}

summ    <- load_arm(list.files(file.path(runs_dir, as.character(year)),
                    pattern = "^summarized_2023_.*\\.jsonl$", full.names = TRUE), "summarized")
correct <- load_arm(list.files(ns_dir,
                    pattern = "^nameswap_correct_summarized_2023_.*\\.jsonl$", full.names = TRUE), "correct")

# The probe files carry duplicated rows from a job-submission race (same fix as build_reidrates.R):
# dedupe on iso x indicator, keeping the last occurrence.
read_reid <- function(prefix) {
  f <- file.path(reid_dir, glue("{prefix}_summ_{year}.jsonl"))
  if (!file.exists(f)) stop("Missing reid file: ", f)
  con <- file(f, "r"); on.exit(close(con))
  stream_in(con, verbose = FALSE) |> as_tibble() |> mutate(.row = row_number()) |>
    group_by(iso, indicator) |> slice_max(.row, n = 1, with_ties = FALSE) |> ungroup() |>
    transmute(country_text_id = iso, indicator, reid = as.integer(correct_top1))
}
reid_all <- families |> select(base_key, reid_prefix) |>
  pmap_dfr(function(base_key, reid_prefix) read_reid(reid_prefix) |> mutate(model_key = base_key))

both <- bind_rows(summ, correct) |>
  inner_join(select(pm, country_text_id, year, indicator, raw_mean),
             by = c("country_text_id","year","indicator")) |>
  inner_join(human_h, by = c("country_text_id","year","indicator")) |>
  inner_join(reid_all, by = c("country_text_id","indicator","model_key")) |>
  mutate(a = abs(rating - raw_mean), s = rating - raw_mean)

wsl <- function(h, a, w) { sw<-sum(w); sh<-sum(w*h); sa<-sum(w*a)
                           (sum(w*h*a) - sh*sa/sw) / (sum(w*h*h) - sh*sh/sw) }

run_family <- function(base_key, model) {
  d <- both |> filter(model_key == base_key) |>
    select(country_text_id, indicator, h, a, s, arm, reid) |>
    pivot_wider(names_from = arm, values_from = c(a, s), names_sep = "_") |> drop_na()
  W <- country_boot_weights(d$country_text_id, n_boot, seed = seed)
  app <- which(colnames(W)=="Apparent"); bt <- setdiff(seq_len(ncol(W)), app)
  qc <- function(v, ...) tibble(est=v[app], lo=quantile(v[bt],.025), hi=quantile(v[bt],.975), ...)
  i1 <- which(d$reid == 1L); i0 <- which(d$reid == 0L)

  D <- vapply(colnames(W), function(dr) {
    w <- unname(W[,dr][d$country_text_id])
    m  <- function(x, i) sum(w[i]*x[i])/sum(w[i])
    sl <- function(x, i) wsl(d$h[i], x[i], w[i])
    all <- seq_len(nrow(d))
    c(mae_all = m(d$a_correct, all) - m(d$a_summarized, all),
      mae_r1  = m(d$a_correct, i1)  - m(d$a_summarized, i1),
      mae_r0  = m(d$a_correct, i0)  - m(d$a_summarized, i0),
      mae_mod = (m(d$a_correct,i1) - m(d$a_summarized,i1)) -
                (m(d$a_correct,i0) - m(d$a_summarized,i0)),
      sd_all  = m(d$s_correct, all) - m(d$s_summarized, all),
      sd_r1   = m(d$s_correct, i1)  - m(d$s_summarized, i1),
      sd_r0   = m(d$s_correct, i0)  - m(d$s_summarized, i0),
      sd_mod  = (m(d$s_correct,i1) - m(d$s_summarized,i1)) -
                (m(d$s_correct,i0) - m(d$s_summarized,i0)),
      sl_all  = sl(d$a_correct, all) - sl(d$a_summarized, all),
      sl_r1   = sl(d$a_correct, i1)  - sl(d$a_summarized, i1),
      sl_r0   = sl(d$a_correct, i0)  - sl(d$a_summarized, i0),
      sl_mod  = (sl(d$a_correct,i1) - sl(d$a_summarized,i1)) -
                (sl(d$a_correct,i0) - sl(d$a_summarized,i0)))
  }, numeric(12))

  map_dfr(rownames(D), \(k) qc(D[k,], key = k)) |>
    separate_wider_delim(key, "_", names = c("outcome","group")) |>
    mutate(model = model, n = nrow(d), n_reid1 = length(i1), n_reid0 = length(i0),
           reid_rate = length(i1)/nrow(d))
}

res <- families |> pmap_dfr(function(model, base_key, reid_prefix) run_family(base_key, model)) |>
  mutate(sig     = if_else(lo > 0 | hi < 0, "*", " "),
         outcome = recode(outcome, mae = "MAE", sd = "Signed deviation", sl = "Difficulty slope"),
         group   = recode(group, all = "Overall", r1 = "Re-identified",
                          r0 = "Not re-identified", mod = "Difference (re-id − not)"),
         model   = factor(model, levels = c("Llama 70B","Qwen 72B","Gemma 27B")))

out <- file.path(proj_root, "data", "derived", glue("reidsplit_{year}.rds"))
saveRDS(list(effects = res, year = year, n_boot = n_boot, reid_treatment = "summ"), out)

for (oc in c("MAE","Signed deviation","Difficulty slope")) {
  cat("\n\n===============", toupper(oc), "===============\n")
  cat("Framing leg C - D, identified - de-identified. * = country-clustered 95% CI excludes 0.\n")
  cat("Partial leak predicts a LARGER (more negative on MAE) effect among NOT re-identified.\n\n")
  res |> filter(outcome == oc) |>
    mutate(v = sprintf("%+.4f [%+.4f,%+.4f]%s", est, lo, hi, sig)) |>
    select(model, group, v) |> pivot_wider(names_from = group, values_from = v) |>
    as.data.frame() |> print(row.names = FALSE)
}
cat("\nn:", unique(res$n), "| re-identified share:",
    sprintf("%.3f", unique(res$reid_rate)), "\n")
message("re-id split bundle written: ", out, " · ", nrow(res), " rows")
