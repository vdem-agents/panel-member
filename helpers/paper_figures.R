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
library(patchwork)   # side-by-side composite for the two-panel Figure 2

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

# Fig 1 (cross-family) — synthetic-coder MAE across three model families, both readouts on one
# axis. Rows = 8: the base few-shot ladder (Cb/Ev/An/Su) on top, the FT-raw ladder (raw-text
# adapter under the same four conditions) on the bottom. Color = model family (model_pal);
# shape = readout (filled ● greedy, open ○ mean; see readout_shape). Models are dodged within each condition row so
# their CIs share one x-axis and overlap is read directly — the design point of this figure.
# Qwen/Gemma are raw-only, so the FT block is FT-raw for all three families (no anon/summ
# adapters here; those stay in the Llama-only A2 grid). Rails and ±SESOI band as in
# fig_readout_landscape.
#
#   exp_bundle    <- readRDS("data/derived/expectation_2019.rds")  # greedy_ci_rerun + exp_ci
#   greedy_bundle <- readRDS("data/derived/bootstrap_2019.rds")    # rails: human/persist
#
# NB: requires the bundles to carry qwen-72b / gemma-27b (base) and qwen-72b-ft-raw /
# gemma-27b-ft-raw cells. Until analysis/06 + 13 ingest those runs the function renders the
# Llama rows only (the filters simply return fewer models) — no error, just a partial figure.
# Call once per year (pass the 2019 bundles for the main figure, the 2023 bundles for the
# appendix replication).
fig_crossmodel_landscape <- function(exp_bundle, greedy_bundle,
                                     band = c("human_loo", "none"),
                                     base_readout = c("greedy", "both", "mean"),
                                     ft_conds = c("codebook", "evidence-zeroshot",
                                                  "anonymized-zeroshot", "summarized-zeroshot")) {
  band         <- match.arg(band)
  base_readout <- match.arg(base_readout)
  sesoi       <- exp_bundle$sesoi
  human_mae   <- greedy_bundle$human_ref$human_mae
  persist_mae <- greedy_bundle$persist_ref$persist_mae

  base_models <- c("llama-70b", "qwen-72b", "gemma-27b")
  ft_models   <- c("llama-70b-ft-raw", "qwen-72b-ft-raw", "gemma-27b-ft-raw")
  base_conds  <- c("codebook", "evidence", "anonymized", "summarized")
  cond_disp   <- c(codebook = "Codebook", evidence = "Raw Text",
                   anonymized = "Anonymized", summarized = "Summarized")

  # Rows are the plain input names in BOTH blocks; the Base/Fine-tuned split becomes a facet
  # strip (the meta-label) rather than an "FT" prefix on the fine-tuned rows.
  cond_lv <- c("Summarized", "Anonymized", "Raw Text", "Codebook")  # first level plots at bottom

  family_of <- function(mk) dplyr::case_when(
    grepl("^llama", mk) ~ "Llama 70B",
    grepl("^qwen",  mk) ~ "Qwen 72B",
    grepl("^gemma", mk) ~ "Gemma 27B",
    TRUE ~ NA_character_)

  # base ladder + FT-raw ladder for one readout's per-cell CI table
  pick <- function(ci, readout) {
    base <- ci |>
      dplyr::filter(model_key %in% base_models, condition %in% base_conds) |>
      dplyr::mutate(row = unname(cond_disp[condition]), block = "Base")
    ft <- ci |>
      dplyr::filter(model_key %in% ft_models, condition %in% ft_conds) |>
      dplyr::mutate(row = unname(cond_disp[canon_col(condition)]), block = "Fine-tuned")
    dplyr::bind_rows(base, ft) |> dplyr::mutate(readout = readout)
  }

  cells <- dplyr::bind_rows(
    pick(exp_bundle$greedy_ci_rerun, "Greedy (mode)"),
    pick(exp_bundle$exp_ci,          "Expectation (mean)")
  ) |>
    dplyr::mutate(
      model   = factor(family_of(model_key), levels = names(model_pal)),
      row     = factor(row, levels = cond_lv),
      block   = factor(block, levels = c("Base", "Fine-tuned")),
      readout = factor(readout, levels = c("Greedy (mode)", "Expectation (mean)"))
    )

  # The greedy/mean split is the FT-block story; in the base block the two readouts differ by
  # < 0.02 MAE (~1/9 SESOI), so plotting both there is clutter. Default base_readout = "greedy"
  # keeps only the confirmatory readout in the Base block (the FT block always keeps both);
  # "both" restores the overlay.
  if (base_readout != "both") {
    keep <- if (base_readout == "greedy") "Greedy (mode)" else "Expectation (mean)"
    cells <- dplyr::filter(cells, !(block == "Base" & readout != keep))
  }

  # Reference labels appear once, pinned to the top (Base) facet so they don't repeat per panel.
  ref_lab <- tibble::tibble(
    block = factor("Base", levels = c("Base", "Fine-tuned")),
    x     = c(persist_mae, human_mae),
    label = c("Naive model", "±SESOI of human reference"),
    hjust = c(-0.07, 0.5)
  )

  # Capless point-ranges (line + point, no end whiskers): minimal ornament, and a row holding a
  # single model reads the same as a dodged trio. Shape still encodes the readout (greedy/mean).
  dodge <- position_dodge(width = 0.6)

  p <- ggplot(cells, aes(ai_mae, row, color = model, shape = readout, group = model))
  if (band == "human_loo") {
    p <- p +
      annotate("rect", xmin = human_mae - sesoi, xmax = human_mae + sesoi,
               ymin = -Inf, ymax = Inf, fill = "grey85", alpha = 0.55)
  }
  p +
    geom_vline(xintercept = persist_mae, linetype = "dashed",  color = "grey40") +
    geom_vline(xintercept = human_mae,   linetype = "longdash", color = "grey40") +
    geom_text(data = ref_lab, aes(x = x, y = Inf, label = label, hjust = hjust),
              vjust = -0.5, color = "grey40", size = 2.9, inherit.aes = FALSE) +
    geom_linerange(aes(xmin = ai_lo, xmax = ai_hi), orientation = "y",
                   linewidth = 0.5, alpha = 0.7, position = dodge) +
    geom_point(size = 2.3, stroke = 0.9, position = dodge) +
    facet_grid(rows = vars(block), scales = "free_y", space = "free", switch = "y") +
    scale_color_manual(values = model_pal, name = NULL) +
    scale_shape_manual(values = readout_shape, name = NULL) +
    coord_cartesian(clip = "off") +
    labs(x = "AI Mean Absolute Error", y = NULL) +
    theme_minimal(base_size = 12) +
    theme(legend.position = "top", legend.justification = "left", legend.box = "vertical",
          legend.box.just = "left", legend.margin = margin(b = 0),
          panel.grid.major.y = element_blank(), plot.title.position = "plot",
          panel.spacing.y = unit(0.9, "lines"),
          strip.placement = "outside",
          strip.background = element_blank(),
          strip.text.y.left = element_text(angle = 0, face = "bold", hjust = 1),
          plot.margin = margin(t = 16, r = 8, b = 6, l = 6))
}

# Fig 2 — the difficulty-tracking twin of Fig 1. Same rows (base block over FT-raw block, each
# on the four inputs) and the same color = MODEL encoding, but the x-axis is the Test-3 slope of
# AI error on case difficulty h_c instead of MAE, and the reference is the human self-reference
# slope = 1 instead of the human MAE line. Fig 1's crowded column of CIs hugging the human MAE
# line says "on average error they're all about equally close"; this figure cracks that column
# open on the dimension MAE can't see — does the synthetic coder err on the same cases a human
# finds hard (slope → 1) or lean on a prior (slope flat)? Greedy readout only, by design: the
# slope is a panel-member question, so there is no shape channel here.
#
#   dm_bundle <- readRDS("data/derived/distmatch_slope_2019.rds")  # dm_slope: per-cell slope + CI
fig_crossmodel_slope <- function(dm_bundle,
                                 ft_conds = c("codebook", "evidence-zeroshot",
                                              "anonymized-zeroshot", "summarized-zeroshot")) {
  cells0 <- dm_bundle$dm_slope

  base_models <- c("llama-70b", "qwen-72b", "gemma-27b")
  ft_models   <- c("llama-70b-ft-raw", "qwen-72b-ft-raw", "gemma-27b-ft-raw")
  base_conds  <- c("codebook", "evidence", "anonymized", "summarized")
  cond_disp   <- c(codebook = "Codebook", evidence = "Raw Text",
                   anonymized = "Anonymized", summarized = "Summarized")

  # bottom-to-top: FT block below, base block on top — identical row order to Fig 1.
  row_lv <- c("FT · Summarized", "FT · Anonymized", "FT · Raw Text", "FT · Codebook",
              "Summarized", "Anonymized", "Raw Text", "Codebook")

  family_of <- function(mk) dplyr::case_when(
    grepl("^llama", mk) ~ "Llama 70B",
    grepl("^qwen",  mk) ~ "Qwen 72B",
    grepl("^gemma", mk) ~ "Gemma 27B",
    TRUE ~ NA_character_)

  # Rows are the plain input names in BOTH blocks; the Base/Fine-tuned distinction moves to a
  # facet strip (the meta-label / bracket) instead of an "FT ·" prefix, so the two blocks read
  # as the same four inputs under two headings.
  cond_lv <- c("Summarized", "Anonymized", "Raw Text", "Codebook")  # first level plots at bottom
  base <- cells0 |>
    dplyr::filter(model_key %in% base_models, condition %in% base_conds) |>
    dplyr::mutate(row = unname(cond_disp[condition]), block = "Base")
  ft <- cells0 |>
    dplyr::filter(model_key %in% ft_models, condition %in% ft_conds) |>
    dplyr::mutate(row = unname(cond_disp[canon_col(condition)]), block = "Fine-tuned")
  cells <- dplyr::bind_rows(base, ft) |>
    dplyr::mutate(model = factor(family_of(model_key), levels = names(model_pal)),
                  row   = factor(row, levels = cond_lv),
                  block = factor(block, levels = c("Base", "Fine-tuned")))

  # Capless point-ranges (point + line, no end whiskers): minimal ornament, and — unlike capped
  # error bars — a row holding a single model (the base block until the Qwen/Gemma base runs land)
  # reads the same as a dodged trio, so no lone "TIE fighter" bars.
  dodge <- position_dodge(width = 0.6)

  ggplot(cells, aes(est, row, color = model, group = model)) +
    geom_vline(xintercept = 1, linetype = "longdash", color = "grey40") +
    geom_pointrange(aes(xmin = lo, xmax = hi), orientation = "y",
                    size = 0.45, linewidth = 0.5, position = dodge) +
    facet_grid(rows = vars(block), scales = "free_y", space = "free", switch = "y") +
    scale_color_manual(values = model_pal, name = NULL) +
    scale_x_continuous(expand = expansion(mult = c(0.04, 0.02))) +
    coord_cartesian(clip = "off") +
    labs(x = expression("difficulty-tracking slope of AI error on  " * h[c]),
         y = NULL) +
    theme_minimal(base_size = 12) +
    theme(legend.position = "top", legend.justification = "left",
          panel.grid.major.y = element_blank(), plot.title.position = "plot",
          panel.spacing.y = unit(0.9, "lines"),
          strip.placement = "outside",
          strip.background = element_blank(),
          strip.text.y.left = element_text(angle = 0, face = "bold", hjust = 1))
}

# Fig 2 (left panel) — the difficulty slope drawn as a shape. Mean error vs case difficulty for a
# steep exemplar and a flat exemplar, against the human reference curve — which lies on y = x
# because difficulty h_c is *defined* as the human error on the case (so the human's error equals
# the case's difficulty). x is a property of the case (how hard humans found it); y is whichever
# coder's error we plot. `feature` = two "model_key|condition" cells to draw as curves (default:
# the steepest and flattest cells, i.e. the top and bottom of the coefficient panel). Revisit the
# defaults once the Qwen/Gemma base runs land and the flattest cell may change.
#
#   dm_bundle <- readRDS("data/derived/distmatch_slope_2019.rds")  # needs dm_fine + he_fine
fig_slope_curve <- function(dm_bundle,
                            feature = c("qwen-72b-ft-raw|codebook", "llama-70b|summarized"),
                            xmax = 1.6) {
  family_of <- function(mk) dplyr::case_when(
    grepl("^llama", mk) ~ "Llama 70B", grepl("^qwen", mk) ~ "Qwen 72B",
    grepl("^gemma", mk) ~ "Gemma 27B", TRUE ~ NA_character_)
  cond_disp <- c(codebook = "Codebook", evidence = "Raw Text",
                 anonymized = "Anonymized", summarized = "Summarized")
  lab_of <- function(cell) {
    mk <- sub("\\|.*$", "", cell); cond <- sub("^[^|]*\\|", "", cell)
    block <- if (grepl("-ft-", mk)) "fine-tuned" else "base"
    paste0(family_of(mk), " · ", block, " · ", unname(cond_disp[canon_col(cond)]))
  }
  he  <- dm_bundle$he_fine
  sel <- dm_bundle$dm_fine |>
    dplyr::filter(cell %in% feature) |>
    dplyr::mutate(model = family_of(model_key), label = vapply(cell, lab_of, character(1)))
  # each featured cell keeps its model's color (ties to panel B); human = grey
  lab_levels <- unique(sel$label)
  pal <- c(setNames(unname(model_pal[sel$model[match(lab_levels, sel$label)]]), lab_levels),
           "Human coder" = "grey30")
  sel$label <- factor(sel$label, levels = lab_levels)

  ggplot() +
    geom_ribbon(data = he,  aes(x, ymin = lo, ymax = hi), fill = "grey70", alpha = 0.30) +
    geom_line(data = he,   aes(x, est, color = "Human coder"), linewidth = 1.0) +
    geom_ribbon(data = sel, aes(x, ymin = lo, ymax = hi, fill = label), alpha = 0.18) +
    geom_line(data = sel,  aes(x, est, color = label), linewidth = 1.0) +
    scale_color_manual(values = pal, name = NULL) +
    scale_fill_manual(values = pal, guide = "none") +
    coord_cartesian(xlim = c(0, xmax), ylim = c(0, xmax)) +
    labs(x = "Case difficulty — typical human error (rating points)",
         y = "Mean absolute error (rating points)") +
    theme_minimal(base_size = 12) +
    theme(legend.position = "top", legend.justification = "left", legend.direction = "vertical",
          panel.grid.minor = element_blank(), plot.title.position = "plot")
}

# Fig 2 (composite) — the two panels side by side: the curve (what the slope measures) and the
# coefficient plot (every model ranked by that slope). Requires the curve fields in the bundle.
fig_crossmodel_slope_2panel <- function(dm_bundle,
                                        feature = c("qwen-72b-ft-raw|codebook",
                                                    "llama-70b|summarized"),
                                        ft_conds = c("codebook", "evidence-zeroshot",
                                                     "anonymized-zeroshot", "summarized-zeroshot")) {
  fig_slope_curve(dm_bundle, feature = feature) + fig_crossmodel_slope(dm_bundle, ft_conds = ft_conds) +
    patchwork::plot_layout(widths = c(1, 1.05)) +
    patchwork::plot_annotation(tag_levels = "A")
}

# Fig 3 (left panel) — signed deviation across the democracy gradient. y = AI rating minus the
# human panel mean; the dotted zero line is the panel-member target (a real coder sums to 0 per
# bin by construction), the dashed grey line is the V-Dem IRT target expressed on the same axis
# (mean(ord - panel_mean) per bin), so featured cells can be read against BOTH references. An
# upward slope = exaggerates the regime gradient; downward = compresses. `feature` = cells drawn
# as curves (default: the gap extremes — flattest and steepest of the plotted cells). Uses dm_q +
# irt_ref_q from build_signeddev.R.
fig_signeddev_curve <- function(sd_bundle,
                                feature = c("gemma-27b-ft-raw|anonymized-zeroshot",
                                            "llama-70b|evidence")) {
  sesoi <- sd_bundle$sesoi
  family_of <- function(mk) dplyr::case_when(
    grepl("^llama", mk) ~ "Llama 70B", grepl("^qwen", mk) ~ "Qwen 72B",
    grepl("^gemma", mk) ~ "Gemma 27B", TRUE ~ NA_character_)
  cond_disp <- c(codebook = "Codebook", evidence = "Raw Text",
                 anonymized = "Anonymized", summarized = "Summarized")
  lab_of <- function(cell) {
    mk <- sub("\\|.*$", "", cell); cond <- sub("^[^|]*\\|", "", cell)
    block <- if (grepl("-ft-", mk)) "fine-tuned" else "base"
    paste0(family_of(mk), " · ", block, " · ", unname(cond_disp[canon_col(cond)]))
  }
  sel <- sd_bundle$dm_q |>
    dplyr::filter(cell %in% feature) |>
    dplyr::mutate(model = family_of(model_key), label = vapply(cell, lab_of, character(1)))
  lab_levels <- unique(sel$label)
  pal <- setNames(unname(model_pal[sel$model[match(lab_levels, sel$label)]]), lab_levels)
  sel$label <- factor(sel$label, levels = lab_levels)
  irt <- sd_bundle$irt_ref_q

  ggplot() +
    annotate("rect", xmin = -Inf, xmax = Inf, ymin = -sesoi, ymax = sesoi,
             fill = "grey85", alpha = 0.55) +
    geom_hline(yintercept = 0, linetype = "dotted", color = "grey30", linewidth = 0.4) +
    geom_line(data = irt, aes(bin, est), linetype = "dashed", color = "grey45", linewidth = 0.7) +
    annotate("text", x = 3, y = irt$est[irt$bin == 3], label = "V-Dem IRT",
             color = "grey25", size = 2.9, hjust = 1, vjust = -0.9) +
    geom_ribbon(data = sel, aes(bin, ymin = lo, ymax = hi, fill = label), alpha = 0.18) +
    geom_line(data = sel, aes(bin, est, color = label), linewidth = 1.0) +
    geom_pointrange(data = sel, aes(bin, est, ymin = lo, ymax = hi, color = label), size = 0.3) +
    scale_color_manual(values = pal, name = NULL) +
    scale_fill_manual(values = pal, guide = "none") +
    scale_x_continuous(breaks = 1:5) +
    labs(x = "democracy quintile (1 = most autocratic → 5 = most democratic)",
         y = "signed deviation (AI − panel mean)") +
    theme_minimal(base_size = 12) +
    theme(legend.position = "top", legend.justification = "left", legend.direction = "vertical",
          panel.grid.minor = element_blank(), plot.title.position = "plot")
}

# Fig 3 (right panel) — exaggeration gap (Q5 − Q1 signed deviation) per cell, the twin of Fig 2's
# coefficient panel. Reference at 0 (no tilt); positive = exaggerates the gradient, negative =
# compresses. Same Base/Fine-tuned strips, plain input rows, capless point-ranges, color = model.
fig_signeddev_gap <- function(sd_bundle,
                              ft_conds = c("codebook", "evidence-zeroshot",
                                           "anonymized-zeroshot", "summarized-zeroshot")) {
  cells0 <- sd_bundle$dm_eg_q
  base_models <- c("llama-70b", "qwen-72b", "gemma-27b")
  ft_models   <- c("llama-70b-ft-raw", "qwen-72b-ft-raw", "gemma-27b-ft-raw")
  base_conds  <- c("codebook", "evidence", "anonymized", "summarized")
  cond_disp   <- c(codebook = "Codebook", evidence = "Raw Text",
                   anonymized = "Anonymized", summarized = "Summarized")
  cond_lv <- c("Summarized", "Anonymized", "Raw Text", "Codebook")
  family_of <- function(mk) dplyr::case_when(
    grepl("^llama", mk) ~ "Llama 70B", grepl("^qwen", mk) ~ "Qwen 72B",
    grepl("^gemma", mk) ~ "Gemma 27B", TRUE ~ NA_character_)

  base <- cells0 |> dplyr::filter(model_key %in% base_models, condition %in% base_conds) |>
    dplyr::mutate(row = unname(cond_disp[condition]), block = "Base")
  ft <- cells0 |> dplyr::filter(model_key %in% ft_models, condition %in% ft_conds) |>
    dplyr::mutate(row = unname(cond_disp[canon_col(condition)]), block = "Fine-tuned")
  cells <- dplyr::bind_rows(base, ft) |>
    dplyr::mutate(model = factor(family_of(model_key), levels = names(model_pal)),
                  row   = factor(row, levels = cond_lv),
                  block = factor(block, levels = c("Base", "Fine-tuned")))
  sesoi <- sd_bundle$sesoi
  dodge <- position_dodge(width = 0.6)

  ggplot(cells, aes(est, row, color = model, group = model)) +
    annotate("rect", xmin = -sesoi, xmax = sesoi, ymin = -Inf, ymax = Inf,
             fill = "grey85", alpha = 0.55) +
    geom_vline(xintercept = 0, linetype = "dashed", color = "grey40") +
    geom_pointrange(aes(xmin = lo, xmax = hi), orientation = "y",
                    size = 0.45, linewidth = 0.5, position = dodge) +
    facet_grid(rows = vars(block), scales = "free_y", space = "free", switch = "y") +
    scale_color_manual(values = model_pal, name = NULL) +
    coord_cartesian(clip = "off") +
    labs(x = "exaggeration gap (Q5 − Q1 signed deviation)", y = NULL) +
    theme_minimal(base_size = 12) +
    theme(legend.position = "top", legend.justification = "left",
          panel.grid.major.y = element_blank(), plot.title.position = "plot",
          panel.spacing.y = unit(0.9, "lines"),
          strip.placement = "outside", strip.background = element_blank(),
          strip.text.y.left = element_text(angle = 0, face = "bold", hjust = 1))
}

# Fig 3 (composite) — the gradient curve (what the exaggeration gap measures) beside the gap
# coefficient plot (every model ranked). Requires signeddev_xmodel_{year}.rds.
fig_crossmodel_signeddev_2panel <- function(sd_bundle,
                                            feature = c("gemma-27b-ft-raw|anonymized-zeroshot",
                                                        "llama-70b|evidence"),
                                            ft_conds = c("codebook", "evidence-zeroshot",
                                                         "anonymized-zeroshot", "summarized-zeroshot")) {
  fig_signeddev_curve(sd_bundle, feature = feature) + fig_signeddev_gap(sd_bundle, ft_conds = ft_conds) +
    patchwork::plot_layout(widths = c(1, 1.05)) +
    patchwork::plot_annotation(tag_levels = "A")
}

# Fig 3 (regime variant, left panel) — signed deviation across V-Dem's Regimes of the World
# (v2x_regime: 0 closed autocracy .. 3 liberal democracy, stored as ri = v2x_regime + 1 so bins run
# 1..4). Same construction as fig_signeddev_curve but reads dm_r / irt_ref_r — the regime-type cut
# build_signeddev.R computes alongside the democracy-quintile cut.
fig_signeddev_curve_regime <- function(sd_bundle,
                                       feature = c("gemma-27b-ft-raw|anonymized-zeroshot",
                                                   "llama-70b|evidence")) {
  sesoi <- sd_bundle$sesoi
  family_of <- function(mk) dplyr::case_when(
    grepl("^llama", mk) ~ "Llama 70B", grepl("^qwen", mk) ~ "Qwen 72B",
    grepl("^gemma", mk) ~ "Gemma 27B", TRUE ~ NA_character_)
  cond_disp <- c(codebook = "Codebook", evidence = "Raw Text",
                 anonymized = "Anonymized", summarized = "Summarized")
  lab_of <- function(cell) {
    mk <- sub("\\|.*$", "", cell); cond <- sub("^[^|]*\\|", "", cell)
    block <- if (grepl("-ft-", mk)) "fine-tuned" else "base"
    paste0(family_of(mk), " · ", block, " · ", unname(cond_disp[canon_col(cond)]))
  }
  sel <- sd_bundle$dm_r |>
    dplyr::filter(cell %in% feature) |>
    dplyr::mutate(model = family_of(model_key), label = vapply(cell, lab_of, character(1)))
  lab_levels <- unique(sel$label)
  pal <- setNames(unname(model_pal[sel$model[match(lab_levels, sel$label)]]), lab_levels)
  sel$label <- factor(sel$label, levels = lab_levels)
  irt <- sd_bundle$irt_ref_r
  regime_lv <- c("Closed\nautocracy", "Electoral\nautocracy", "Electoral\ndemocracy", "Liberal\ndemocracy")

  ggplot() +
    annotate("rect", xmin = -Inf, xmax = Inf, ymin = -sesoi, ymax = sesoi,
             fill = "grey85", alpha = 0.55) +
    geom_hline(yintercept = 0, linetype = "dotted", color = "grey30", linewidth = 0.4) +
    geom_line(data = irt, aes(bin, est), linetype = "dashed", color = "grey45", linewidth = 0.7) +
    annotate("text", x = 2, y = irt$est[irt$bin == 2], label = "V-Dem IRT",
             color = "grey25", size = 2.9, hjust = 1, vjust = -0.9) +
    geom_ribbon(data = sel, aes(bin, ymin = lo, ymax = hi, fill = label), alpha = 0.18) +
    geom_line(data = sel, aes(bin, est, color = label), linewidth = 1.0) +
    geom_pointrange(data = sel, aes(bin, est, ymin = lo, ymax = hi, color = label), size = 0.3) +
    scale_color_manual(values = pal, name = NULL) +
    scale_fill_manual(values = pal, guide = "none") +
    scale_x_continuous(breaks = 1:4, labels = regime_lv) +
    labs(x = "regime type (V-Dem Regimes of the World)",
         y = "signed deviation (AI − panel mean)") +
    theme_minimal(base_size = 12) +
    theme(legend.position = "top", legend.justification = "left", legend.direction = "vertical",
          panel.grid.minor = element_blank(), plot.title.position = "plot")
}

# Fig 3 (regime variant, right panel) — exaggeration gap (liberal democracy − closed autocracy
# signed deviation) per cell, the regime-cut twin of fig_signeddev_gap. Reads dm_eg_r.
fig_signeddev_gap_regime <- function(sd_bundle,
                                     ft_conds = c("codebook", "evidence-zeroshot",
                                                  "anonymized-zeroshot", "summarized-zeroshot")) {
  cells0 <- sd_bundle$dm_eg_r
  base_models <- c("llama-70b", "qwen-72b", "gemma-27b")
  ft_models   <- c("llama-70b-ft-raw", "qwen-72b-ft-raw", "gemma-27b-ft-raw")
  base_conds  <- c("codebook", "evidence", "anonymized", "summarized")
  cond_disp   <- c(codebook = "Codebook", evidence = "Raw Text",
                   anonymized = "Anonymized", summarized = "Summarized")
  cond_lv <- c("Summarized", "Anonymized", "Raw Text", "Codebook")
  family_of <- function(mk) dplyr::case_when(
    grepl("^llama", mk) ~ "Llama 70B", grepl("^qwen", mk) ~ "Qwen 72B",
    grepl("^gemma", mk) ~ "Gemma 27B", TRUE ~ NA_character_)

  base <- cells0 |> dplyr::filter(model_key %in% base_models, condition %in% base_conds) |>
    dplyr::mutate(row = unname(cond_disp[condition]), block = "Base")
  ft <- cells0 |> dplyr::filter(model_key %in% ft_models, condition %in% ft_conds) |>
    dplyr::mutate(row = unname(cond_disp[canon_col(condition)]), block = "Fine-tuned")
  cells <- dplyr::bind_rows(base, ft) |>
    dplyr::mutate(model = factor(family_of(model_key), levels = names(model_pal)),
                  row   = factor(row, levels = cond_lv),
                  block = factor(block, levels = c("Base", "Fine-tuned")))
  sesoi <- sd_bundle$sesoi
  dodge <- position_dodge(width = 0.6)

  ggplot(cells, aes(est, row, color = model, group = model)) +
    annotate("rect", xmin = -sesoi, xmax = sesoi, ymin = -Inf, ymax = Inf,
             fill = "grey85", alpha = 0.55) +
    geom_vline(xintercept = 0, linetype = "dashed", color = "grey40") +
    geom_pointrange(aes(xmin = lo, xmax = hi), orientation = "y",
                    size = 0.45, linewidth = 0.5, position = dodge) +
    facet_grid(rows = vars(block), scales = "free_y", space = "free", switch = "y") +
    scale_color_manual(values = model_pal, name = NULL) +
    coord_cartesian(clip = "off") +
    labs(x = "exaggeration gap (liberal democracy − closed autocracy signed deviation)", y = NULL) +
    theme_minimal(base_size = 12) +
    theme(legend.position = "top", legend.justification = "left",
          panel.grid.major.y = element_blank(), plot.title.position = "plot",
          panel.spacing.y = unit(0.9, "lines"),
          strip.placement = "outside", strip.background = element_blank(),
          strip.text.y.left = element_text(angle = 0, face = "bold", hjust = 1))
}

# Fig 3 (regime variant, composite) — the gradient curve beside the gap coefficient plot, using
# V-Dem Regimes of the World instead of democracy quintiles. Requires signeddev_xmodel_{year}.rds.
fig_crossmodel_signeddev_2panel_regime <- function(sd_bundle,
                                                   feature = c("gemma-27b-ft-raw|anonymized-zeroshot",
                                                               "llama-70b|evidence"),
                                                   ft_conds = c("codebook", "evidence-zeroshot",
                                                                "anonymized-zeroshot", "summarized-zeroshot")) {
  fig_signeddev_curve_regime(sd_bundle, feature = feature) +
    fig_signeddev_gap_regime(sd_bundle, ft_conds = ft_conds) +
    patchwork::plot_layout(widths = c(1, 1.05)) +
    patchwork::plot_annotation(tag_levels = "A")
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
      # Llama-only grid (Base + its three FT variants); the cross-family models (qwen/gemma
      # ft-raw) live in Fig 1, and without this filter they'd map to an NA facet here.
      filter(model_key %in% names(model_disp)) |>
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

  # readout = shape (solid ● greedy, open ○ mean), matching the cross-model Fig 1 convention
  # (readout_shape). This grid is entirely Llama (Base + its three FT variants), so its marks
  # carry the Llama blue from model_pal — keeping "Llama = blue" consistent with Fig 1 and the
  # 2023 replication rather than rendering a lone monochrome figure.
  ink <- unname(model_pal["Llama 70B"])
  p <- ggplot(cells, aes(ai_mae, cond, shape = readout))
  if (band == "human_loo") {
    p <- p + annotate("rect", xmin = human_mae - sesoi, xmax = human_mae + sesoi,
                      ymin = -Inf, ymax = Inf, fill = "grey85", alpha = 0.55)
  }
  p +
    geom_vline(xintercept = persist_mae, linetype = "dashed",  color = "grey40") +
    geom_vline(xintercept = human_mae,   linetype = "longdash", color = "grey40") +
    geom_errorbar(aes(xmin = ai_lo, xmax = ai_hi), orientation = "y",
                  width = 0.25, linewidth = 0.6, color = ink, position = position_dodge(width = 0.55)) +
    geom_point(size = 2.2, color = ink, position = position_dodge(width = 0.55)) +
    # ring the diagonal (each FT model's own training input); a square keeps it distinct from the
    # open-circle mean marker so a ringed mean point doesn't read as two concentric circles.
    geom_point(data = diag_pts, aes(group = readout), inherit.aes = TRUE,
               shape = 0, size = 4.6, stroke = 0.7, color = "grey45",
               position = position_dodge(width = 0.55), show.legend = FALSE) +
    geom_text(data = rail_lab, aes(x = x, y = cond, label = label, hjust = hj),
              inherit.aes = FALSE, color = "grey40", size = 2.7, vjust = -1.2) +
    facet_wrap(~model, ncol = 1, strip.position = "top") +
    scale_shape_manual(values = readout_shape, name = NULL) +
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
