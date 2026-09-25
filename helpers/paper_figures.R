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

# The MAE landscape (single-model) — synthetic-coder MAE landscape, greedy (mode) vs expectation (mean).
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

# The MAE landscape, cross-family (chunk `fig-crossmodel`) — synthetic-coder MAE across three model families, both readouts on one
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

  # Reference labels appear once, pinned to the Base facet so they don't repeat per panel.
  # Naive-model and human-reference labels sit just above the top (Codebook) row, right of
  # their own lines — clear of the CIs and of the sightline from axis to data, still inside
  # the panel. The SESOI-band label stays above the panel, centred on the band.
  line_lab <- tibble::tibble(
    block = factor("Base", levels = c("Base", "Fine-tuned")),
    x     = c(persist_mae + 0.012, human_mae + 0.012),
    y     = "Codebook",
    label = c("Naive model", "Human reference")
  )
  band_lab <- tibble::tibble(
    block = factor("Base", levels = c("Base", "Fine-tuned")),
    x     = human_mae,
    label = "±SESOI band"
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
    geom_text(data = line_lab, aes(x = x, y = y, label = label),
              position = position_nudge(y = 0.4), hjust = 0, vjust = 0.5,
              color = "grey40", size = 2.9, inherit.aes = FALSE) +
    geom_text(data = band_lab, aes(x = x, y = Inf, label = label),
              hjust = 0.5, vjust = -0.5, color = "grey40", size = 2.9, inherit.aes = FALSE) +
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

# Panel-A featured cells, chosen from exactly the cells Panel B plots (base x {codebook, evidence,
# anonymized, summarized}; FT-raw x ft_conds). Returns c(steep_cell, flat_cell) as
# "model_key|condition" strings; a non-NULL `feature` passes straight through (manual override).
#
#   steep = max of the Panel-B coefficient (`coef_tbl`: dm_slope / dm_eg_q / dm_eg_r).
#   flat  = if `curve_tbl` (dm_q / dm_r) is given, the best-CALIBRATED cell — min RMS deviation
#           from 0 across the per-bin gradient. The exaggeration gap is a Q5-Q1 *difference*, so
#           it is blind to level: a uniformly biased-low flat line scores near-zero gap. Ranking
#           the flat pick by distance-from-target instead avoids featuring that misleading curve.
#           Without `curve_tbl` (difficulty slope, where the metric IS the slope and the curve
#           starts near the origin) the flat pick is just the min coefficient.
# The cells a Panel B plots: base x {codebook, evidence, anonymized, summarized}, FT-raw x ft_conds.
# Shared by the featured-cell pickers and the Panel A grey context traces.
.panelB_pool <- function(tbl, ft_conds) {
  base_models <- c("llama-70b", "qwen-72b", "gemma-27b")
  ft_models   <- c("llama-70b-ft-raw", "qwen-72b-ft-raw", "gemma-27b-ft-raw")
  base_conds  <- c("codebook", "evidence", "anonymized", "summarized")
  dplyr::filter(tbl, (model_key %in% base_models & condition %in% base_conds) |
                     (model_key %in% ft_models   & condition %in% ft_conds))
}

.panelA_feature <- function(coef_tbl, ft_conds, feature = NULL, curve_tbl = NULL) {
  if (!is.null(feature)) return(feature)
  in_pool <- function(tbl) .panelB_pool(tbl, ft_conds)
  fam <- function(cell) sub("-.*$", "", sub("\\|.*$", "", cell))  # llama / qwen / gemma

  pool  <- in_pool(coef_tbl)
  steep <- pool$cell[which.max(pool$est)]

  # Flat candidates, best-first: by calibration (RMS deviation from 0 across the gradient) when a
  # curve table is supplied, else by the coefficient itself.
  if (is.null(curve_tbl)) {
    ord <- pool$cell[order(pool$est)]
  } else {
    cp  <- in_pool(curve_tbl)
    rms <- tapply(cp$est, cp$cell, function(v) sqrt(mean(v^2, na.rm = TRUE)))
    ord <- names(sort(rms))
  }
  # Prefer a flat exemplar from a different model family than the steep one so Panel A stays a
  # two-colour read; the top-ranked candidates are near-tied on calibration anyway. Fall back to
  # the best candidate if every option shares the family.
  diff_fam <- ord[vapply(ord, function(c) fam(c) != fam(steep), logical(1))]
  flat <- if (length(diff_fam)) diff_fam[1] else ord[1]

  c(steep, flat)
}

# The signed-deviation figure's Panel A features three cells that illustrate the distinct patterns the average-signed-
# deviation panel (Panel B) collapses into one number:
#   calibrated = min RMS deviation from 0 across the gradient  (from cut_tbl: dm_q / dm_r)
#   steepest   = max exaggeration gap Q5-Q1 / lib.dem - closed aut.  (from gap_tbl: dm_eg_q / dm_eg_r)
#   harshest   = min average signed deviation  (from ov_tbl: dm_ov)
# All three drawn from the Panel B pool. A non-NULL `feature` passes straight through.
.signeddev_feature3 <- function(cut_tbl, gap_tbl, ov_tbl, ft_conds, feature = NULL) {
  if (!is.null(feature)) return(feature)
  fam <- function(cell) sub("-.*$", "", sub("\\|.*$", "", cell))  # llama / qwen / gemma
  cut <- .panelB_pool(cut_tbl, ft_conds)
  gap <- .panelB_pool(gap_tbl, ft_conds)
  ov  <- .panelB_pool(ov_tbl,  ft_conds)
  # Prefer one cell per model family so Panel A stays a three-colour read; fall back to the raw
  # pick when no distinct-family option is left.
  pick_diff <- function(ranked, used) {
    d <- ranked[!vapply(ranked, function(c) fam(c) %in% used, logical(1))]
    if (length(d)) d[1] else ranked[1]
  }
  rms        <- tapply(cut$est, cut$cell, function(v) sqrt(mean(v^2, na.rm = TRUE)))
  calibrated <- names(which.min(rms))
  steepest   <- pick_diff(gap$cell[order(-gap$est)], fam(calibrated))
  harshest   <- pick_diff(ov$cell[order(ov$est)], c(fam(calibrated), fam(steepest)))
  unique(c(calibrated, steepest, harshest))
}

# The difficulty-slope figure (chunk `fig-crossmodel-slope`) — the twin of the MAE landscape. Same rows (base block over FT-raw block, each
# on the four inputs) and the same color = MODEL encoding, but the x-axis is the Test-3 slope of
# AI error on case difficulty h_c instead of MAE, and the reference is the human self-reference
# slope = 1 instead of the human MAE line. The MAE landscape's crowded column of CIs hugging the human MAE
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

  # bottom-to-top: FT block below, base block on top — identical row order to the MAE landscape.
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
  ref_lab <- tibble::tibble(block = factor("Base", levels = c("Base", "Fine-tuned")),
                            x = 0.985, y = "Codebook", label = "Human coder")

  ggplot(cells, aes(est, row, color = model, group = model)) +
    geom_vline(xintercept = 1, linetype = "longdash", color = "grey40") +
    geom_text(data = ref_lab, aes(x = x, y = y, label = label),
              position = position_nudge(y = 0.4), hjust = 1, vjust = 0.5,
              color = "grey40", size = 2.9, inherit.aes = FALSE) +
    geom_pointrange(aes(xmin = lo, xmax = hi), orientation = "y",
                    size = 0.45, linewidth = 0.5, position = dodge) +
    facet_grid(rows = vars(block), scales = "free_y", space = "free", switch = "y") +
    scale_color_manual(values = model_pal, name = NULL) +
    scale_x_continuous(expand = expansion(mult = c(0.04, 0.02))) +
    coord_cartesian(clip = "off") +
    labs(title = "B. Average Difficulty Tracking Error",
         x = "AI Case Difficulty Slope", y = NULL) +
    theme_minimal(base_size = 12) +
    theme(legend.position = "top", legend.justification = "left",
          panel.grid.major.y = element_blank(), plot.title.position = "plot",
          plot.title = element_text(face = "bold"),
          axis.title.x = element_text(margin = margin(t = 7)),
          panel.spacing.y = unit(0.9, "lines"),
          strip.placement = "outside",
          strip.background = element_blank(),
          strip.text.y.left = element_text(angle = 0, face = "bold", hjust = 1))
}

# Difficulty-slope figure (left panel) — the difficulty slope drawn as a shape. Mean error vs case difficulty for a
# steep exemplar and a flat exemplar, against the human reference curve — which lies on y = x
# because difficulty h_c is *defined* as the human error on the case (so the human's error equals
# the case's difficulty). x is a property of the case (how hard humans found it); y is whichever
# coder's error we plot. `feature` = two "model_key|condition" cells to draw as curves; default
# NULL auto-selects the top and bottom of the coefficient panel (max / min slope) from the cells
# Panel B plots under this ft_conds trim. Pass an explicit pair to override.
#
#   dm_bundle <- readRDS("data/derived/distmatch_slope_2019.rds")  # needs dm_fine + he_fine
fig_slope_curve <- function(dm_bundle,
                            feature = NULL,
                            ft_conds = c("codebook", "evidence-zeroshot",
                                         "anonymized-zeroshot", "summarized-zeroshot"),
                            xmax = 1.6) {
  feature <- .panelA_feature(dm_bundle$dm_slope, ft_conds, feature)
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
    geom_line(data = .panelB_pool(dm_bundle$dm_fine, ft_conds),
              aes(x, est, group = cell), color = "grey78", linewidth = 0.3) +
    geom_ribbon(data = he,  aes(x, ymin = lo, ymax = hi), fill = "grey70", alpha = 0.30) +
    geom_line(data = he,   aes(x, est, color = "Human coder"), linewidth = 1.0) +
    geom_ribbon(data = sel, aes(x, ymin = lo, ymax = hi, fill = label), alpha = 0.18) +
    geom_line(data = sel,  aes(x, est, color = label), linewidth = 1.0) +
    scale_color_manual(values = pal, name = NULL) +
    scale_fill_manual(values = pal, guide = "none") +
    coord_cartesian(xlim = c(0, xmax), ylim = c(0, xmax)) +
    labs(title = "A. AI Error by Case Difficulty",
         x = "Case Difficulty (Typical Human Error)", y = "MAE of AI Rating") +
    theme_minimal(base_size = 12) +
    theme(legend.position = "top", legend.justification = "left", legend.direction = "vertical",
          panel.grid.minor = element_blank(), plot.title.position = "plot",
          plot.title = element_text(face = "bold"),
          axis.title.x = element_text(margin = margin(t = 7)),
          axis.title.y = element_text(margin = margin(r = 7)))
}

# Difficulty-slope figure (composite) — the two panels side by side: the curve (what the slope measures) and the
# coefficient plot (every model ranked by that slope). Requires the curve fields in the bundle.
fig_crossmodel_slope_2panel <- function(dm_bundle,
                                        feature = NULL,
                                        ft_conds = c("codebook", "evidence-zeroshot",
                                                     "anonymized-zeroshot", "summarized-zeroshot")) {
  fig_slope_curve(dm_bundle, feature = feature, ft_conds = ft_conds) +
    fig_crossmodel_slope(dm_bundle, ft_conds = ft_conds) +
    patchwork::plot_layout(widths = c(1, 1.05))
}

# Signed-deviation figure (left panel) — signed deviation across the democracy gradient. y = AI rating minus the
# human panel mean; the dotted zero line is the panel-member target (a real coder sums to 0 per
# bin by construction), the dashed grey line is the V-Dem IRT target expressed on the same axis
# (mean(ord - panel_mean) per bin), so featured cells can be read against BOTH references. An
# upward slope = exaggerates the regime gradient; downward = compresses. Faint grey traces show
# every cell in the Panel B pool; `feature` = the cells drawn in colour, default NULL auto-selects
# three (calibrated / steepest / harshest — see .signeddev_feature3). Uses dm_q + irt_ref_q from
# build_signeddev.R.
fig_signeddev_curve <- function(sd_bundle,
                                feature = NULL,
                                ft_conds = c("codebook", "evidence-zeroshot",
                                             "anonymized-zeroshot", "summarized-zeroshot")) {
  feature <- .signeddev_feature3(sd_bundle$dm_q, sd_bundle$dm_eg_q, sd_bundle$dm_ov,
                                 ft_conds, feature)
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
    geom_line(data = .panelB_pool(sd_bundle$dm_q, ft_conds),
              aes(bin, est, group = cell), color = "grey78", linewidth = 0.3) +
    geom_line(data = irt, aes(bin, est), linetype = "dashed", color = "grey45", linewidth = 0.7) +
    annotate("text", x = 3, y = irt$est[irt$bin == 3], label = "V-Dem IRT",
             color = "grey25", size = 2.9, hjust = 1, vjust = -0.9) +
    # Uncertainty carried by the per-bin whiskers only. A ribbon here would (a) duplicate the
    # exact lo/hi the pointrange already shows, (b) imply continuous between-bin uncertainty
    # across just 4-5 discrete bins, and (c) muddy where the two translucent series overlap.
    # (The 20-bin difficulty-tracking Panel A keeps its ribbon — there a band is quasi-continuous.)
    geom_line(data = sel, aes(bin, est, color = label), linewidth = 0.7) +
    geom_pointrange(data = sel, aes(bin, est, ymin = lo, ymax = hi, color = label), size = 0.45) +
    scale_color_manual(values = pal, name = NULL) +
    scale_x_continuous(breaks = 1:5) +
    labs(title = "A. Signed Deviation by Quintile",
         x = "Democracy Quintile (1 = Most Autocratic, 5 = Most Democratic)",
         y = "Signed Deviation (AI - Panel Mean)") +
    theme_minimal(base_size = 12) +
    theme(legend.position = "top", legend.justification = "left", legend.direction = "vertical",
          panel.grid.minor = element_blank(), plot.title.position = "plot",
          plot.title = element_text(face = "bold"),
          axis.title.x = element_text(margin = margin(t = 7)),
          axis.title.y = element_text(margin = margin(r = 7)))
}

# Signed-deviation figure (right panel) — AVERAGE signed deviation across the gradient (dm_ov, "pooled shift" from
# build_signeddev.R) per cell, the twin of the difficulty-slope figure's coefficient panel. Reference at 0 = the human
# panel member (their signed deviations average to 0). Negative = the model rates below the panel
# on average (harsh); positive = above (generous). dm_ov is binning-independent, so the regime
# variant plots the same numbers — only Panel A differs between the two cuts. Same Base/Fine-tuned
# strips, plain input rows, capless point-ranges, color = model.
fig_signeddev_gap <- function(sd_bundle,
                              ft_conds = c("codebook", "evidence-zeroshot",
                                           "anonymized-zeroshot", "summarized-zeroshot")) {
  cells0 <- sd_bundle$dm_ov
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
  ref_lab <- tibble::tibble(block = factor("Base", levels = c("Base", "Fine-tuned")),
                            x = -0.006, y = "Codebook", label = "Human reference")
  band_lab <- tibble::tibble(block = factor("Base", levels = c("Base", "Fine-tuned")),
                             x = 0, label = "±SESOI band")

  ggplot(cells, aes(est, row, color = model, group = model)) +
    annotate("rect", xmin = -sesoi, xmax = sesoi, ymin = -Inf, ymax = Inf,
             fill = "grey85", alpha = 0.55) +
    geom_vline(xintercept = 0, linetype = "dashed", color = "grey40") +
    geom_text(data = ref_lab, aes(x = x, y = y, label = label),
              position = position_nudge(y = 0.4), hjust = 1, vjust = 0.5,
              color = "grey40", size = 2.9, inherit.aes = FALSE) +
    geom_text(data = band_lab, aes(x = x, y = Inf, label = label),
              hjust = 0.5, vjust = -0.5, color = "grey40", size = 2.9, inherit.aes = FALSE) +
    geom_pointrange(aes(xmin = lo, xmax = hi), orientation = "y",
                    size = 0.45, linewidth = 0.5, position = dodge) +
    facet_grid(rows = vars(block), scales = "free_y", space = "free", switch = "y") +
    scale_color_manual(values = model_pal, name = NULL) +
    coord_cartesian(clip = "off") +
    labs(title = "B. Average Signed Deviation",
         x = "Average Signed Deviation (AI - Panel Mean)", y = NULL) +
    theme_minimal(base_size = 12) +
    theme(legend.position = "top", legend.justification = "left",
          panel.grid.major.y = element_blank(), plot.title.position = "plot",
          plot.title = element_text(face = "bold"),
          axis.title.x = element_text(margin = margin(t = 7)),
          panel.spacing.y = unit(0.9, "lines"),
          strip.placement = "outside", strip.background = element_blank(),
          strip.text.y.left = element_text(angle = 0, face = "bold", hjust = 1))
}

# Signed-deviation figure (composite) — the gradient curve (what the exaggeration gap measures) beside the gap
# coefficient plot (every model ranked). Requires signeddev_xmodel_{year}.rds.
fig_crossmodel_signeddev_2panel <- function(sd_bundle,
                                            feature = NULL,
                                            ft_conds = c("codebook", "evidence-zeroshot",
                                                         "anonymized-zeroshot", "summarized-zeroshot")) {
  fig_signeddev_curve(sd_bundle, feature = feature, ft_conds = ft_conds) +
    fig_signeddev_gap(sd_bundle, ft_conds = ft_conds) +
    patchwork::plot_layout(widths = c(1, 1.05))
}

# Signed-deviation figure (regime variant, left panel; chunk `fig-crossmodel-signeddev-regime`) — signed deviation across V-Dem's Regimes of the World
# (v2x_regime: 0 closed autocracy .. 3 liberal democracy, stored as ri = v2x_regime + 1 so bins run
# 1..4). Same construction as fig_signeddev_curve but reads dm_r / irt_ref_r — the regime-type cut
# build_signeddev.R computes alongside the democracy-quintile cut.
fig_signeddev_curve_regime <- function(sd_bundle,
                                       feature = NULL,
                                       ft_conds = c("codebook", "evidence-zeroshot",
                                                    "anonymized-zeroshot", "summarized-zeroshot")) {
  feature <- .signeddev_feature3(sd_bundle$dm_r, sd_bundle$dm_eg_r, sd_bundle$dm_ov,
                                 ft_conds, feature)
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
    geom_line(data = .panelB_pool(sd_bundle$dm_r, ft_conds),
              aes(bin, est, group = cell), color = "grey78", linewidth = 0.3) +
    geom_line(data = irt, aes(bin, est), linetype = "dashed", color = "grey45", linewidth = 0.7) +
    annotate("text", x = 1.3, y = irt$est[irt$bin == 1], label = "V-Dem IRT",
             color = "grey15", size = 3.1, fontface = "bold", hjust = 0, vjust = 1.2) +
    # Uncertainty carried by the per-bin whiskers only. A ribbon here would (a) duplicate the
    # exact lo/hi the pointrange already shows, (b) imply continuous between-bin uncertainty
    # across just 4-5 discrete bins, and (c) muddy where the two translucent series overlap.
    # (The 20-bin difficulty-tracking Panel A keeps its ribbon — there a band is quasi-continuous.)
    geom_line(data = sel, aes(bin, est, color = label), linewidth = 0.7) +
    geom_pointrange(data = sel, aes(bin, est, ymin = lo, ymax = hi, color = label), size = 0.45) +
    scale_color_manual(values = pal, name = NULL) +
    scale_x_continuous(breaks = 1:4, labels = regime_lv) +
    labs(title = "A. Signed Deviation by Regime Type",
         x = NULL, y = "Signed Deviation (AI - Panel Mean)") +
    theme_minimal(base_size = 12) +
    theme(legend.position = "top", legend.justification = "left", legend.direction = "vertical",
          panel.grid.minor = element_blank(), plot.title.position = "plot",
          plot.title = element_text(face = "bold"),
          axis.title.y = element_text(margin = margin(r = 7)))
}

# Signed-deviation figure (regime variant, right panel) — identical to fig_signeddev_gap: average signed deviation
# is binning-independent, so the regime-cut Panel B is the same plot as the quintile-cut one.
# Kept as its own function so the regime composite reads symmetrically; only Panel A differs.
fig_signeddev_gap_regime <- function(sd_bundle,
                                     ft_conds = c("codebook", "evidence-zeroshot",
                                                  "anonymized-zeroshot", "summarized-zeroshot")) {
  cells0 <- sd_bundle$dm_ov
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
  ref_lab <- tibble::tibble(block = factor("Base", levels = c("Base", "Fine-tuned")),
                            x = -0.006, y = "Codebook", label = "Human reference")
  band_lab <- tibble::tibble(block = factor("Base", levels = c("Base", "Fine-tuned")),
                             x = 0, label = "±SESOI band")

  ggplot(cells, aes(est, row, color = model, group = model)) +
    annotate("rect", xmin = -sesoi, xmax = sesoi, ymin = -Inf, ymax = Inf,
             fill = "grey85", alpha = 0.55) +
    geom_vline(xintercept = 0, linetype = "dashed", color = "grey40") +
    geom_text(data = ref_lab, aes(x = x, y = y, label = label),
              position = position_nudge(y = 0.4), hjust = 1, vjust = 0.5,
              color = "grey40", size = 2.9, inherit.aes = FALSE) +
    geom_text(data = band_lab, aes(x = x, y = Inf, label = label),
              hjust = 0.5, vjust = -0.5, color = "grey40", size = 2.9, inherit.aes = FALSE) +
    geom_pointrange(aes(xmin = lo, xmax = hi), orientation = "y",
                    size = 0.45, linewidth = 0.5, position = dodge) +
    facet_grid(rows = vars(block), scales = "free_y", space = "free", switch = "y") +
    scale_color_manual(values = model_pal, name = NULL) +
    coord_cartesian(clip = "off") +
    labs(title = "B. Average Signed Deviation",
         x = "Average Signed Deviation (AI - Panel Mean)", y = NULL) +
    theme_minimal(base_size = 12) +
    theme(legend.position = "top", legend.justification = "left",
          panel.grid.major.y = element_blank(), plot.title.position = "plot",
          plot.title = element_text(face = "bold"),
          axis.title.x = element_text(margin = margin(t = 7)),
          panel.spacing.y = unit(0.9, "lines"),
          strip.placement = "outside", strip.background = element_blank(),
          strip.text.y.left = element_text(angle = 0, face = "bold", hjust = 1))
}

# Signed-deviation figure (regime variant, composite) — the gradient curve beside the gap coefficient plot, using
# V-Dem Regimes of the World instead of democracy quintiles. Requires signeddev_xmodel_{year}.rds.
fig_crossmodel_signeddev_2panel_regime <- function(sd_bundle,
                                                   feature = NULL,
                                                   ft_conds = c("codebook", "evidence-zeroshot",
                                                                "anonymized-zeroshot", "summarized-zeroshot")) {
  fig_signeddev_curve_regime(sd_bundle, feature = feature, ft_conds = ft_conds) +
    fig_signeddev_gap_regime(sd_bundle, ft_conds = ft_conds) +
    patchwork::plot_layout(widths = c(1, 1.05))
}


# Full 4x4 readout grid (chunk `fig-grid`): every model on every input, the off-diagonal
# expansion of the cross-model MAE figure (chunk `fig-crossmodel`). Same greedy-vs-expectation grammar, faceted by model, with
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
      # ft-raw) live in the cross-family MAE landscape, and without this filter they'd map to an NA facet here.
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

  # readout = shape (solid ● greedy, open ○ mean), matching the cross-model MAE landscape's convention
  # (readout_shape). This grid is entirely Llama (Base + its three FT variants), so its marks
  # carry the Llama blue from model_pal — keeping "Llama = blue" consistent with the MAE landscape and the
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

# Standalone re-identification-rate figure (Question 5 — notes/proposed-mechanism-tests.md,
# Section 6; see notes/mockups/reid-rates-fig-concept.md for the full design rationale and the
# data-integrity fix this bundle already reflects). Plain bars, no CI — a descriptive proportion
# over a large pool, not a paired contrast (2026-09-05 decision).
#
#   reidrates_bundle <- readRDS("data/derived/reidrates_2023.rds")
#   fig_reid_rates(reidrates_bundle)                 # top-1 (main text)
#   fig_reid_rates(reidrates_bundle, metric = "top3") # top-3 (appendix companion)
#
# Model order (left to right within each condition) is fixed by descending Base x Anonymized
# rate on the metric being plotted, computed from the real data — not hardcoded — so it re-sorts
# itself if the underlying rates change (and independently for the top-3 panel, rather than
# inheriting top-1's order). No chance-level reference line drawn (2026-09-05) — it sits
# indistinguishably close to zero at this scale; `reidrates_bundle$chance_rate` is still there
# for the figure note / caption to cite as a number instead.
fig_reid_rates <- function(reidrates_bundle, metric = c("top1", "top3")) {
  metric  <- match.arg(metric)
  rate_col <- if (metric == "top1") "rate" else "rate_top3"

  d <- reidrates_bundle$rates |>
    dplyr::mutate(
      modelvar  = factor(modelvar, levels = c("base", "ft-raw"), labels = c("Base", "Fine-Tuned")),
      condition = factor(condition, levels = c("Anonymized", "Summarized")),
      rate      = .data[[rate_col]]
    )

  model_order <- d |>
    dplyr::filter(modelvar == "Base", condition == "Anonymized") |>
    dplyr::arrange(dplyr::desc(rate)) |>
    dplyr::pull(model)
  d <- dplyr::mutate(d, model = factor(model, levels = model_order))

  ggplot(d, aes(condition, rate, fill = model)) +
    geom_col(position = position_dodge(width = 0.7), width = 0.62) +
    facet_grid(~ modelvar, switch = "x") +
    scale_fill_manual(values = model_pal, name = NULL) +
    scale_y_continuous(labels = scales::percent, expand = expansion(mult = c(0, 0.08))) +
    labs(x = NULL, y = "Re-Identification Rate") +
    theme_minimal(base_size = 12) +
    theme(legend.position = "top", legend.justification = "left",
          panel.grid.major.x = element_blank(),
          strip.placement = "outside", strip.text = element_text(face = "bold"),
          panel.spacing = unit(1.2, "lines"))
}

# Prominence-crossing mechanism figure (notes/proposed-mechanism-tests.md, Section 6; design
# settled 2026-09-06 — see notes/mockups/prominence-crossing-fig-concept.md). One panel per
# outcome: per model family x weight-state (Base / Fine-Tuned), the three coefficients of
#   outcome ~ Re-identified + Movement + Re-identified:Movement
# fit per CYI by closed-form country-clustered WLS in helpers/build_prominence.R. Re-identified
# is a fixed per-CYI prominence flag from that family's base-model re-id (Summarized text, main
# text; Anonymized is the appendix companion); Movement is |Δv2x_polyarchy| 2018-2023.
#
#   prom_bundle <- readRDS("data/derived/prominence_evidence_gain_2023_summ.rds")
#   fig_prominence(prom_bundle, sesoi = boot_bundle_2023$sesoi,
#                  xlab = "effect on evidence gain (MAE)")
#
# `sesoi = NULL` (the default) draws no band — required for outcomes not on the MAE rating-point
# scale (difficulty_slope's rows are slope-modifier coefficients, a different unit; the SESOI
# band is only meaningful for evidence_gain / nameswap_tracking, both literal rating-point
# differences). Pass a numeric sesoi only for those.
fig_prominence <- function(prom_bundle, sesoi = NULL, xlab) {
  d <- prom_bundle$effects

  p <- ggplot(d, aes(est, term, color = model))
  if (!is.null(sesoi)) {
    p <- p + annotate("rect", xmin = -sesoi, xmax = sesoi, ymin = -Inf, ymax = Inf,
                      fill = "grey85", alpha = 0.55)
  }
  p +
    geom_vline(xintercept = 0, linetype = "dashed", color = "grey40") +
    geom_pointrange(aes(xmin = lo, xmax = hi), size = 0.45, linewidth = 0.6,
                     position = position_dodge(width = 0.5)) +
    facet_grid(rows = vars(block), scales = "free_y", space = "free", switch = "y") +
    scale_color_manual(values = model_pal, name = NULL) +
    labs(x = xlab, y = NULL) +
    theme_minimal(base_size = 11) +
    theme(legend.position = "top", legend.justification = "left",
          panel.grid.major.y = element_blank(), strip.placement = "outside",
          strip.background = element_blank(),
          strip.text.y.left = element_text(angle = 0, face = "bold", hjust = 1),
          axis.title.x = element_text(margin = margin(t = 7)))
}

# Movement illustration (Question 3/Section 6's "staleness" ingredient — the descriptive
# companion to fig_reid_rates()'s "prominence" ingredient, both foreshadowing the
# prominence-crossing test). Ranked lollipop chart: one point per country, signed change in
# v2x_polyarchy (2018-2023), sorted. Labels exactly the 5 most-backslid and 5 most-improved
# countries — a fixed rule, not a visual judgment call — pushed into the margins clear of the
# stem region so they never sit on top of a bar. See notes/mockups/movement-illustration-
# mockup.R for the design iteration this was built from.
#
#   movement_bundle <- readRDS("data/derived/movement_2023.rds")
#   country_names    <- readr::read_csv("data/processed/ert.csv") |> dplyr::distinct(country_text_id, country_name)
#   fig_movement(movement_bundle, country_names)
fig_movement <- function(movement_bundle, country_names, n_label = 5) {
  d <- movement_bundle$dpoly |>
    dplyr::left_join(country_names, by = "country_text_id") |>
    dplyr::filter(!is.na(dpoly_signed)) |>
    dplyr::arrange(dpoly_signed) |>
    dplyr::mutate(rank = dplyr::row_number(),
                  direction = dplyr::if_else(dpoly_signed >= 0, "Improved", "Backslid"))

  n_countries <- nrow(d)
  d <- d |>
    dplyr::mutate(label = dplyr::if_else(rank <= n_label | rank > n_countries - n_label,
                                         country_name, NA_character_))

  dir_pal <- c("Backslid" = "#D55E00", "Improved" = "#0072B2")
  margin  <- round(n_countries * 0.12)

  ggplot(d, aes(rank, dpoly_signed, color = direction)) +
    geom_hline(yintercept = 0, color = "grey50", linewidth = 0.4) +
    geom_segment(aes(xend = rank, yend = 0), linewidth = 0.4, alpha = 0.6) +
    geom_point(size = 1.6) +
    ggrepel::geom_text_repel(
      data = ~ filter(.x, rank <= n_label),
      aes(label = label), size = 2.9, color = "grey20",
      max.overlaps = Inf, segment.size = 0.3, min.segment.length = 0, seed = 42,
      box.padding = 0.4, direction = "y", hjust = 1,
      xlim = c(NA, 1 - margin * 0.4)) +
    ggrepel::geom_text_repel(
      data = ~ filter(.x, rank > n_countries - n_label),
      aes(label = label), size = 2.9, color = "grey20",
      max.overlaps = Inf, segment.size = 0.3, min.segment.length = 0, seed = 42,
      box.padding = 0.4, direction = "y", hjust = 0,
      xlim = c(n_countries + margin * 0.4, NA)) +
    scale_color_manual(values = dir_pal, name = NULL) +
    scale_x_continuous(breaks = NULL, expand = expansion(mult = c(0.16, 0.16))) +
    scale_y_continuous(expand = expansion(mult = c(0.08, 0.08))) +
    labs(x = NULL, y = "Change in Polyarchy Score (2018 - 2023)") +
    theme_minimal(base_size = 12) +
    theme(legend.position = "top", legend.justification = "left",
          panel.grid.major.x = element_blank(), panel.grid.minor = element_blank())
}

# Chunk `fig-slope-by-condition`: does movement's / prominence's effect on the difficulty-tracking slope hold up
# across the de-identification ladder? Two side-by-side panels (Movement, Prominence), each from
# helpers/build_slope_by_condition.R's separate, interaction-free models:
#   a ~ h + movement + h:movement   (Panel A)
#   a ~ h + reid     + h:reid       (Panel B)
# run across all four Base conditions (Codebook/Evidence/Anonymized/Summarized) and the trimmed
# Fine-Tuned pair (Codebook/Evidence only, matching the FT-raw trim used throughout Figures 1-3).
# No SESOI band (slope-modifier units, not MAE). Movement's coefficient is on a percentile-rank
# scale (least- to most-moved country); Prominence's is a literal identified-vs-not comparison,
# no transform — a caption/prose note, not an axis-title difference (2026-09-06 decision).
#
#   sbc_movement <- readRDS("data/derived/slopebycondition_movement_2023.rds")
#   sbc_reid     <- readRDS("data/derived/slopebycondition_reid_2023.rds")
#   fig_slope_by_condition_2panel(sbc_movement, sbc_reid)
fig_slope_by_condition_2panel <- function(movement_bundle, reid_bundle) {
  make_panel <- function(bundle, subtitle, xlab) {
    d <- bundle$effects
    ggplot(d, aes(est, condition, color = model)) +
      geom_vline(xintercept = 0, linetype = "dashed", color = "grey40") +
      geom_pointrange(aes(xmin = lo, xmax = hi), size = 0.42, linewidth = 0.6,
                       position = position_dodge(width = 0.5)) +
      facet_grid(rows = vars(block), scales = "free_y", space = "free", switch = "y") +
      scale_color_manual(values = model_pal, name = NULL) +
      labs(x = xlab, y = NULL, subtitle = subtitle) +
      theme_minimal(base_size = 11) +
      theme(legend.position = "top", legend.justification = "left",
            panel.grid.major.y = element_blank(), strip.placement = "outside",
            strip.background = element_blank(),
            strip.text.y.left = element_text(angle = 0, face = "bold", hjust = 1),
            axis.title.x = element_text(margin = margin(t = 7)),
            plot.subtitle = element_text(face = "bold", size = 10.5))
  }

  # Axis titles carry the differing basis explicitly (2026-09-06) -- a reader scanning the plot
  # (not the caption) should not assume the two coefficients are on the same per-unit footing.
  pA <- make_panel(movement_bundle, "A. Movement", "Effect on Slope (Max Swing)")
  pB <- make_panel(reid_bundle, "B. Prominence", "Effect on Slope (Identified vs. Not)")

  (pA | pB) + patchwork::plot_layout(guides = "collect") &
    theme(legend.position = "top")
}

# Chunk `fig-signeddev-by-condition`: does movement's / prominence's effect on signed deviation (AI rating - panel mean)
# hold up across the de-identification ladder? Same shape as fig_slope_by_condition_2panel(), but
# from helpers/build_signeddev_by_condition.R's two SEPARATE, simpler models (no h term at all,
# unlike the difficulty-slope version -- signed deviation isn't itself regressed against
# difficulty here):
#   signed_dev ~ movement_signed   (Panel A)
#   signed_dev ~ reid              (Panel B)
# Movement uses the SIGNED, rank-tamed version (direction is the point -- a lag/anchoring test:
# does a backslid country still get an overly generous rating). UNLIKE `fig-slope-by-condition`, this DOES carry
# a SESOI band (2026-09-06 correction) -- signed deviation is a plain rating-point-scale level
# effect (same footing as evidence_gain/tracking), not a slope-modifier, so the paper's usual
# rounding-floor logic applies here the same way it does everywhere else.
#
#   sd_movement <- readRDS("data/derived/signeddevbycondition_movement_2023.rds")
#   sd_reid     <- readRDS("data/derived/signeddevbycondition_reid_2023.rds")
#   fig_signeddev_by_condition_2panel(sd_movement, sd_reid, sesoi = boot_bundle_2023$sesoi)
fig_signeddev_by_condition_2panel <- function(movement_bundle, reid_bundle, sesoi = NULL) {
  make_panel <- function(bundle, subtitle, xlab) {
    d <- bundle$effects
    p <- ggplot(d, aes(est, condition, color = model))
    if (!is.null(sesoi)) {
      p <- p + annotate("rect", xmin = -sesoi, xmax = sesoi, ymin = -Inf, ymax = Inf,
                        fill = "grey85", alpha = 0.55)
    }
    p +
      geom_vline(xintercept = 0, linetype = "dashed", color = "grey40") +
      geom_pointrange(aes(xmin = lo, xmax = hi), size = 0.42, linewidth = 0.6,
                       position = position_dodge(width = 0.5)) +
      facet_grid(rows = vars(block), scales = "free_y", space = "free", switch = "y") +
      scale_color_manual(values = model_pal, name = NULL) +
      labs(x = xlab, y = NULL, subtitle = subtitle) +
      theme_minimal(base_size = 11) +
      theme(legend.position = "top", legend.justification = "left",
            panel.grid.major.y = element_blank(), strip.placement = "outside",
            strip.background = element_blank(),
            strip.text.y.left = element_text(angle = 0, face = "bold", hjust = 1),
            axis.title.x = element_text(margin = margin(t = 7)),
            plot.subtitle = element_text(face = "bold", size = 10.5))
  }

  pA <- make_panel(movement_bundle, "A. Movement", "Effect on Signed Deviation (Max Swing)")
  pB <- make_panel(reid_bundle, "B. Prominence", "Effect on Signed Deviation (Identified vs. Not)")

  (pA | pB) + patchwork::plot_layout(guides = "collect") &
    theme(legend.position = "top")
}

# Shared regime palette for the dose-response panels below -- Okabe-Ito throughout
# (Mixed FT and Mixed pool were originally a ColorBrewer blue/purple inherited from the
# exploratory tipping-point scripts; the blue in particular collided with Llama's model
# color when the two panel types sit side by side, so both were swapped to validated
# Okabe-Ito hues that don't collide with model_pal: vermillion and reddish purple).
doseresponse_pal <- c("Same AI (Qwen FT)" = "#e08214", "Mixed FT (6 cells)" = "#D55E00",
                      "Mixed pool (18 cells)" = "#CC79A7")

# RETIRED (not rendered; superseded by fig_fliprate_quad) -- the mean-shift augmentation
# scenario. Does adding one AI
# rating to a thin 2023 panel (2-8 coders, panel GROWS n -> n+1) move the mean, and does
# that hold up as more seats are added? Panel A = build_augmentation.R's single-seat
# result by condition/model; Panel B = build_doseresponse_augmentation.R's k=1..4
# dose-response for three curated regimes. Degradation (replacing a healthy panel's
# coders) is not a real deployment path -- carried by fig_degradation_combined() as a
# robustness companion rather than co-headlined here. NOTE: neither this function nor
# fig_degradation_combined() is currently rendered; the deployment figures now report verdict
# changes via fig_fliprate_quad(). Both are kept because their numbers are quotable in prose.
# Both outcomes are a signed shift in the panel mean, rating points, zero-referenced. No
# SESOI band: the shift is a difference of two integers over a panel-size denominator,
# with no forced-rounding floor the way a single rating vs. a fractional mean has (see
# notes/mockups/augmentation-concept.md for the full derivation and the abandoned
# alternatives -- a mismatched remove/add threshold, then SESOI itself -- that led here).
#
#   aug <- readRDS("data/derived/augmentation_2023.rds")
#   dr  <- readRDS("data/derived/doseresponse_augmentation_2023.rds")
#   fig_augmentation_combined(aug, dr)
fig_augmentation_combined <- function(augmentation_bundle, doseresponse_bundle) {
  d <- augmentation_bundle$effects |>
    mutate(condition = factor(as.character(condition),
                              levels = c("Summarized", "Anonymized", "Raw Text", "Codebook")),
          block = factor(as.character(block), levels = c("Base", "Fine-Tuned")))

  pA <- ggplot(d, aes(est, condition, color = model)) +
    geom_vline(xintercept = 0, linetype = "dashed", color = "grey40") +
    geom_pointrange(aes(xmin = lo, xmax = hi), size = 0.42, linewidth = 0.6,
                     position = position_dodge(width = 0.5)) +
    facet_grid(rows = vars(block), scales = "free_y", space = "free", switch = "y") +
    scale_color_manual(values = model_pal, name = NULL) +
    labs(x = "Shift in Rating Points", y = NULL, subtitle = "A. One AI Seat, by Condition") +
    theme_minimal(base_size = 11) +
    theme(legend.position = "top", legend.justification = "left",
          panel.grid.major.y = element_blank(), strip.placement = "outside",
          strip.background = element_blank(),
          strip.text.y.left = element_text(angle = 0, face = "bold", hjust = 1),
          axis.title.x = element_text(margin = margin(t = 7)),
          plot.subtitle = element_text(face = "bold", size = 10.5))

  dodge <- position_dodge(width = 0.08)
  pB <- ggplot(doseresponse_bundle$results, aes(k, est, color = regime)) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "grey40") +
    geom_line(position = dodge, linewidth = 0.7) +
    geom_pointrange(aes(ymin = lo, ymax = hi), position = dodge, size = 0.42, linewidth = 0.6) +
    scale_color_manual(values = doseresponse_pal, name = NULL) +
    scale_x_continuous(breaks = seq_len(doseresponse_bundle$kmax)) +
    labs(x = "k AI Seats Added", y = "Shift in Rating Points",
         subtitle = "B. Dose-Response, k Seats Added") +
    theme_minimal(base_size = 11) +
    theme(legend.position = "top", legend.justification = "left",
          panel.grid.minor = element_blank(),
          axis.title.x = element_text(margin = margin(t = 7)),
          plot.subtitle = element_text(face = "bold", size = 10.5))

  pA | pB
}

# The degradation companion to fig_augmentation_combined() -- does replacing a HEALTHY panel's
# coders with AI move it the same way? Not a real deployment scenario on its own (no one
# is proposing to swap out functioning human panels), kept as a robustness check that the
# augmentation story isn't an artifact of starting from a thin panel. Same shape as
# fig_augmentation_combined(): Panel A = build_degradation.R's single-seat swap result by
# condition/model; Panel B = build_doseresponse_degradation.R's k=1..6 dose-response.
#
#   deg <- readRDS("data/derived/degradation_2023.rds")
#   dr  <- readRDS("data/derived/doseresponse_degradation_2023.rds")
#   fig_degradation_combined(deg, dr)
fig_degradation_combined <- function(degradation_bundle, doseresponse_bundle) {
  d <- degradation_bundle$effects |>
    mutate(condition = factor(as.character(condition),
                              levels = c("Summarized", "Anonymized", "Raw Text", "Codebook")),
          block = factor(as.character(block), levels = c("Base", "Fine-Tuned")))

  pA <- ggplot(d, aes(est, condition, color = model)) +
    geom_vline(xintercept = 0, linetype = "dashed", color = "grey40") +
    geom_pointrange(aes(xmin = lo, xmax = hi), size = 0.42, linewidth = 0.6,
                     position = position_dodge(width = 0.5)) +
    facet_grid(rows = vars(block), scales = "free_y", space = "free", switch = "y") +
    scale_color_manual(values = model_pal, name = NULL) +
    labs(x = "Shift in Rating Points", y = NULL, subtitle = "A. One Seat Swapped, by Condition") +
    theme_minimal(base_size = 11) +
    theme(legend.position = "top", legend.justification = "left",
          panel.grid.major.y = element_blank(), strip.placement = "outside",
          strip.background = element_blank(),
          strip.text.y.left = element_text(angle = 0, face = "bold", hjust = 1),
          axis.title.x = element_text(margin = margin(t = 7)),
          plot.subtitle = element_text(face = "bold", size = 10.5))

  dodge <- position_dodge(width = 0.08)
  pB <- ggplot(doseresponse_bundle$results, aes(k, est, color = regime)) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "grey40") +
    geom_line(position = dodge, linewidth = 0.7) +
    geom_pointrange(aes(ymin = lo, ymax = hi), position = dodge, size = 0.42, linewidth = 0.6) +
    scale_color_manual(values = doseresponse_pal, name = NULL) +
    scale_x_continuous(breaks = seq_len(doseresponse_bundle$kmax)) +
    labs(x = "k Seats Replaced", y = "Shift in Rating Points",
         subtitle = "B. Dose-Response, k Seats Replaced") +
    theme_minimal(base_size = 11) +
    theme(legend.position = "top", legend.justification = "left",
          panel.grid.minor = element_blank(),
          axis.title.x = element_text(margin = margin(t = 7)),
          plot.subtitle = element_text(face = "bold", size = 10.5))

  pA | pB
}

# Appendix: name-swap tracking level, base + fine-tuned, all three families (2023) --
# helpers/build_priorreliance.R's Panel B. Plain country-clustered bootstrap mean of
# track = |rating_sw - named_mean| - |rating_sw - source_mean| (analysis/10-nameswap-2019.qmd's
# Metric 1) per model x weight-state, no crossing against prominence/movement (that's a different,
# separate question from the one this appendix figure answers). SESOI applies -- tracking is a
# paired rating-point-scale level effect, same footing as evidence_gain/signed deviation.
#
#   panelB <- readRDS("data/derived/priorreliance_panelB_2023.rds")
#   fig_nameswap_tracking(panelB, sesoi = boot_bundle_2023$sesoi)
fig_nameswap_tracking <- function(panelB_bundle, sesoi = NULL) {
  d <- panelB_bundle$effects
  p <- ggplot(d, aes(est, model, color = model))
  if (!is.null(sesoi)) {
    p <- p + annotate("rect", xmin = -sesoi, xmax = sesoi, ymin = -Inf, ymax = Inf,
                      fill = "grey85", alpha = 0.55)
  }
  p +
    geom_vline(xintercept = 0, linetype = "dashed", color = "grey40") +
    geom_pointrange(aes(xmin = lo, xmax = hi), size = 0.5, linewidth = 0.6) +
    facet_grid(rows = vars(block), scales = "free_y", space = "free", switch = "y") +
    scale_color_manual(values = model_pal, guide = "none") +
    labs(x = "Tracking (+ = reads content, - = follows swapped name)", y = NULL) +
    theme_minimal(base_size = 12) +
    theme(panel.grid.major.y = element_blank(), strip.placement = "outside",
          strip.background = element_blank(),
          strip.text.y.left = element_text(angle = 0, face = "bold", hjust = 1),
          axis.title.x = element_text(margin = margin(t = 7)))
}

# Mockup: does movement / prominence directly predict name-swap tracking?
# (helpers/build_nameswap_by_moderator.R, 2026-09-06) -- the one outcome from Figures 4-7's
# mechanism-test arc that was never crossed against the two moderators. Same simplified,
# no-interaction shape as fig_slope_by_condition_2panel() / fig_signeddev_by_condition_2panel(),
# but there's no de-identification ladder here (name-swap only ran on one text condition per
# weight-state), so the panel layout is fig_nameswap_tracking's y=model / facet=block instead of a
# condition axis. SESOI applies -- tracking is a rating-point-scale level effect, same footing as
# signed deviation / evidence_gain.
#
#   ns_movement <- readRDS("data/derived/nameswapbymoderator_movement_2023.rds")
#   ns_reid     <- readRDS("data/derived/nameswapbymoderator_reid_2023.rds")
#   fig_nameswap_by_moderator_2panel(ns_movement, ns_reid, sesoi = boot_bundle_2023$sesoi)
fig_nameswap_by_moderator_2panel <- function(movement_bundle, reid_bundle, sesoi = NULL) {
  make_panel <- function(bundle, subtitle, xlab) {
    d <- bundle$effects
    p <- ggplot(d, aes(est, model, color = model))
    if (!is.null(sesoi)) {
      p <- p + annotate("rect", xmin = -sesoi, xmax = sesoi, ymin = -Inf, ymax = Inf,
                        fill = "grey85", alpha = 0.55)
    }
    p +
      geom_vline(xintercept = 0, linetype = "dashed", color = "grey40") +
      geom_pointrange(aes(xmin = lo, xmax = hi), size = 0.5, linewidth = 0.6) +
      facet_grid(rows = vars(block), scales = "free_y", space = "free", switch = "y") +
      scale_color_manual(values = model_pal, guide = "none") +
      labs(x = xlab, y = NULL, subtitle = subtitle) +
      theme_minimal(base_size = 11) +
      theme(panel.grid.major.y = element_blank(), strip.placement = "outside",
            strip.background = element_blank(),
            strip.text.y.left = element_text(angle = 0, face = "bold", hjust = 1),
            axis.title.x = element_text(margin = margin(t = 7)),
            plot.subtitle = element_text(face = "bold", size = 10.5))
  }

  pA <- make_panel(movement_bundle, "A. Movement", "Effect on Tracking (Max Swing)")
  pB <- make_panel(reid_bundle, "B. Prominence", "Effect on Tracking (Identified vs. Not)")

  pA | pB
}

# Identity's direct effect (Test B from the "what explains Figs 1-3's de-identification pattern"
# discussion, 2026-09-06) -- helpers/build_identity_effect{,_signeddev,_slope}.R. Two paired
# condition contrasts, same shared bootstrap draws per family: Anonymized - Evidence ("Full Text",
# identity removed with length held fixed) and Summarized - Summarized-Identified ("Compressed",
# identity removed with compression held fixed). Runs on three outcomes: MAE (identityeffect_),
# signed deviation (identityeffect_signeddev_), and the difficulty-tracking slope
# (identityeffect_slope_). Pass `xlab` per outcome. `drop_diff = TRUE` hides the
# "Full Text - Compressed" row (its point estimate is mechanically row1 - row2; keep those numbers
# in prose). SESOI applies to the MAE and signed-deviation outcomes (rating-point level effects),
# not to the slope outcome (slope-modifier units) -- pass sesoi = NULL there.
#
#   ie <- readRDS("data/derived/identityeffect_2023.rds")
#   fig_identity_effect(ie, sesoi = boot_bundle_2023$sesoi)
fig_identity_effect <- function(bundle, sesoi = NULL, drop_diff = FALSE,
                                xlab = "Effect on MAE (Identity Removed)") {
  d <- bundle$effects
  if (drop_diff) d <- droplevels(dplyr::filter(d, level != "Full Text - Compressed"))
  p <- ggplot(d, aes(est, level, color = model))
  if (!is.null(sesoi)) {
    p <- p + annotate("rect", xmin = -sesoi, xmax = sesoi, ymin = -Inf, ymax = Inf,
                      fill = "grey85", alpha = 0.55)
  }
  p +
    geom_vline(xintercept = 0, linetype = "dashed", color = "grey40") +
    geom_pointrange(aes(xmin = lo, xmax = hi), size = 0.5, linewidth = 0.6,
                     position = position_dodge(width = 0.5)) +
    scale_color_manual(values = model_pal, name = NULL) +
    labs(x = xlab, y = NULL) +
    theme_minimal(base_size = 12) +
    theme(legend.position = "top", legend.justification = "left",
          panel.grid.major.y = element_blank(),
          axis.title.x = element_text(margin = margin(t = 7)))
}

# RETIRED (nothing calls this now; superseded by fig_identity_and_compression) — the identity-removal
# contrast on all three outcomes in one figure. Three
# side-by-side panels, each its own ggplot with its OWN x-scale (the outcomes are in different
# units and are not comparable across panels). The measure name rides in each panel's bold
# subtitle ("A. Mean Absolute Error" / "B. Signed Deviation" / "C. Case Difficulty Slope"), the
# `fig-slope-by-condition` / `fig-signeddev-by-condition` idiom; one shared meta x-title "Effect of Removing Country Identity" beneath all three
# (patchwork caption). Shared y-axis is the two paired
# contrasts (Full Text, Compressed) -- the "Full Text - Compressed" row is dropped (its point
# estimate is mechanically row1 - row2; keep those numbers in prose). The ±SESOI band is drawn only
# on the two rating-point-scale panels (A, B), never on Case Difficulty Slope (slope-modifier
# units, per the Section 6 rule). Built with patchwork.
#
#   ie <- readRDS("data/derived/identityeffect_2023.rds")
#   sd <- readRDS("data/derived/identityeffect_signeddev_2023.rds")
#   sl <- readRDS("data/derived/identityeffect_slope_2023.rds")
#   fig_identity_effect_combined(ie, sd, sl, sesoi = boot_bundle_2023$sesoi)
fig_identity_effect_combined <- function(mae_bundle, signeddev_bundle, slope_bundle,
                                         sesoi = NULL) {
  con_lv <- c("Compressed", "Full Text")   # first level plots at bottom

  one_panel <- function(bundle, subtitle, band, show_y) {
    d <- bundle$effects |>
      dplyr::filter(level != "Full Text - Compressed") |>
      dplyr::mutate(contrast = factor(as.character(level), levels = con_lv),
                    model    = factor(model, levels = names(model_pal)))
    p <- ggplot(d, aes(est, contrast, color = model, group = model))
    if (band && !is.null(sesoi)) {
      p <- p + annotate("rect", xmin = -sesoi, xmax = sesoi, ymin = -Inf, ymax = Inf,
                        fill = "grey85", alpha = 0.55)
    }
    p <- p +
      geom_vline(xintercept = 0, linetype = "dashed", color = "grey40") +
      geom_pointrange(aes(xmin = lo, xmax = hi), size = 0.5, linewidth = 0.6,
                      position = position_dodge(width = 0.5)) +
      scale_color_manual(values = model_pal, name = NULL) +
      labs(subtitle = subtitle, x = NULL, y = NULL) +
      theme_minimal(base_size = 12) +
      theme(legend.position = "top", legend.justification = "left",
            panel.grid.major.y = element_blank(),
            plot.subtitle = element_text(face = "bold", size = 10.5))
    if (!show_y) p <- p + theme(axis.text.y = element_blank())
    p
  }

  pA <- one_panel(mae_bundle,       "A. Mean Absolute Error",   band = TRUE,  show_y = TRUE)
  pB <- one_panel(signeddev_bundle, "B. Signed Deviation",      band = TRUE,  show_y = FALSE)
  pC <- one_panel(slope_bundle,     "C. Case Difficulty Slope", band = FALSE, show_y = FALSE)

  (pA | pB | pC) +
    patchwork::plot_layout(guides = "collect") +
    patchwork::plot_annotation(
      caption = "Effect of Removing Country Identity",
      theme = theme(plot.caption = element_text(hjust = 0.5, size = 11, margin = margin(t = 8)))
    ) &
    theme(legend.position = "top", legend.justification = "left")
}

# Chunk `fig-nameswap-channels` (Figure 7) — the name-swap read two ways, split by salience.
# Built from build_nameswap_channels.R.
#
#   A. mean |cue| — how far the rating moves when ONLY the name changes, rating points. The same
#      evidence rated twice (true name / injected name) and differenced, so no panel means enter.
#      This IS a rating-point scale, so the ±SESOI band applies and is drawn as a shaded region
#      from zero to the threshold: anything inside it would be too small to matter.
#   B. text's share of the pull, b_source/(b_source + b_named) from the two-channel regression.
#      0.50 = the two channels pull equally. Percent-formatted so the two panels do not read as
#      the same units despite both spanning 0-1.
#
# Solid = that country-indicator's de-identified evidence was re-identified (high salience), open
# = it was not; fixed base-model partition, so Base and Fine-Tuned rows split identical items.
#
# Layout notes, all deliberate: panel.border + zero facet spacing frames each plot's DATA region
# as one box with a Base/Fine-Tuned divider (row labels and titles stay outside); panel B drops
# its row labels and strips because the two share one set; plot_spacer() keeps the two frames from
# abutting; the collected legend rides on the patchwork theme via plot_annotation, since applying
# it to the subplots draws it inside their frames. The shaded band must be the FIRST layer --
# adding data layers over it afterwards gives the panels different guide specs and patchwork then
# refuses to collect the legend.
#
#   fig_nameswap_channels(readRDS("data/derived/nameswapchannels_2023.rds"),
#                         sesoi = boot_bundle_2023$sesoi)
fig_nameswap_channels <- function(bundle, sesoi = NULL) {
  reid_shape <- c("Re-identified" = 16, "Not re-identified" = 1)
  dodge <- position_dodge(width = 0.6)

  # "All swaps" is the pooled row the prose quotes; the figure plots only the salience split.
  prep <- function(m) bundle$effects |>
    dplyr::filter(metric == m, stratum != "All swaps") |>
    dplyr::mutate(model = factor(model, levels = names(model_pal)),
                  block = factor(block, levels = c("Base", "Fine-Tuned")),
                  stratum = factor(stratum, levels = c("Re-identified", "Not re-identified")))

  panel <- function(d, xlab, subtitle, rows = TRUE, band = NULL) {
    p <- ggplot(d, aes(est, model, color = model, shape = stratum, group = stratum))
    if (!is.null(band)) {
      p <- p + annotate("rect", xmin = band[1], xmax = band[2], ymin = -Inf, ymax = Inf,
                        fill = "grey85", alpha = 0.55)
    }
    p <- p +
      geom_linerange(aes(xmin = lo, xmax = hi), linewidth = 0.5, alpha = 0.7, position = dodge) +
      geom_point(size = 2.4, stroke = 1, position = dodge) +
      facet_grid(rows = vars(block), scales = "free_y", space = "free", switch = "y") +
      scale_color_manual(values = model_pal, guide = "none") +
      scale_shape_manual(values = reid_shape, name = NULL) +
      coord_cartesian(xlim = c(0, 1), clip = "off") +
      labs(x = xlab, y = NULL, subtitle = subtitle) +
      theme_minimal(base_size = 11) +
      theme(legend.position = "top", legend.justification = "center",
            panel.grid.major.y = element_blank(),
            panel.spacing.y = unit(0, "lines"),
            panel.border = element_rect(color = "grey75", fill = NA, linewidth = 0.4),
            strip.placement = "outside", strip.background = element_blank(),
            plot.subtitle = element_text(face = "bold", size = 10.5),
            axis.title.x = element_text(margin = margin(t = 7)))
    if (rows) {
      p + theme(strip.text.y.left = element_text(angle = 0, face = "bold", hjust = 1))
    } else {
      p + theme(strip.text.y.left = element_blank(), axis.text.y = element_blank())
    }
  }

  # Reference labels once, pinned to the Base facet, not once per facet.
  lab_one <- function(x, txt, hj) tibble::tibble(
    block = factor("Base", levels = c("Base", "Fine-Tuned")),
    x = x, y = "Llama 70B", label = txt, hj = hj)
  draw_lab <- function(d) geom_text(data = d, aes(x = x, y = y, label = label, hjust = hj),
                                    inherit.aes = FALSE, vjust = 0.5, color = "grey20",
                                    fontface = "bold", size = 2.9)

  pA <- panel(prep("Mean |shift|"), "Mean Shift in Rating Points",
              "A. How far the rating moves when only the name changes",
              band = if (is.null(sesoi)) NULL else c(0, sesoi))
  if (!is.null(sesoi)) {
    pA <- pA + geom_vline(xintercept = sesoi, linetype = "dashed", color = "grey40") +
      draw_lab(lab_one(sesoi + 0.02, "SESOI", 0))
  }

  pB <- panel(prep("Text's share"), "Share of Rating Driven by the Text (vs. the Country Name)",
              "B. Text vs. name: which one the rating follows", rows = FALSE) +
    scale_x_continuous(labels = scales::percent_format(accuracy = 1)) +
    geom_vline(xintercept = 0.5, linetype = "dashed", color = "grey40") +
    draw_lab(lab_one(0.485, "equal", 1))

  (pA | patchwork::plot_spacer() | pB) +
    patchwork::plot_layout(widths = c(1, 0.02, 1), guides = "collect") +
    patchwork::plot_annotation(theme = theme(legend.position = "top",
                                             legend.justification = "center",
                                             legend.margin = margin(b = 4)))
}

# Chunk `fig-nameswap-salience-tests` (Appendix A11) — the paired salience differences behind
# Figure 7's solid/open split, re-identified minus not, computed within each bootstrap draw.
# Built from build_nameswap_channels.R's `tests`.
#
# SIGN. The text's share moves opposite to the other two by construction (more weight on the name
# is less on the text), so plotting it raw would put "the name did more" on different sides of
# zero in different panels. It is negated here and relabelled "Name's share", so across all three
# panels right-of-zero means the same thing: the injected name did more work where the evidence
# was identifiable.
#
# NO SESOI band. The prereg fixes the band for primary effects, not for every subgroup difference;
# applying it to these contrasts would be a new use of the number, and a stricter one. Flip rate
# is in the bundle (Section 7 quotes its levels) but is not plotted here, since the main text does
# not show it.
#
#   fig_nameswap_salience_tests(readRDS("data/derived/nameswapchannels_2023.rds"))
fig_nameswap_salience_tests <- function(bundle) {
  lv <- c("Mean shift (rating points)", "Name's share")
  d <- bundle$tests |>
    dplyr::filter(metric != "Flip rate") |>
    dplyr::mutate(
      flip_sign = metric == "Text's share",
      est = ifelse(flip_sign, -est, est),
      newlo = ifelse(flip_sign, -hi, lo),
      newhi = ifelse(flip_sign, -lo, hi),
      lo = newlo, hi = newhi,
      metric = dplyr::recode(metric, "Mean |shift|" = "Mean shift (rating points)",
                             "Text's share" = "Name's share"),
      metric = factor(metric, levels = lv),
      model = factor(model, levels = names(model_pal)),
      block = factor(block, levels = c("Base", "Fine-Tuned")))

  ggplot(d, aes(est, model, color = model)) +
    geom_vline(xintercept = 0, linetype = "dashed", color = "grey40") +
    geom_linerange(aes(xmin = lo, xmax = hi), linewidth = 0.5, alpha = 0.7) +
    geom_point(size = 2.4) +
    facet_grid(rows = vars(block), cols = vars(metric),
               scales = "free", space = "free_y", switch = "y") +
    scale_color_manual(values = model_pal, guide = "none") +
    labs(x = "Difference: re-identified − not re-identified", y = NULL) +
    theme_minimal(base_size = 11) +
    theme(panel.grid.major.y = element_blank(),
          panel.spacing.x = unit(1.1, "lines"),
          panel.spacing.y = unit(0, "lines"),
          panel.border = element_rect(color = "grey75", fill = NA, linewidth = 0.4),
          strip.placement = "outside", strip.background = element_blank(),
          strip.text.y.left = element_text(angle = 0, face = "bold", hjust = 1),
          strip.text.x = element_text(face = "bold", size = 10),
          axis.title.x = element_text(margin = margin(t = 7)),
          plot.margin = margin(t = 10, r = 10, b = 6, l = 6))
}

# RETIRED (nothing calls this now; Figure 7 is fig_nameswap_channels as of 2026-09-24). Name-swap
# tracking on the metric's achievable range. The rating-point version
# (fig_nameswap_tracking, built from build_priorreliance.R --panel B) reports base effects of
# +0.06-0.07, which read as negligible. They are not: the metric is bounded by the gap between
# the two countries' panel means, so the same estimate is ~10% of the available range. Panel A is
# the per-swap position on that range, Panel B the win rate against the injected name. Both are
# drawn on their FULL theoretical range (-1..+1 and 0..1) rather than zoomed to the estimates --
# what the axis shows is the point of the rescaling. No ±SESOI band: the paper's rating-point
# threshold is a level comparison against the human reference, and this is neither a level nor a
# rating-point scale. See notes/mockups/nameswap-rescaled-concept.md.
#
#   fig_nameswap_rescaled(readRDS("data/derived/nameswaprescaled_2023.rds"))
fig_nameswap_rescaled <- function(bundle) {
  d <- bundle$effects |>
    dplyr::mutate(model = factor(model, levels = names(model_pal)))

  panel <- function(dd, xlim, ref, xlab, subtitle, breaks, labels) {
    ggplot(dd, aes(est, model, color = model)) +
      geom_vline(xintercept = ref, linetype = "dashed", color = "grey40") +
      geom_pointrange(aes(xmin = lo, xmax = hi), size = 0.5, linewidth = 0.7) +
      facet_grid(rows = vars(block), scales = "free_y", space = "free", switch = "y") +
      scale_color_manual(values = model_pal, guide = "none") +
      scale_x_continuous(limits = xlim, breaks = breaks, labels = labels) +
      labs(x = xlab, y = NULL, subtitle = subtitle) +
      theme_minimal(base_size = 11) +
      theme(panel.grid.major.y = element_blank(), panel.grid.minor = element_blank(),
            strip.placement = "outside", strip.background = element_blank(),
            strip.text.y.left = element_text(angle = 0, face = "bold", hjust = 1),
            axis.title.x = element_text(margin = margin(t = 7)),
            plot.subtitle = element_text(face = "bold", size = 10.5))
  }

  pA <- panel(dplyr::filter(d, metric == "position"), c(-1, 1), 0,
              paste0("-1 = at or past the injected country's panel mean\n",
                     "+1 = at or past the true country's panel mean"),
              "A. Position between the two countries",
              c(-1, -0.5, 0, 0.5, 1), c("-1", "-0.5", "0\nmidpoint", "0.5", "+1"))

  pB <- panel(dplyr::filter(d, metric == "win"), c(0, 1), 0.5,
              paste0("share of swaps where the rating is closer\n",
                     "to the true country's panel mean"),
              "B. Win rate against the injected name",
              c(0, 0.25, 0.5, 0.75, 1), c("0", "0.25", "0.50\ncoin flip", "0.75", "1"))

  pA | pB
}

# Chunk `fig-identity-and-compression` — the two successive steps along the summarized family,
# in the three-panel one-x-scale-each layout shared with `fig-summarization-arms`.
#
#   Row 1  Compression        summarized-identified - raw text     names present on BOTH sides,
#                                                                  so only the compression moves
#   Row 2  De-identification  summarized - summarized-identified   compressed on BOTH sides,
#                                                                  so only the identity moves
#
#   raw text --[row 1]--> summarized-identified --[row 2]--> summarized
#
# SIGN: later - earlier, so positive MAE = further from the panel mean in both rows.
#
# Row 1 + Row 2 = summarized - raw text, the whole gap. They are two SUCCESSIVE STEPS, not shares
# of a total: row 1 is measured with identity present, row 2 with compression present, so their
# magnitudes are conditioned differently. Moving the same two factors in the other order (via
# anonymized) reverses which looks larger for Gemma -- so no percentage of any kind is reported
# here. See notes/identity-mechanism-arc-2026-09-16.md.
#
# NO ±SESOI band (2026-09-18 decision, following the deployment figure `fig-fliprate`'s precedent). SESOI defends against
# small RANDOM error -- a change below half a rounding step vanishes in any single published
# score. These are consistent directional pushes, and the question is whether a step moves the
# model and in which direction, i.e. sign + interval. The band also discriminates nothing here:
# at 0.113 it swallows every cell except Llama's de-identification MAE. Settled in
# notes/paper-figures-pipeline-review-2026-09-06.md Addendum 9.
#
# Reads the same bundles the retired fig_identity_effect_combined() rendered from; the Compression row was added to them
# by helpers/build_identity_effect*.R on 2026-09-18.
#
#   fig_identity_and_compression(ie, sl, sd)
fig_identity_and_compression <- function(mae_bundle, slope_bundle, signeddev_bundle) {
  con_lv <- c("De-identification", "Compression")   # first level plots at bottom

  one_panel <- function(bundle, subtitle, show_y) {
    d <- bundle$effects |>
      tibble::as_tibble() |>
      dplyr::filter(level %in% c("Compression", "Compressed")) |>
      dplyr::mutate(
        contrast = factor(dplyr::if_else(level == "Compression",
                                         "Compression", "De-identification"), levels = con_lv),
        model    = factor(model, levels = names(model_pal)))
    p <- ggplot(d, aes(est, contrast, color = model, group = model)) +
      geom_vline(xintercept = 0, linetype = "dashed", color = "grey40") +
      geom_pointrange(aes(xmin = lo, xmax = hi), size = 0.5, linewidth = 0.6,
                      position = position_dodge(width = 0.5)) +
      scale_color_manual(values = model_pal, name = NULL) +
      labs(subtitle = subtitle, x = NULL, y = NULL) +
      theme_minimal(base_size = 12) +
      theme(legend.position = "top", legend.justification = "left",
            panel.grid.major.y = element_blank(),
            # Three free x-scales side by side read as one strip without a boundary.
            panel.border = element_rect(color = "grey75", fill = NA, linewidth = 0.4),
            plot.margin = margin(l = 6, r = 6, t = 3, b = 3),
            axis.text.y = element_text(size = 10.5),
            plot.subtitle = element_text(face = "bold", size = 10.5))
    if (!show_y) p <- p + theme(axis.text.y = element_blank())
    p
  }

  # Panel order follows Figures 1-3: MAE, difficulty tracking, signed deviation.
  pA <- one_panel(mae_bundle,       "A. Mean Absolute Error",   TRUE)
  pB <- one_panel(slope_bundle,     "B. Case Difficulty Slope", FALSE)
  pC <- one_panel(signeddev_bundle, "C. Signed Deviation",      FALSE)

  (pA | pB | pC) +
    patchwork::plot_layout(guides = "collect") +
    patchwork::plot_annotation(
      caption = "Net Effect of Each Step (Compressing Text and Removing Country Identity)",
      theme = theme(plot.caption = element_text(hjust = 0.5, size = 11, margin = margin(t = 8)))
    ) &
    theme(legend.position = "top", legend.justification = "left")
}

# Chunk `fig-summarization-arms` — the three summarized arms as distances from ONE origin (raw
# evidence), in `fig-identity-and-compression`'s layout.
#
#   Summ-Identified        ~400w rewrite, names in the TEXT and the FRAMING
#   Summ + named framing   ~400w rewrite, names stripped from the text, country named in framing
#                          (the name-swap battery's control arm: name-swap mode forces
#                          hide_identity off, so this is the only run with that combination)
#   Summarized             ~400w rewrite, names stripped from the text, framing blanked
#
# Every arm is a paired contrast against raw evidence, so each is a distance from the same origin:
# no contrast depends on an ordering and none is a share of a total.
#
# CAVEAT that has to travel with it: where the first two arms coincide, that says text identity
# adds little GIVEN the framing already supplies it. It does not establish that text identity is
# unimportant on its own -- that needs the fourth cell (identified text, blank framing), which has
# never been run. It is also strongest for Llama, partial for Qwen, and absent for Gemma (whose
# three arms sit within 0.012), so it is not a three-family finding.
#
#   fig_summarization_arms(readRDS("data/derived/summarizationarms_2023.rds"))
fig_summarization_arms <- function(bundle) {
  arm_lv <- c("Summarized", "Summ + named framing", "Summ-Identified")  # first plots at bottom

  d <- bundle$effects |>
    dplyr::filter(arm %in% c("A", "C", "D")) |>
    dplyr::mutate(
      condition = factor(dplyr::recode(arm, A = "Summ-Identified",
                                            C = "Summ + named framing",
                                            D = "Summarized"), levels = arm_lv),
      model     = factor(model, levels = names(model_pal)))

  one_panel <- function(oc, subtitle, show_y) {
    p <- ggplot(dplyr::filter(d, outcome == oc),
                aes(est, condition, color = model, group = model)) +
      geom_vline(xintercept = 0, linetype = "dashed", color = "grey40") +
      geom_pointrange(aes(xmin = lo, xmax = hi), size = 0.5, linewidth = 0.6,
                      position = position_dodge(width = 0.5)) +
      scale_color_manual(values = model_pal, name = NULL) +
      labs(subtitle = subtitle, x = NULL, y = NULL) +
      theme_minimal(base_size = 12) +
      theme(legend.position = "top", legend.justification = "left",
            panel.grid.major.y = element_blank(),
            panel.border = element_rect(color = "grey75", fill = NA, linewidth = 0.4),
            plot.margin = margin(l = 6, r = 6, t = 3, b = 3),
            axis.text.y = element_text(size = 10.5),
            plot.subtitle = element_text(face = "bold", size = 10.5))
    if (!show_y) p <- p + theme(axis.text.y = element_blank())
    p
  }

  pA <- one_panel("MAE",              "A. Mean Absolute Error",   TRUE)
  pB <- one_panel("Difficulty slope", "B. Case Difficulty Slope", FALSE)
  pC <- one_panel("Signed deviation", "C. Signed Deviation",      FALSE)

  (pA | pB | pC) +
    patchwork::plot_layout(guides = "collect") +
    patchwork::plot_annotation(
      caption = "Effect of Each Summarized Condition Relative to Raw Evidence",
      theme = theme(plot.caption = element_text(hjust = 0.5, size = 11, margin = margin(t = 8)))
    ) &
    theme(legend.position = "top", legend.justification = "left")
}

# Chunk `fig-reid-split` — is the task-framing leg concentrated where the model CANNOT
# re-identify the country? Partial leak predicts the effect is LARGER among CYIs the model could
# NOT name (identity truly gone there); framing-only attention predicts it is FLAT.
#
# Color encodes the RE-IDENTIFICATION GROUP, not the model (model is on the facet rows), so
# model_pal's hues are deliberately avoided -- a reader flipping between figures should never
# read these as model colors.
#
#   fig_reid_split(readRDS("data/derived/reidsplit_2023.rds"))
fig_reid_split <- function(bundle) {
  grp_pal <- c("Re-identified"            = "#D55E00",   # Okabe-Ito vermillion
               "Not re-identified"        = "#0072B2",   # Okabe-Ito blue
               "Overall"                  = "grey25",
               "Difference (re-id − not)" = "#009E73")  # Okabe-Ito bluish green

  d <- bundle$effects |>
    dplyr::mutate(
      group   = factor(group, levels = rev(names(grp_pal))),
      outcome = factor(outcome, levels = c("MAE", "Signed deviation", "Difficulty slope"),
                       labels = c("MAE\n(negative = naming lowers error)",
                                  "Signed deviation\n(positive = naming is less harsh)",
                                  "Difficulty slope\n(positive = naming steepens tracking)")))

  ggplot(d, aes(est, group, color = group)) +
    geom_vline(xintercept = 0, linetype = "dashed", color = "grey45") +
    geom_pointrange(aes(xmin = lo, xmax = hi), size = 0.45, linewidth = 0.7) +
    facet_grid(rows = vars(model), cols = vars(outcome), scales = "free_x", switch = "y") +
    scale_color_manual(values = grp_pal, breaks = names(grp_pal), name = NULL) +
    labs(x = "Task-framing leg, identified − de-identified (2023, base models)", y = NULL) +
    guides(color = guide_legend(nrow = 1, reverse = TRUE)) +
    theme_minimal(base_size = 10.5) +
    theme(legend.position = "top", legend.justification = "left",
          # free_x scales butt together and collide otherwise
          panel.spacing.x = grid::unit(1.4, "lines"),
          panel.grid.major.y = element_blank(), panel.grid.minor = element_blank(),
          strip.placement = "outside", strip.background = element_blank(),
          strip.text.x = element_text(face = "bold", size = 9.5),
          strip.text.y.left = element_text(angle = 0, face = "bold", size = 9.5, hjust = 1),
          axis.text.y = element_text(size = 9),
          axis.title.x = element_text(margin = margin(t = 7)))
}

# The two deployment mechanics side by side, on verdict changes (Panel A) and directional push
# (Panel B). Called twice: mechanic = "add" for the main deployment figure (augmentation) and
# mechanic = "rep" for its appendix companion (replacement). Both read the build_fliprate.R
# bundles. Section numbers are deliberately not named here -- the appendix has renumbered twice.
#
# Shared y-scale across the two panels in each figure is deliberate: replacement disturbs
# roughly 1.5-2x as many verdicts as addition, and that level difference is a finding, not a
# nuisance to be auto-scaled away.
#
# Human churn is PLOTTED, not zero-referenced, in the change-rate figure -- a verdict change from
# ordinary turnover is 16-42%, not zero in expectation the way a mean shift is. In the
# directional figure it becomes the zero line, because that panel is already differenced
# against it, paired at the panel level.
#
#   fa <- readRDS("data/derived/fliprate_augmentation_2023.rds")
#   fd <- readRDS("data/derived/fliprate_degradation_2023.rds")
#   fig_fliprate_pair(fa, fd); fig_fliprate_direction_pair(fa, fd)
fliprate_lv <- c("Same AI (Qwen FT)", "Mixed FT (6 cells)",
                 "Mixed pool (18 cells)", "Human churn")

# Explicit per-regime x-offset rather than position_dodge(): k is continuous, and the top row
# has four arms against the bottom row's three, so a dodge would allocate different widths per
# row and the same colour would land at a different x in A than in C. Fixed offsets keep each
# regime on one vertical line down the whole figure.
#
# Lines are offset with the points. Leaving the lines on the true k was tried and is worse: at
# an offset of 0.15 the line visibly misses its own markers. The cost of dodging both is that
# two series sitting a point apart (Mixed FT and Mixed pool in Panel B) can look like they touch
# -- acceptable, since there they genuinely nearly coincide.
fliprate_xoff <- stats::setNames(seq(-0.07, 0.07, length.out = length(fliprate_lv)),
                                 fliprate_lv)

.fliprate_prep <- function(aug_bundle, deg_bundle) {
  grab <- function(b, mech) tibble::as_tibble(b$effects) |>
    dplyr::mutate(regime = factor(regime, levels = fliprate_lv), mech = mech)
  dplyr::bind_rows(grab(aug_bundle, "add"), grab(deg_bundle, "rep")) |>
    dplyr::mutate(kx = k + unname(fliprate_xoff[as.character(regime)]))
}

.fliprate_thm <- function() {
  theme_minimal(base_size = 12) +
    theme(legend.position = "top", legend.justification = "left",
          panel.grid.minor = element_blank(),
          panel.border = element_rect(color = "grey75", fill = NA, linewidth = 0.4),
          plot.subtitle = element_text(face = "bold", size = 11),
          axis.title = element_text(size = 10.5))
}

# `mechanic` selects which deployment mechanic to draw: "both" gives the original 2x2,
# "add" the augmentation row alone, "rep" the replacement row alone. The paper uses "add"
# in the main text and "rep" in the appendix, because under the leading-edge framing of
# `fig-panelsize-history` the seats were never filled rather than vacated -- so adding is the deployment
# mechanic and replacing is the counterfactual.
#
# BOTH bundles are required whichever row is drawn. `shared_scale` decides whether the y-limits
# span both mechanics or only the row being drawn; it defaults to FALSE, so each solo figure
# fits its own data. Replacement disturbs roughly twice as much as augmentation at every k
# (churn alone reaches 41.5% against 22.4%), and sharing the limits would squeeze the
# augmentation row into the lower ~40% of the change-rate axis to make that gap visible by shape. The
# level difference reads off the axis instead. `mechanic = "both"` always shares, since there
# the two rows sit in one figure and a reader compares them directly.
fig_fliprate_quad <- function(aug_bundle, deg_bundle, mechanic = c("both", "add", "rep"),
                              shared_scale = FALSE) {
  mechanic <- match.arg(mechanic)
  d   <- .fliprate_prep(aug_bundle, deg_bundle)
  pal <- c(doseresponse_pal, "Human churn" = "grey35")
  ds  <- if (shared_scale || mechanic == "both") d
         else dplyr::filter(d, mech == mechanic)
  yf  <- range(c(100 * ds$flip_lo, 100 * ds$flip_hi), na.rm = TRUE) + c(-2, 2)
  yd  <- range(c(100 * ds$netd_lo, 100 * ds$netd_hi), na.rm = TRUE) + c(-1, 1)

  # The change-rate panels carry the only legend: they have the linetype scale (Human churn is a plotted
  # arm there, and the zero line in the direction panels), so letting the direction panels emit
  # their own colour guide makes patchwork collect TWO legends instead of merging them.
  flip_panel <- function(m, sub, xlab) {
    ggplot(dplyr::filter(d, mech == m),
           aes(kx, 100 * flip, color = regime, linetype = regime)) +
      geom_line(linewidth = 0.8) +
      geom_pointrange(aes(ymin = 100 * flip_lo, ymax = 100 * flip_hi), size = 0.35) +
      scale_color_manual(values = pal, name = NULL) +
      scale_linetype_manual(values = c("solid", "solid", "solid", "22"), name = NULL) +
      scale_x_continuous(breaks = 1:4) + coord_cartesian(ylim = yf) +
      labs(subtitle = sub, x = xlab, y = "% of Panels Whose\nVerdict Changes") +
      .fliprate_thm()
  }
  dir_panel <- function(m, sub, xlab) {
    ggplot(dplyr::filter(d, mech == m, regime != "Human churn"),
           aes(kx, 100 * netd, color = regime)) +
      geom_hline(yintercept = 0, linetype = "22", color = "grey35") +
      geom_line(linewidth = 0.8) +
      geom_pointrange(aes(ymin = 100 * netd_lo, ymax = 100 * netd_hi), size = 0.35) +
      scale_color_manual(values = pal, guide = "none") +
      scale_x_continuous(breaks = 1:4) + coord_cartesian(ylim = yd) +
      labs(subtitle = sub, x = xlab,
           y = "Net Down \u2212 Up,\nvs. Human Churn (pts)") +
      .fliprate_thm()
  }

  # Rows are the MECHANIC, columns the OUTCOME, so each row reads as a unit and can be drawn
  # on its own. Outcome in columns also matches fig_identity_and_compression() and
# fig_summarization_arms(). Costs four axis titles
  # rather than two: adjacent columns are in different units, and x means something different
  # in each row, so neither can be shared away without risking a mislabel. Panel letters
  # restart at A when a row is drawn alone, since it is then its own figure.
  solo <- mechanic != "both"
  # The mechanic qualifier is redundant with the x-axis title when a row is drawn alone, but
  # load-bearing in the 2x2 where both rows sit in one figure.
  add_row <- (flip_panel("add", if (solo) "A. Verdicts Changed"
                                else      "A. Verdicts Changed — Seats Added",
                         "k Seats Added") |
              dir_panel("add",  if (solo) "B. Direction"
                                else      "B. Direction — Seats Added",
                        "k Seats Added"))
  rep_row <- (flip_panel("rep", if (solo) "A. Verdicts Changed"
                                else      "C. Verdicts Changed — Seats Replaced",
                         "k Seats Replaced") |
              dir_panel("rep",  if (solo) "B. Direction"
                                else      "D. Direction — Seats Replaced",
                        "k Seats Replaced"))

  out <- switch(mechanic,
                both = add_row / rep_row,
                add  = add_row,
                rep  = rep_row)

  # Solo rows: both panels carry one x variable on identical breaks, so the duplicate x title
  # collapses to one. The y titles are in different units and are never collected. The 2x2
  # keeps all four, since x means something different in each row there.
  out <- out + patchwork::plot_layout(guides = "collect",
                                      axis_titles = if (solo) "collect_x" else "keep") &
    theme(legend.position = "top", legend.justification = "left")

  # A collected x title labels both panels rather than one, so it is sized up from the
  # per-panel default to match the weight it now carries. The 2x2 keeps its four titles at
  # the base size, where each still labels a single panel.
  if (solo) out <- out & theme(axis.title.x = element_text(size = 12.5,
                                                           margin = margin(t = 6)))
  out
}

# -----------------------------------------------------------------------------
# Motivating figures (Figures 1-2). Both read data/derived/panelsize.rds, built by
# helpers/build_panelsize.R -- see that file for the estimation and for why the
# leading-edge reading in Figure 1B is not an attrition series.
# -----------------------------------------------------------------------------

# Panel size is ORDERED, so a categorical palette would throw the ordering away. These
# are ramps anchored on the repo's two Okabe-Ito hues: vermillion stepped dark-to-light
# below V-Dem's floor of five, blue at or above it. Adjacent-pair separation validated:
# worst normal-vision dE 15.6, worst CVD dE 10.2.
.panelsize_band_pal <- c("1"   = "#5A2800", "2"   = "#C25600", "3"  = "#F09A4A",
                         "4"   = "#FBD9BE", "5–8" = "#8ECFEE", "9+" = "#0072B2")
.panelsize_blue <- "#0072B2"   # as the current release reports it
.panelsize_verm <- "#D55E00"   # as measured at the time

# Fig 1 -- how thin V-Dem's panels are, and when.
#
#   bundle <- readRDS("data/derived/panelsize.rds")
#
# (A) The panel-size distribution across V-Dem's five eras, so the contemporary era is
#     read against the project's own history rather than in isolation.
# (B) The same years seen twice: as first published, before any back-coding was possible,
#     and as the current release reports them. The vermillion bars are flat -- every year
#     arrives about equally thin -- and the blue bars ramp purely with how many release
#     cycles a year has had. The most recent year has had none, so its two bars are equal.
fig_panelsize_history <- function(bundle) {
  era_tops <- distinct(bundle$era, era, pct_lt5)

  p_era <- ggplot(bundle$era, aes(era, prop, fill = band)) +
    geom_col(width = 0.72, colour = "white", linewidth = 0.4,
             position = position_fill(reverse = TRUE)) +
    geom_text(data = era_tops, aes(era, y = 1.04, label = sprintf("%.0f%%", pct_lt5)),
              inherit.aes = FALSE, size = 3, colour = "grey25", fontface = "bold") +
    scale_fill_manual(values = .panelsize_band_pal, name = "Coders per cell",
                      guide = guide_legend(nrow = 1)) +
    scale_y_continuous(labels = scales::percent, breaks = seq(0, 1, 0.25),
                       expand = expansion(mult = c(0.01, 0.09))) +
    labs(title = "A. Across V-Dem's history",
         subtitle = "Distribution of panel sizes; bold = share below five",
         x = NULL, y = "Share of cells") +
    theme_minimal(base_size = 11) +
    theme(legend.position = "bottom", panel.grid.major.x = element_blank(),
          panel.grid.minor = element_blank(), plot.title.position = "plot")

  p_pairs <- ggplot(bundle$pairs, aes(factor(cohort_year), pct, fill = when)) +
    geom_hline(yintercept = bundle$settled_ref, linetype = "22", colour = "grey50") +
    geom_col(position = position_dodge(width = 0.74), width = 0.68) +
    geom_text(aes(label = sprintf("%.0f", pct)), position = position_dodge(width = 0.74),
              vjust = -0.45, size = 2.7, colour = "grey25") +
    geom_text(data = distinct(bundle$pairs, cohort_year, cycles),
              aes(x = factor(cohort_year), y = -3.4,
                  label = ifelse(cycles == 0, "none", as.character(cycles))),
              inherit.aes = FALSE, size = 2.7, colour = "grey45") +
    scale_fill_manual(values = c("At first publication" = .panelsize_verm,
                                 "As V16 reports it"    = .panelsize_blue),
                      name = NULL, guide = guide_legend(nrow = 1)) +
    scale_y_continuous(labels = function(x) paste0(x, "%"), limits = c(-5, 49),
                       breaks = seq(0, 40, 10)) +
    labs(title = "B. Within the contemporary era",
         subtitle = sprintf(paste("Share below five, before and after back-coding.",
                                  "Dashed line = settled level, %.1f%%.",
                                  "\nNumber below each pair = release cycles elapsed."),
                            bundle$settled_ref),
         x = "Year being rated", y = "Cells below five") +
    theme_minimal(base_size = 11) +
    theme(legend.position = "bottom", panel.grid.major.x = element_blank(),
          panel.grid.minor = element_blank(), plot.title.position = "plot")

  (p_era | p_pairs) + patchwork::plot_layout(widths = c(1, 1.15))
}

# Fig 2 -- what an added coder buys, in V-Dem's own uncertainty units.
#
#   bundle <- readRDS("data/derived/panelsize.rds")
#   series "adjusted" (default) = panel-size dummies within indicator, country and year
#          fixed effects, so the comparison holds the case constant. "raw" = conditional
#          means, i.e. what a data user encounters before any adjustment.
#
# Both panels come from ONE fit and one country-clustered vcov, so the marginal panel's
# point estimates are exactly the level panel's first differences. Its INTERVALS are not
# readable off the level ribbons: the variance of a difference carries a covariance term,
# and adjacent coefficients here correlate ~0.76. See build_panelsize.R.
#
# Axis limits span both series so the raw and adjusted versions stay comparable when both
# are drawn (main text shows adjusted; raw is the appendix companion). Title and subtitle
# default to NULL because the chunk caption carries them in the manuscript; pass them to
# reproduce the standalone notebook version.
fig_coder_value <- function(bundle, series = c("adjusted", "raw"),
                            title = NULL, subtitle = NULL) {
  series <- match.arg(series)
  colour <- if (series == "adjusted") .panelsize_verm else .panelsize_blue

  lvl  <- filter(bundle$mv_levels,   series == !!series)
  marg <- filter(bundle$mv_marginal, series == !!series)
  nmax <- bundle$meta$mv_max

  # Shared across both series, so switching `series` does not silently rescale the axis.
  ylim_lvl  <- range(bundle$mv_levels$est   + outer(bundle$mv_levels$se,   c(-1.96, 1.96)))
  ylim_marg <- range(bundle$mv_marginal$d   + outer(bundle$mv_marginal$se, c(-1.96, 1.96)))

  # V-Dem's two published lines, drawn on both panels: the shaded zone is "three or fewer"
  # (advised against) and the dashed rule is the recommended floor of five.
  bands <- list(
    annotate("rect", xmin = 0.5, xmax = 3.5, ymin = -Inf, ymax = Inf,
             fill = "grey70", alpha = 0.16),
    annotate("segment", x = 5, xend = 5, y = -Inf, yend = Inf,
             linetype = "22", colour = "grey45", linewidth = 0.4)
  )

  p_lvl <- ggplot(lvl, aes(n_coders, est)) + bands +
    annotate("text", x = 5, y = ylim_lvl[2], hjust = -0.08, vjust = 1.1, size = 2.9,
             colour = "grey35", label = "V-Dem's floor of five") +
    geom_ribbon(aes(ymin = est - 1.96 * se, ymax = est + 1.96 * se),
                fill = colour, alpha = 0.30) +
    geom_line(colour = colour, linewidth = 0.5) +
    geom_point(colour = colour, size = 1.5) +
    scale_x_continuous(breaks = seq(1, nmax, 2)) +
    coord_cartesian(ylim = ylim_lvl) +
    labs(title = "Level — how uncertain is a panel of this size?",
         subtitle = "Lower is less uncertainty",
         x = "Panel size (coders)", y = "Posterior SD") +
    theme_minimal(base_size = 11) +
    theme(panel.grid.minor = element_blank(), plot.title.position = "plot")

  # Sign convention kept as-is: this is a change in SD, the same quantity and sign a
  # regression coefficient reports. Plotting "reduction" instead would make the axis
  # positive-is-better but would no longer be the number in the table. Labelled instead.
  p_marg <- ggplot(marg, aes(n_coders, d)) + bands +
    geom_hline(yintercept = 0, colour = "grey40", linewidth = 0.5) +
    annotate("text", x = nmax, y = 0, hjust = 1, vjust = -0.8, size = 2.9,
             colour = "grey35", label = "zero = the added coder changed nothing") +
    geom_linerange(aes(ymin = d - 1.96 * se, ymax = d + 1.96 * se),
                   colour = colour, alpha = 0.55, linewidth = 0.9) +
    geom_point(colour = colour, size = 2.1) +
    scale_x_continuous(breaks = seq(2, nmax, 2)) +
    coord_cartesian(ylim = ylim_marg) +
    labs(title = "Marginal — what did the next coder buy?",
         subtitle = "Change in SD from adding one coder. More negative = bought more.",
         x = "Panel size after adding (coders)", y = "Δ Posterior SD") +
    theme_minimal(base_size = 11) +
    theme(panel.grid.minor = element_blank(), plot.title.position = "plot")

  out <- (p_lvl | p_marg)
  if (!is.null(title) || !is.null(subtitle)) {
    out <- out + patchwork::plot_annotation(
      title = title, subtitle = subtitle,
      theme = theme(plot.title = element_text(size = 13, face = "bold")))
  }
  out
}

.panelsize_lt5_pal <- c("<1%" = "#FDDBC7", "1–5%" = "#F4A582", "5–10%" = "#D55E00",
                        "10–20%" = "#A03F00", ">20%" = "#6B2900")
.panelsize_regime_pal <- c("Closed autocracy"    = "#D55E00", "Electoral autocracy" = "#E69F00",
                           "Electoral democracy" = "#56B4E9", "Liberal democracy"   = "#0072B2")

# Appendix A1 -- the cross-sectional and temporal cuts behind Figure 1.
#
# Both panels measure the same quantity, coders per country-indicator-year, so they share
# a y-axis; only the thing being varied differs. (A) varies time and regime type, (B)
# varies country.
#
# Panel A is NOT an attrition series -- see build_panelsize.R and Figure 1B. The decline
# after 2013 is back-coding that has not arrived yet; the leading-edge workforce is flat.
# The dotted rules mark coding-schedule features, not workforce events: 2005 is where
# contemporary recruits stop back-coding, 2013 where the original coding round ended.
fig_panelsize_cuts <- function(bundle, n_label = 6) {
  country <- bundle$country
  ylim_shared <- range(country$mean_n)

  p_time <- ggplot(bundle$regime, aes(year, mean_n, colour = regime)) +
    geom_line(linewidth = 0.85) +
    geom_vline(xintercept = c(2005, 2013), linetype = "dotted", colour = "grey45") +
    annotate("text", x = 2005, y = Inf, label = "2005", hjust = -0.15, vjust = 1.6,
             size = 2.9, colour = "grey40") +
    annotate("text", x = 2013, y = Inf, label = "2013", hjust = -0.15, vjust = 1.6,
             size = 2.9, colour = "grey40") +
    scale_colour_manual(values = .panelsize_regime_pal, name = NULL,
                        guide = guide_legend(nrow = 2)) +
    coord_cartesian(ylim = ylim_shared) +
    labs(title = "A. Over time, by regime type",
         subtitle = paste("Autocracies run persistently thinner. Dotted lines: the",
                          "back-coding floor\nand the end of the original coding round."),
         x = "Year being rated", y = "Coders per country-indicator-year") +
    theme_minimal(base_size = 11) +
    theme(legend.position = "bottom", panel.grid.minor = element_blank(),
          plot.title.position = "plot")

  # Labels are placed at explicit coordinates rather than by repel-with-nudges. The curve
  # runs corner to corner, so the two clear regions are the wedge ABOVE it on the left and
  # the wedge BELOW it on the right. Thin-country labels go in the first, thick-country in
  # the second, each as an evenly spaced column with a drawn leader line. Longest labels
  # sit furthest from the curve, since text extends horizontally into it.
  n_ctry <- nrow(country)
  lab <- country |>
    filter(rank <= n_label | rank > n_ctry - n_label) |>
    mutate(side = if_else(rank <= n_label, "thin", "thick")) |>
    group_by(side) |>
    arrange(desc(nchar(country_name)), .by_group = TRUE) |>
    mutate(
      slot  = row_number(),
      # Thick-country labels fan left as they RISE. The points sit together in the
      # top-right corner, so a label placed low and far left would need a leader line
      # crossing every label between it and its point. Anchoring the lowest label
      # furthest right keeps each leader to the right of the labels below it.
      lab_x = if_else(side == "thin", 20, (n_ctry - 3) - (slot - 1) * 4.6),
      lab_y = if_else(side == "thin", 13.2 - (slot - 1) * 0.72,
                                       6.4 + (slot - 1) * 0.72),
      hj    = if_else(side == "thin", 0, 1)
    ) |>
    ungroup()

  p_country <- ggplot(country, aes(rank, mean_n)) +
    geom_hline(yintercept = 5, linetype = "22", colour = "grey55") +
    annotate("text", x = 55, y = 5, label = "V-Dem's floor of five",
             hjust = 0, vjust = -0.7, size = 2.9, colour = "grey45") +
    geom_segment(data = lab, aes(x = rank, y = mean_n, xend = lab_x, yend = lab_y),
                 colour = "grey70", linewidth = 0.22, inherit.aes = FALSE) +
    geom_point(aes(colour = lt5_bin), size = 1.6) +
    geom_text(data = lab, aes(x = lab_x, y = lab_y, label = country_name, hjust = hj),
              size = 2.7, colour = "grey20", inherit.aes = FALSE) +
    scale_colour_manual(values = .panelsize_lt5_pal, name = "Cells below five",
                        guide = guide_legend(nrow = 1)) +
    coord_cartesian(ylim = c(4.8, max(country$mean_n) + 0.6),
                    xlim = c(-2, n_ctry + 5)) +
    labs(title = "B. Across countries",
         subtitle = sprintf("%d countries, %d–%d, ranked. Labels: %d thinnest and %d thickest.",
                            n_ctry, bundle$meta$var_window[1], bundle$meta$var_window[2],
                            n_label, n_label),
         x = "Country (ranked)", y = NULL) +
    theme_minimal(base_size = 11) +
    theme(legend.position = "bottom", panel.grid.minor = element_blank(),
          panel.grid.major.x = element_blank(), plot.title.position = "plot")

  (p_time | p_country) + patchwork::plot_layout(widths = c(1, 1.1))
}

# Appendix A2 -- panel size by survey, and what accounts for the variation.
#
# (A) V-Dem recruits at the survey level, so this is the unit that corresponds to an
#     actual recruitment decision. Vermillion marks surveys whose series begin after 1789:
#     a younger survey has had fewer recruitment rounds, so youth and thinness are
#     confounded and the two thinnest surveys are exactly the two young ones.
# (B) One-way R-squared per grouping plus two nested fits. Two things the caption has to
#     say: the single-predictor bars are NOT orthogonal shares (they sum past the
#     cumulative fit, because country and year overlap), and R-squared rises mechanically
#     with the number of levels, so country's lead is partly a degrees-of-freedom artifact.
fig_panelsize_sources <- function(bundle) {
  survey <- bundle$survey |> mutate(name = factor(name, levels = name))
  var_r2 <- bundle$var_r2 |> mutate(source = factor(source, levels = rev(source)))

  p_survey <- ggplot(survey, aes(mean_n, name)) +
    geom_vline(xintercept = 5, linetype = "22", colour = "grey55") +
    geom_segment(aes(x = 5, xend = mean_n, yend = name), colour = "grey75", linewidth = 0.5) +
    geom_point(aes(colour = later_start), size = 3) +
    geom_text(aes(label = sprintf("%.1f", mean_n)), hjust = -0.55, size = 2.9,
              colour = "grey25") +
    scale_colour_manual(values = c(`FALSE` = "#0072B2", `TRUE` = "#D55E00"), name = NULL,
                        labels = c(`FALSE` = "series starts 1789",
                                   `TRUE`  = "series starts later")) +
    scale_x_continuous(limits = c(5, max(survey$mean_n) + 1.2),
                       breaks = seq(5, 12, 1)) +
    labs(title = "By survey", x = "Mean coders", y = NULL,
         subtitle = sprintf("Mean panel size, %d–%d (indicators in parentheses)",
                            bundle$meta$var_window[1], bundle$meta$var_window[2])) +
    theme_minimal(base_size = 11) +
    theme(panel.grid.minor = element_blank(), panel.grid.major.y = element_blank(),
          legend.position = "bottom", plot.title.position = "plot")

  p_var <- ggplot(var_r2, aes(r2, source, fill = kind)) +
    geom_col(width = 0.62) +
    geom_text(aes(label = sprintf("%.3f", r2)), hjust = -0.2, size = 2.9, colour = "grey25") +
    scale_fill_manual(values = c(`one predictor` = "#0072B2", cumulative = "grey70"),
                      name = NULL) +
    scale_x_continuous(limits = c(0, 0.78), expand = expansion(mult = c(0, 0.02))) +
    labs(title = "What explains panel size?", x = "R²", y = NULL,
         subtitle = sprintf("Share of variance in coders per cell, %d–%d",
                            bundle$meta$var_window[1], bundle$meta$var_window[2])) +
    theme_minimal(base_size = 11) +
    theme(panel.grid.minor = element_blank(), panel.grid.major.y = element_blank(),
          legend.position = "bottom", plot.title.position = "plot")

  (p_survey | p_var) + patchwork::plot_layout(widths = c(1.25, 1))
}

# ── fig_temperature_ladder — Appendix A9 ────────────────────────────────────
# What decoding temperature would do to all three outcomes. Every rating in the paper is the
# greedy mode (T = 0); T > 0 here is the EXPECTED behaviour of a sampled rating, computed in
# closed form from the stored rating distribution (q_T(y) ∝ p(y)^(1/T)), so no new inference is
# involved. The slope is exact rather than approximate because OLS is linear in the outcome.
#
# Lines rather than a forest plot: temperature is continuous and ordered, the story is a monotone
# trend against a fixed reference, and the bundle carries 198 estimates. Dashed rule in each panel
# is the human reference (MAE 0.725, slope 1.00, signed deviation 0.00); the solid dot marks T = 0,
# the setting actually used. Data: build_temperature_ladder.R.
fig_temperature_ladder <- function(bundle) {
  lab <- c("llama-70b-ft-raw" = "Llama 70B", "qwen-72b-ft-raw" = "Qwen 72B",
           "gemma-27b-ft-raw" = "Gemma 27B")

  d <- bundle$ladder |>
    dplyr::mutate(
      model     = factor(lab[model_key], levels = names(model_pal)),
      condition = dplyr::recode(condition, codebook = "Codebook only",
                                `evidence-zeroshot` = "Raw evidence"),
      outcome   = factor(outcome,
                         levels = c("MAE", "Difficulty slope", "Signed deviation")))

  refs <- tibble::tibble(outcome = factor(names(bundle$refs), levels = levels(d$outcome)),
                         y = unname(bundle$refs))

  ggplot2::ggplot(d, ggplot2::aes(temp, est, colour = model, fill = model)) +
    ggplot2::geom_hline(data = refs, ggplot2::aes(yintercept = y), linetype = "longdash",
                        colour = "grey35", linewidth = 0.4, inherit.aes = FALSE) +
    ggplot2::geom_ribbon(ggplot2::aes(ymin = lo, ymax = hi), alpha = 0.16, colour = NA) +
    ggplot2::geom_line(linewidth = 0.7) +
    ggplot2::geom_point(data = ~ dplyr::filter(.x, temp == 0), size = 2.1) +
    ggplot2::facet_grid(condition ~ outcome, scales = "free_y", switch = "y") +
    ggplot2::scale_colour_manual(values = model_pal, name = NULL) +
    ggplot2::scale_fill_manual(values = model_pal, guide = "none") +
    ggplot2::scale_x_continuous(breaks = seq(0, 1, 0.25)) +
    ggplot2::labs(x = "Decoding temperature  (0 = greedy mode, used throughout the paper)",
                  y = NULL) +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(legend.position = "top",
                   panel.border = ggplot2::element_rect(colour = "grey80", fill = NA),
                   panel.grid.minor = ggplot2::element_blank(),
                   strip.placement = "outside",
                   strip.text = ggplot2::element_text(face = "bold"))
}
