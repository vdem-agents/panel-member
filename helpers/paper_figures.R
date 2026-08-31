# Paper figure & table builders
# -----------------------------------------------------------------------------
# Each function returns a ggplot or gt object so the manuscript document can call
# it directly (e.g. `fig_readout_landscape(...)`) and drop the result in place.
# These read the precomputed derived bundles; nothing here reruns a bootstrap.
#
# Assumes R/bootstrap_helpers.R has already been sourced in the calling session
# (for model_labels, family_pal, ft_diag). The paper gallery sources both.

library(tidyverse)
library(glue)
library(gt)

# Categorical palette (family_pal, readout_pal) is defined once in R/bootstrap_helpers.R,
# which the paper gallery sources before this file.

# Fig 1.1 — synthetic-coder MAE landscape, greedy (mode) vs expectation (mean).
# Seven cells (base ladder Cb/Ev/An/Su + the FT diagonal) x two readouts, against
# the rounding-floor / persistence / human-LOO rails, with an optional +/-SESOI
# band around the human-LOO line.
#
#   exp_bundle    <- readRDS("data/derived/expectation_2019.rds")  # cells + CIs, both readouts
#   greedy_bundle <- readRDS("data/derived/bootstrap_2019.rds")    # rails: human/persist/floor
#   band          "human_loo" (default) shades +/-SESOI around human LOO; "none" omits it.
#
# Both readouts are read from the expectation bundle (`greedy_ci_rerun`, `exp_ci`) so they
# sit on the identical captured pool; with capture now at 100% the greedy re-run matches the
# confirmatory `bootstrap_2019.rds$boot_ci`.
fig_readout_landscape <- function(exp_bundle, greedy_bundle,
                                  band = c("human_loo", "none")) {
  band        <- match.arg(band)
  sesoi       <- exp_bundle$sesoi
  human_mae   <- greedy_bundle$human_ref$human_mae
  persist_mae <- greedy_bundle$persist_ref$persist_mae

  base_conds <- c("codebook", "evidence", "anonymized", "summarized")
  row_lv <- c("FT · Summarized", "FT · Anonymized", "FT · Raw Text",
              "Summarized", "Anonymized", "Raw Text", "Codebook")

  # base 4 conditions + FT diagonal, for one readout's per-cell CI table
  pick <- function(ci, readout) {
    bind_rows(
      filter(ci, model_key == "llama-70b", condition %in% base_conds),
      semi_join(ci, ft_diag, by = c("model_key", "condition"))
    ) |>
      mutate(readout = readout)
  }

  cells <- bind_rows(
    pick(exp_bundle$greedy_ci_rerun, "Greedy (mode)"),
    pick(exp_bundle$exp_ci,          "Expectation (mean)")
  ) |>
    mutate(
      row = case_when(
        model_key == "llama-70b" ~ recode(condition, codebook = "Codebook", evidence = "Raw Text",
                                          anonymized = "Anonymized", summarized = "Summarized"),
        TRUE ~ recode(model_key, "llama-70b-ft-raw" = "FT · Raw Text",
                      "llama-70b-ft-anon" = "FT · Anonymized",
                      "llama-70b-ft-summ" = "FT · Summarized")
      ),
      row     = factor(row, levels = row_lv),
      readout = factor(readout, levels = c("Greedy (mode)", "Expectation (mean)"))
    )

  # Reference lines are drawn and labeled IN the plot (QMD-06 Fig-1 idiom), not decoded in a
  # subtitle. Lines cap just above the top row so their labels sit in the clean strip above.
  n_row <- length(row_lv)
  ycap  <- n_row + 0.3

  p <- ggplot(cells, aes(ai_mae, row, color = readout))
  if (band == "human_loo") {
    p <- p +
      annotate("rect", xmin = human_mae - sesoi, xmax = human_mae + sesoi,
               ymin = -Inf, ymax = ycap, fill = "grey85", alpha = 0.55) +
      annotate("text", x = human_mae, y = ycap + 0.25, label = "±SESOI of human reference",
               color = "grey40", size = 2.9, hjust = 0.5)
  }
  p +
    annotate("segment", x = persist_mae, xend = persist_mae, y = -Inf, yend = ycap,
             linetype = "dashed", color = "grey40") +
    annotate("segment", x = human_mae, xend = human_mae, y = -Inf, yend = ycap,
             linetype = "longdash", color = "grey40") +
    annotate("text", x = persist_mae, y = n_row - 0.2, label = "Naive model",
             color = "grey40", size = 2.9, hjust = -0.07) +
    # separator between the base block (top 4) and the FT block (bottom 3)
    geom_hline(yintercept = 3.5, color = "grey85", linewidth = 0.4) +
    geom_errorbar(aes(xmin = ai_lo, xmax = ai_hi), orientation = "y",
                  width = 0.2, linewidth = 0.6, position = position_dodge(width = 0.5)) +
    geom_point(size = 2.2, position = position_dodge(width = 0.5)) +
    scale_color_manual(values = readout_pal, name = NULL) +
    scale_y_discrete() +   # explicit: lets the numeric line/label y-positions coexist with the factor rows
    coord_cartesian(clip = "off") +
    labs(x = "AI Mean Absolute Error", y = NULL) +
    theme_minimal(base_size = 12) +
    theme(legend.position = "top", legend.justification = "left",
          panel.grid.major.y = element_blank(), plot.title.position = "plot")
}

# Fig A2 — full 4×4 readout grid: every model on every input, the off-diagonal
# expansion of Figure 1. Same greedy-vs-expectation grammar, faceted by model, with
# each fine-tuned model's own training input (the diagonal cell) ringed. Exploratory:
# the off-diagonal cross-generalization cells are not preregistered.
#
#   exp_bundle    <- readRDS("data/derived/expectation_2019.rds")  # all 16 cells, both readouts
#   greedy_bundle <- readRDS("data/derived/bootstrap_2019.rds")    # rails: human/persist
fig_readout_grid <- function(exp_bundle, greedy_bundle,
                             band = c("human_loo", "none")) {
  band        <- match.arg(band)
  sesoi       <- exp_bundle$sesoi
  human_mae   <- greedy_bundle$human_ref$human_mae
  persist_mae <- greedy_bundle$persist_ref$persist_mae

  cond_lv    <- c("Summarized", "Anonymized", "Raw Text", "Codebook")  # first level plots at bottom
  model_disp <- c("llama-70b" = "Base", "llama-70b-ft-raw" = "FT · Raw Text",
                  "llama-70b-ft-anon" = "FT · Anonymized", "llama-70b-ft-summ" = "FT · Summarized")
  model_lv   <- unname(model_disp)

  # base few-shot ladder + every FT model on all four inputs (drop the base zero-shot dups)
  prep <- function(ci, readout) {
    ci |>
      filter(!(model_key == "llama-70b" & grepl("zeroshot$", condition))) |>
      mutate(
        readout = readout,
        model   = factor(unname(model_disp[model_key]), levels = model_lv),
        cond    = factor(recode(canon_col(condition),
                                codebook = "Codebook", evidence = "Raw Text",
                                anonymized = "Anonymized", summarized = "Summarized"),
                         levels = cond_lv)
      )
  }

  cells <- bind_rows(
    prep(exp_bundle$greedy_ci_rerun, "Greedy (mode)"),
    prep(exp_bundle$exp_ci,          "Expectation (mean)")
  ) |>
    mutate(readout = factor(readout, levels = c("Greedy (mode)", "Expectation (mean)")))

  # each FT model's own training input, ringed on both readout points
  diag_pts <- semi_join(cells, ft_diag, by = c("model_key", "condition"))

  # rails labeled once, in the top (Base) facet, to avoid four-fold repetition
  rail_lab <- tibble::tibble(
    model = factor("Base", levels = model_lv),
    cond  = factor("Codebook", levels = cond_lv),
    x     = c(persist_mae, human_mae),
    label = c("Naive model", "Human reference"),
    hj    = c(-0.07, 1.05)
  )

  p <- ggplot(cells, aes(ai_mae, cond, color = readout))
  if (band == "human_loo") {
    p <- p + annotate("rect", xmin = human_mae - sesoi, xmax = human_mae + sesoi,
                      ymin = -Inf, ymax = Inf, fill = "grey85", alpha = 0.55)
  }
  p +
    geom_vline(xintercept = persist_mae, linetype = "dashed",  color = "grey40") +
    geom_vline(xintercept = human_mae,   linetype = "longdash", color = "grey40") +
    geom_errorbar(aes(xmin = ai_lo, xmax = ai_hi), orientation = "y",
                  width = 0.25, linewidth = 0.6, position = position_dodge(width = 0.55)) +
    geom_point(size = 2.2, position = position_dodge(width = 0.55)) +
    geom_point(data = diag_pts, aes(group = readout), inherit.aes = TRUE,
               shape = 1, size = 4.4, stroke = 0.7, color = "grey20",
               position = position_dodge(width = 0.55), show.legend = FALSE) +
    geom_text(data = rail_lab, aes(x = x, y = cond, label = label, hjust = hj),
              inherit.aes = FALSE, color = "grey40", size = 2.7, vjust = -1.2) +
    facet_wrap(~model, ncol = 1, strip.position = "top") +
    scale_color_manual(values = readout_pal, name = NULL) +
    coord_cartesian(clip = "off") +
    labs(x = "AI Mean Absolute Error", y = NULL) +
    theme_minimal(base_size = 12) +
    theme(legend.position = "top", legend.justification = "left",
          panel.grid.major.y = element_blank(),
          strip.text = element_text(face = "bold", hjust = 0),
          plot.title.position = "plot")
}

# ── B and F hypothesis tests ────────────────────────────────────────────────
# bf_contrasts() is the single source: the 9 registered contrasts (B1–B4, F1×3, F2×2) as
# paired ΔMAE with CI, significance, "beyond SESOI", and a verdict against the registered
# prediction (dir: -1 = "MAE(A) < MAE(B)", +1 = ">"). tbl_bf() and fig_bf() both consume it.
# Reads the greedy bundle (bootstrap_2019.rds): $boot_results (for paired_delta) + $sesoi.
bf_contrasts <- function(boot_bundle) {
  results <- boot_bundle$boot_results
  s       <- boot_bundle$sesoi

  # Three-way verdict + the two borderline cases (point beyond SESOI, CI grazing the band).
  verdict_of <- function(est, lo, hi, dir) {
    if (dir < 0 && hi < -s) return("Supported")
    if (dir < 0 && lo >  s) return("Reversed")
    if (dir > 0 && lo >  s) return("Supported")
    if (dir > 0 && hi < -s) return("Reversed")
    if (((lo > 0) | (hi < 0)) && abs(est) > s) {
      supp <- (dir < 0 && est < 0) || (dir > 0 && est > 0)
      return(if (supp) "Borderline supported" else "Borderline reversed")
    }
    "Null"
  }

  specs <- tibble::tribble(
    ~grp,                        ~a_mk,                ~a_cond,               ~b_mk,               ~b_cond,               ~label,                                        ~pred,                           ~dir,
    "Base-model identification", "llama-70b",          "evidence",            "llama-70b",         "codebook",            "Raw Text − Codebook",                 "MAE(Ev) < MAE(Cb)",             -1,
    "Base-model identification", "llama-70b",          "anonymized",          "llama-70b",         "codebook",            "Anonymized − Codebook",               "MAE(An) < MAE(Cb)",             -1,
    "Base-model identification", "llama-70b",          "anonymized",          "llama-70b",         "evidence",            "Anonymized − Raw Text",               "MAE(An) < MAE(Ev)",             -1,
    "Base-model identification", "llama-70b",          "summarized",          "llama-70b",         "anonymized",          "Summarized − Anonymized",             "MAE(Su) < MAE(An)",             -1,
    "Fine-tuning",               "llama-70b-ft-raw",   "evidence-zeroshot",   "llama-70b",         "evidence",            "FT · Raw Text − Base · Raw Text",     "MAE(FT-Raw) < MAE(Base-Raw)",   -1,
    "Fine-tuning",               "llama-70b-ft-anon",  "anonymized-zeroshot", "llama-70b",         "anonymized",          "FT · Anonymized − Base · Anonymized", "MAE(FT-Anon) < MAE(Base-Anon)", -1,
    "Fine-tuning",               "llama-70b-ft-summ",  "summarized-zeroshot", "llama-70b",         "summarized",          "FT · Summarized − Base · Summarized", "MAE(FT-Summ) < MAE(Base-Summ)", -1,
    "Fine-tuning",               "llama-70b-ft-anon",  "evidence-zeroshot",   "llama-70b-ft-raw",  "evidence-zeroshot",   "FT · Anonymized − FT · Raw Text",     "MAE(FT-anon) < MAE(FT-raw)",    -1,
    "Fine-tuning",               "llama-70b-ft-summ",  "evidence-zeroshot",   "llama-70b-ft-anon", "evidence-zeroshot",   "FT · Summarized − FT · Anonymized",   "MAE(FT-summ) < MAE(FT-anon)",   -1
  )

  purrr::pmap_dfr(specs, function(grp, a_mk, a_cond, b_mk, b_cond, label, pred, dir) {
    pd <- paired_delta(a_mk, a_cond, b_mk, b_cond, label, results = results, sesoi_val = s)
    tibble::tibble(
      grp, label = pd$label, pred = pred, dir = dir,
      est = pd$est, lo = pd$lo, hi = pd$hi,
      sig = (pd$lo > 0) | (pd$hi < 0), sesoi_out = pd$sesoi_out,
      verdict = verdict_of(pd$est, pd$lo, pd$hi, dir)
    )
  }) |>
    dplyr::mutate(sesoi = s,
                  grp = factor(grp, levels = c("Base-model identification", "Fine-tuning")))
}

# Table form (gt). ΔMAE bold per `bold`: "significant" (95% CI excludes 0 — note: at this n
# every contrast is significant, so all rows bold), "sesoi" (point beyond ±SESOI), or "none".
tbl_bf <- function(boot_bundle, bold = c("significant", "sesoi", "none")) {
  bold <- match.arg(bold)
  d <- bf_contrasts(boot_bundle)
  s <- d$sesoi[1]
  bold_note <- switch(bold,
    significant = "bold ΔMAE = statistically significant (95% CI excludes 0)",
    sesoi       = "bold ΔMAE = beyond ±SESOI (substantively meaningful)",
    none        = "")
  d |>
    dplyr::mutate(hit = switch(bold, significant = sig, sesoi = sesoi_out, none = FALSE),
                  num = sprintf("%+.3f", est)) |>
    dplyr::transmute(
      grp,
      Contrast                = label,
      `Registered prediction` = pred,
      `ΔMAE`                  = dplyr::if_else(hit, glue("**{num}**"), num),
      `95% CI`                = glue("[{round(lo, 3)}, {round(hi, 3)}]"),
      `Beyond SESOI?`         = dplyr::if_else(sesoi_out, "yes", "no"),
      Verdict                 = verdict) |>
    gt(groupname_col = "grp") |>
    fmt_markdown(columns = "ΔMAE") |>
    tab_header(
      title    = "Formal tests of the B and F hypotheses",
      subtitle = glue("2019 · paired country-clustered bootstrap · SESOI ±{round(s, 3)}",
                      if (nzchar(bold_note)) glue(" · {bold_note}") else ""))
}

# Figure form: a coefficient/forest plot of the same 9 contrasts, with a dashed zero line and
# the ±SESOI band. Built as two stacked panels (one per group) via patchwork so each group
# header is a plot title — left-justified to the figure edge via plot.title.position = "plot"
# (facet strips clip, so they cannot be pushed left of the panel). Heights are proportional to
# the row counts (4 base, 5 fine-tuning), so row spacing is even across groups.
fig_bf <- function(boot_bundle) {
  d  <- bf_contrasts(boot_bundle)
  s  <- d$sesoi[1]
  xr <- range(c(d$lo, d$hi, -s, s, 0)); xr <- xr + c(-0.02, 0.02) * diff(xr)

  one <- function(df, title, show_x) {
    df <- dplyr::mutate(df, label = factor(label, levels = rev(label)))  # first spec plots at top
    p <- ggplot(df, aes(est, label)) +
      annotate("rect", xmin = -s, xmax = s, ymin = -Inf, ymax = Inf, fill = "grey85", alpha = 0.55) +
      geom_vline(xintercept = 0, linetype = "dashed", color = "grey40") +
      geom_errorbar(aes(xmin = lo, xmax = hi), orientation = "y",
                    width = 0.25, linewidth = 0.6, color = "#0072B2") +
      geom_point(size = 2.6, color = "#0072B2") +
      scale_x_continuous(limits = xr) +
      labs(title = title, x = NULL, y = NULL) +
      theme_minimal(base_size = 12) +
      theme(panel.grid.major.y = element_blank(),
            plot.title = element_text(face = "bold", size = 11),
            plot.title.position = "plot")   # title aligns to the whole plot width (label gutter incl.)
    if (!show_x) p <- p + theme(axis.text.x = element_blank(), axis.ticks.x = element_blank())
    p
  }

  pB <- one(dplyr::filter(d, grp == "Base-model identification"), "Base-model identification", FALSE)
  pF <- one(dplyr::filter(d, grp == "Fine-tuning"),               "Fine-tuning",               TRUE)
  patchwork::wrap_plots(pB, pF, ncol = 1, heights = c(4, 5))
}
