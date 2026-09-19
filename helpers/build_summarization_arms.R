# build_summarization_arms.R — every de-identification arm measured from ONE baseline (raw
# evidence), on shared draws. Appendix: the task-framing vs. evidence-body question.
#
# Replaces the nested-tree presentation (notes/mockups/decomposition-tree-*), which split the
# ladder into sequential parent/child nodes and labelled each as a share of the total. Those
# shares are path-dependent -- whichever factor moves first absorbs the "first taste" effect --
# so they read as attribution ("compression is 1% of the penalty") when only recovery is
# licensed. Distances from a common origin have no such problem: each is a paired contrast in
# its own right. See notes/mockups/summarization-arms-concept.md.
#
# Arms (2023, base models):
#   evidence                     raw source text, names intact | country named in framing
#   anonymized                   raw-length, names redacted    | framing blanked
#   summarized-identified  (A)   ~400w rewrite, names KEPT     | country named in framing
#   nameswap_correct_summ  (C)   ~400w rewrite, names stripped | country named in framing
#   summarized             (D)   ~400w rewrite, names stripped | framing blanked
#
# C is the name-swap battery's control arm: name-swap mode forces hide_identity off, so it is the
# only run carrying de-identified text with the real country named in the framing.
#
# Reported, all paired, all on the same country-clustered draws (2000, seed 42):
#   FROM THE EVIDENCE BASELINE   anonymized - evidence, A - evidence, C - evidence, D - evidence
#   NAMED PAIRED CONTRASTS       D - A (identity removed, compression fixed)
#                                C - D (task framing only, evidence text identical)
#                                A - C (restore names in the evidence body)
#                                D - anon (path-2 step 2: compress, already de-identified)
#
# The path-2 rows exist to demonstrate path dependence, not to be plotted: moving the same two
# factors in the other order reverses which step looks larger for Gemma.
#
# Sign: arm - baseline. MAE positive = further from the panel mean; signed deviation negative =
# harsher; slope negative = flatter difficulty tracking.

suppressPackageStartupMessages({ library(tidyverse); library(glue); library(jsonlite) })

proj_root <- rprojroot::find_root(rprojroot::is_git_root)
source(file.path(proj_root, "helpers", "bootstrap_helpers.R"))
year <- 2023L; n_boot <- 2000L; seed <- 42L

runs_dir <- file.path(proj_root, "data", "output", "runs")
ns_dir   <- file.path(proj_root, "data", "output", "nameswap")

families <- tribble(~model, ~base_key,
                    "Llama 70B", "llama-70b", "Qwen 72B", "qwen-72b", "Gemma 27B", "gemma-27b")

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
yr_runs <- file.path(runs_dir, as.character(year))

arms <- bind_rows(
  load_arm(list.files(yr_runs, pattern="^evidence_2023_.*\\.jsonl$",   full.names=TRUE), "evidence"),
  load_arm(list.files(yr_runs, pattern="^anonymized_2023_.*\\.jsonl$", full.names=TRUE), "anon"),
  load_arm(list.files(yr_runs, pattern="^summarized_2023_.*\\.jsonl$", full.names=TRUE), "summ"),
  load_arm(list.files(runs_dir, pattern="^summarized-identified_2023_.*\\.jsonl$", full.names=TRUE), "summid"),
  load_arm(list.files(ns_dir,  pattern="^nameswap_correct_summarized_2023_.*\\.jsonl$", full.names=TRUE), "corr")
) |>
  inner_join(select(pm, country_text_id, year, indicator, raw_mean),
             by = c("country_text_id","year","indicator")) |>
  inner_join(human_h, by = c("country_text_id","year","indicator")) |>
  mutate(a = abs(rating - raw_mean), s = rating - raw_mean)

wsl <- function(h, a, w) { sw<-sum(w); sh<-sum(w*h); sa<-sum(w*a)
                           (sum(w*h*a) - sh*sa/sw) / (sum(w*h*h) - sh*sh/sw) }

run_family <- function(base_key, model) {
  d <- arms |> filter(model_key == base_key) |>
    select(country_text_id, indicator, h, a, s, arm) |>
    pivot_wider(names_from = arm, values_from = c(a, s), names_sep = "_") |> drop_na()
  W <- country_boot_weights(d$country_text_id, n_boot, seed = seed)
  app <- which(colnames(W)=="Apparent"); bt <- setdiff(seq_len(ncol(W)), app)
  qc <- function(v, ...) tibble(est=v[app], lo=quantile(v[bt],.025), hi=quantile(v[bt],.975), ...)

  D <- vapply(colnames(W), function(dr) {
    w <- unname(W[,dr][d$country_text_id]); sw <- sum(w)
    m  <- function(x) sum(w*x)/sw
    sl <- function(x) wsl(d$h, x, w)
    c(mae_anon = m(d$a_anon)  - m(d$a_evidence),  sd_anon = m(d$s_anon)  - m(d$s_evidence),
      mae_A    = m(d$a_summid)- m(d$a_evidence),  sd_A    = m(d$s_summid)- m(d$s_evidence),
      mae_C    = m(d$a_corr)  - m(d$a_evidence),  sd_C    = m(d$s_corr)  - m(d$s_evidence),
      mae_D    = m(d$a_summ)  - m(d$a_evidence),  sd_D    = m(d$s_summ)  - m(d$s_evidence),
      mae_DA   = m(d$a_summ)  - m(d$a_summid),    sd_DA   = m(d$s_summ)  - m(d$s_summid),
      mae_CD   = m(d$a_corr)  - m(d$a_summ),      sd_CD   = m(d$s_corr)  - m(d$s_summ),
      mae_AC   = m(d$a_summid)- m(d$a_corr),      sd_AC   = m(d$s_summid)- m(d$s_corr),
      mae_Dan  = m(d$a_summ)  - m(d$a_anon),      sd_Dan  = m(d$s_summ)  - m(d$s_anon),
      sl_anon  = sl(d$a_anon) - sl(d$a_evidence), sl_A    = sl(d$a_summid)- sl(d$a_evidence),
      sl_C     = sl(d$a_corr) - sl(d$a_evidence), sl_D    = sl(d$a_summ) - sl(d$a_evidence),
      sl_DA    = sl(d$a_summ) - sl(d$a_summid),   sl_CD   = sl(d$a_corr) - sl(d$a_summ),
      sl_AC    = sl(d$a_summid)- sl(d$a_corr),    sl_Dan  = sl(d$a_summ) - sl(d$a_anon))
  }, numeric(24))

  map_dfr(rownames(D), \(k) qc(D[k,], key = k)) |> mutate(model = model, n = nrow(d))
}

lab <- c(anon = "Anonymized  (redact, strip both)",
         A    = "Summ-Identified  (compress, keep names)",
         C    = "Summ + named framing  (compress, strip text)",
         D    = "Summarized  (compress, strip both)",
         DA   = "D − A   identity removed, compression fixed",
         CD   = "C − D   task framing only, evidence text identical",
         AC   = "A − C   restore names in the evidence body",
         Dan  = "D − anon   compress, already de-identified  (path-2 step 2)")

res <- families |> pmap_dfr(function(model, base_key) run_family(base_key, model)) |>
  separate_wider_delim(key, "_", names = c("outcome","arm")) |>
  mutate(sig     = if_else(lo > 0 | hi < 0, "*", " "),
         block   = if_else(arm %in% c("anon","A","C","D"),
                           "Measured from raw evidence", "Named paired contrasts"),
         label   = factor(lab[arm], levels = rev(lab)),
         outcome = recode(outcome, mae="MAE", sd="Signed deviation", sl="Difficulty slope"),
         model   = factor(model, levels = c("Llama 70B","Qwen 72B","Gemma 27B")))

out <- file.path(proj_root, "data", "derived", glue("summarizationarms_{year}.rds"))
saveRDS(list(effects = res, year = year, n_boot = n_boot), out)

for (oc in c("MAE","Signed deviation","Difficulty slope")) {
  cat("\n\n=============== ", toupper(oc), " ===============\n", sep="")
  res |> filter(outcome == oc) |>
    mutate(v = sprintf("%+.4f [%+.4f,%+.4f]%s", est, lo, hi, sig)) |>
    select(model, label, v) |> pivot_wider(names_from = model, values_from = v) |>
    as.data.frame() |> print(row.names = FALSE, right = FALSE)
}
cat("\nn (CYIs common to all five arms):", unique(res$n), "\n")
message("summarization-arms bundle written: ", out, " · ", nrow(res), " rows")
