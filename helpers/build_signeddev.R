# build_signeddev.R — cross-model SIGNED-DEVIATION bundle for paper Figure 3, without rendering
# analysis/08-signed-deviation-2019.qmd.
#
# Lifts the signed-deviation compute out of QMD 08 and generalizes it past its Llama-only cell list
# to all three model families. Signed deviation keeps the direction MAE throws away:
#   s_c     = AI_rating - panel_mean     (deviation from the human panel — panel-member target)
#   s_ord_c = AI_rating - vdem_ord       (deviation from V-Dem's IRT ordinal — calibration target)
# averaged within regime bins. Zero = the human/oracle target (human coders sum to 0 per bin by
# construction). The scalar summary is the EXAGGERATION GAP = (most-democratic bin) - (most-
# autocratic bin): positive = exaggerates the gradient, negative = compresses toward the middle.
#
# Two ordered cuts: democracy quintile (theta_quintile, 1..5) and Regime of the World
# (v2x_regime 0..3 -> 1..4). The IRT target expressed in panel-mean-deviation space is
# d_ord = ord - panel_mean, averaged per bin (irt_ref_*): where "matching V-Dem IRT" falls on the
# same axis as s, so a figure can draw the panel-mean target (0) and the IRT target (that line)
# together.
#
# GREEDY readout, same country-clustered bootstrap (seed 42) as build_bundles/build_distmatch.
# Source of cells: data/output/runs/<runs-subdir>/ (2019 -> "expectation", the only dir with all
# three families' greedy ratings; 2023 -> "2023"). Writes signeddev_xmodel_{year}.rds — distinct
# from QMD 08's Llama-only signeddev_{year}.rds so a rebuild never clobbers that frozen archive.
#
# Usage:
#   Rscript helpers/build_signeddev.R                       # 2019 (reads runs/expectation)
#   Rscript helpers/build_signeddev.R --year 2023 --runs-subdir 2023
#   Rscript helpers/build_signeddev.R --verify             # rebuild 2019 & diff Llama gaps vs QMD 08

suppressPackageStartupMessages({ library(tidyverse); library(glue) })

find_panel_member_root <- function() {
  up <- tryCatch(rprojroot::find_root(rprojroot::is_git_root), error = function(e) NA_character_)
  if (!is.na(up)) return(up)
  down <- file.path(getwd(), "panel-member")
  if (dir.exists(file.path(down, ".git"))) return(down)
  stop("Could not locate the panel-member project root from working dir: ", getwd())
}

build_signeddev_bundle <- function(proj_root,
                                   year        = 2019,
                                   runs_subdir = "expectation",
                                   n_boot      = 2000,
                                   seed        = 42,
                                   out_dir     = file.path(proj_root, "data", "derived"),
                                   write       = TRUE) {
  source(file.path(proj_root, "helpers", "bootstrap_helpers.R"), local = TRUE)
  data_dir <- file.path(proj_root, "data", "processed")
  runs_dir <- file.path(proj_root, "data", "output", "runs", runs_subdir)
  if (!dir.exists(runs_dir)) stop("runs dir not found: ", runs_dir)

  needed <- c("country", "year", "indicator", "condition", "model_key", "rating")
  read_run <- function(f) {
    con <- file(f, "r"); on.exit(close(con))
    jsonlite::stream_in(con, verbose = FALSE) |> as_tibble() |> select(all_of(needed))
  }
  files <- list.files(runs_dir, pattern = "\\.jsonl$", full.names = TRUE)
  if (length(files) == 0) stop("No .jsonl files in ", runs_dir)
  ai_raw <- files |> map(read_run) |> bind_rows() |>
    mutate(model_key = str_remove(model_key, "-local$"))

  panel_means <- read_csv(file.path(data_dir, "panel_means.csv"), show_col_types = FALSE)
  vdem_ord <- read_csv(file.path(data_dir, "vdem_ord.csv"), show_col_types = FALSE) |>
    select(country_text_id, year, indicator, ord)

  ai <- ai_raw |>
    filter(year == !!year) |>
    rename(country_text_id = country) |>
    inner_join(select(panel_means, country_text_id, year, indicator,
                      raw_mean, theta_quintile, v2x_regime),
               by = c("country_text_id", "year", "indicator")) |>
    left_join(vdem_ord, by = c("country_text_id", "year", "indicator")) |>
    mutate(s     = rating - raw_mean,
           s_ord = rating - ord,
           cell  = paste(model_key, condition, sep = "|"),
           qi    = ifelse(theta_quintile >= 1, as.integer(theta_quintile), NA_integer_),
           ri    = ifelse(!is.na(v2x_regime), as.integer(v2x_regime) + 1L, NA_integer_))

  cyi_pool <- ai |>
    distinct(country_text_id, year, indicator, raw_mean, theta_quintile, v2x_regime, ord) |>
    mutate(cyi = row_number(), k = paste(country_text_id, indicator),
           qi  = ifelse(theta_quintile >= 1, as.integer(theta_quintile), NA_integer_),
           ri  = ifelse(!is.na(v2x_regime), as.integer(v2x_regime) + 1L, NA_integer_),
           d_ord = ord - raw_mean)            # IRT target in panel-mean-deviation space
  ai <- ai |>
    mutate(k = paste(country_text_id, indicator), cyi = cyi_pool$cyi[match(k, cyi_pool$k)]) |>
    filter(!is.na(cyi))

  cell_lv  <- sort(unique(ai$cell)); ncell <- length(cell_lv)
  ai$celli <- as.integer(factor(ai$cell, levels = cell_lv))
  nq <- 5L; nr <- 4L; lo_idx <- (1:ncell) - 1L

  W <- country_boot_weights(cyi_pool$country_text_id, n_boot, seed = seed)
  draw_id <- colnames(W); app <- which(draw_id == "Apparent")
  boot <- setdiff(seq_along(draw_id), app)

  scatter <- function(tab, len) { v <- rep(NA_real_, len); v[as.integer(rownames(tab))] <- tab; v }
  wmean   <- function(w, x, g, len)
    scatter(rowsum(w * x, g, reorder = FALSE), len) / scatter(rowsum(w, g, reorder = FALSE), len)

  # AI aggregation frames (drop rows missing the relevant cut / IRT score)
  q  <- ai |> filter(!is.na(qi));                r  <- ai |> filter(!is.na(ri))
  oq <- ai |> filter(!is.na(qi), !is.na(s_ord)); orr <- ai |> filter(!is.na(ri), !is.na(s_ord))
  gq  <- (q$celli  - 1L) * nq + q$qi;    gr  <- (r$celli  - 1L) * nr + r$ri
  goq <- (oq$celli - 1L) * nq + oq$qi;   gor <- (orr$celli - 1L) * nr + orr$ri
  # IRT reference (cell-independent) row indices into cyi_pool
  pqo <- which(!is.na(cyi_pool$qi) & !is.na(cyi_pool$d_ord))
  pro <- which(!is.na(cyi_pool$ri) & !is.na(cyi_pool$d_ord))

  draw <- function(wc) {
    qm  <- wmean(wc[q$cyi],   q$s,      gq,       ncell * nq)
    rm  <- wmean(wc[r$cyi],   r$s,      gr,       ncell * nr)
    qmo <- wmean(wc[oq$cyi],  oq$s_ord, goq,      ncell * nq)
    rmo <- wmean(wc[orr$cyi], orr$s_ord, gor,     ncell * nr)
    ov  <- wmean(wc[q$cyi],   q$s,      q$celli,  ncell)
    ovo <- wmean(wc[oq$cyi],  oq$s_ord, oq$celli, ncell)
    irtq <- wmean(wc[pqo], cyi_pool$d_ord[pqo], cyi_pool$qi[pqo], nq)
    irtr <- wmean(wc[pro], cyi_pool$d_ord[pro], cyi_pool$ri[pro], nr)
    list(qm = qm, rm = rm, qmo = qmo, rmo = rmo, ov = ov, ovo = ovo,
         irtq = irtq, irtr = irtr,
         eg_q     = qm[lo_idx * nq + nq]  - qm[lo_idx * nq + 1L],
         eg_r     = rm[lo_idx * nr + nr]  - rm[lo_idx * nr + 1L],
         eg_q_ord = qmo[lo_idx * nq + nq] - qmo[lo_idx * nq + 1L],
         eg_r_ord = rmo[lo_idx * nr + nr] - rmo[lo_idx * nr + 1L])
  }
  draws <- map(draw_id, function(d) draw(unname(W[, d][cyi_pool$country_text_id])))

  mat <- function(field) do.call(rbind, map(draws, field))
  ci  <- function(field, labels) {
    M <- mat(field)
    tibble(item = labels, est = M[app, ],
           lo = apply(M[boot, , drop = FALSE], 2, quantile, 0.025, na.rm = TRUE),
           hi = apply(M[boot, , drop = FALSE], 2, quantile, 0.975, na.rm = TRUE))
  }
  split_cell <- function(tb) tb |>
    tidyr::separate(item, c("cell", "bin"), sep = "@", convert = TRUE) |>
    mutate(model_key = sub("\\|.*$", "", cell), condition = sub("^[^|]*\\|", "", cell))
  gap_tbl <- function(field) ci(field, cell_lv) |> rename(cell = item) |>
    mutate(model_key = sub("\\|.*$", "", cell), condition = sub("^[^|]*\\|", "", cell))

  qn <- paste(rep(cell_lv, each = nq), 1:nq, sep = "@")
  rn <- paste(rep(cell_lv, each = nr), 1:nr, sep = "@")

  dm_q      <- split_cell(ci("qm",  qn));  dm_r      <- split_cell(ci("rm",  rn))
  dm_q_ord  <- split_cell(ci("qmo", qn));  dm_r_ord  <- split_cell(ci("rmo", rn))
  irt_ref_q <- ci("irtq", as.character(1:nq)) |> transmute(bin = as.integer(item), est, lo, hi)
  irt_ref_r <- ci("irtr", as.character(1:nr)) |> transmute(bin = as.integer(item), est, lo, hi)
  dm_eg_q     <- gap_tbl("eg_q");     dm_eg_r     <- gap_tbl("eg_r")
  dm_eg_q_ord <- gap_tbl("eg_q_ord"); dm_eg_r_ord <- gap_tbl("eg_r_ord")
  dm_ov       <- gap_tbl("ov");       dm_ov_ord   <- gap_tbl("ovo")
  eg_q_draws  <- mat("eg_q"); colnames(eg_q_draws) <- cell_lv
  eg_r_draws  <- mat("eg_r"); colnames(eg_r_draws) <- cell_lv

  sesoi <- tryCatch(readRDS(file.path(out_dir, glue("bootstrap_{year}.rds")))$sesoi,
                    error = function(e) NA_real_)

  bundle <- list(
    dm_q = dm_q, dm_r = dm_r,                    # signed dev vs panel mean, per cell x bin + CI
    dm_q_ord = dm_q_ord, dm_r_ord = dm_r_ord,    # signed dev vs IRT ord, per cell x bin + CI
    irt_ref_q = irt_ref_q, irt_ref_r = irt_ref_r,# IRT target in s-space (ord - panel_mean) per bin
    dm_eg_q = dm_eg_q, dm_eg_r = dm_eg_r,        # exaggeration gap (Q5-Q1 / libdem-closed) + CI
    dm_eg_q_ord = dm_eg_q_ord, dm_eg_r_ord = dm_eg_r_ord,
    dm_ov = dm_ov, dm_ov_ord = dm_ov_ord,        # pooled shift (attitude) + CI
    eg_q_draws = eg_q_draws, eg_r_draws = eg_r_draws, draw_id = draw_id,
    cell_lv = cell_lv, sesoi = sesoi, n_boot = n_boot
  )
  if (write) {
    dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
    path <- file.path(out_dir, glue("signeddev_xmodel_{year}.rds"))
    saveRDS(bundle, path)
    message(glue("signeddev bundle written: {path} ({round(file.size(path)/1024)} KB) · {ncell} cells"))
  }
  invisible(bundle)
}

# ── CLI ──────────────────────────────────────────────────────────────────────
parse_args <- function(a) {
  out <- list(year = 2019, runs_subdir = "expectation", n_boot = 2000, verify = FALSE)
  i <- 1
  while (i <= length(a)) {
    switch(a[[i]],
      "--year"        = { out$year        <- as.integer(a[[i + 1]]); i <- i + 2 },
      "--runs-subdir" = { out$runs_subdir <- a[[i + 1]];             i <- i + 2 },
      "--n-boot"      = { out$n_boot      <- as.integer(a[[i + 1]]); i <- i + 2 },
      "--verify"      = { out$verify      <- TRUE;                   i <- i + 1 },
      stop("unknown arg: ", a[[i]]))
  }
  out
}

# Rebuild 2019 from QMD 08's own source (top-level runs/, Llama) and diff the seven Llama
# quintile exaggeration gaps against the frozen signeddev_2019.rds (short Base:Cb… labels).
verify_2019 <- function(proj_root) {
  new <- build_signeddev_bundle(proj_root, year = 2019, runs_subdir = "", write = FALSE)$dm_eg_q
  live <- readRDS(file.path(proj_root, "data", "derived", "signeddev_2019.rds"))$dm_eg_q
  key <- tibble::tribble(
    ~cell,                                   ~lbl,
    "llama-70b|codebook",                    "Base:Cb",
    "llama-70b|evidence",                    "Base:Ev",
    "llama-70b|anonymized",                  "Base:An",
    "llama-70b|summarized",                  "Base:Su",
    "llama-70b-ft-raw|evidence-zeroshot",    "FT-raw:Ev",
    "llama-70b-ft-anon|anonymized-zeroshot", "FT-anon:An",
    "llama-70b-ft-summ|summarized-zeroshot", "FT-summ:Su")
  ne <- new$est[match(key$cell, new$cell)]
  le <- live$est[match(key$lbl, as.character(live$cell))]
  print(tibble::tibble(lbl = key$lbl, new = round(ne, 4), live = round(le, 4),
                       d = signif(abs(ne - le), 3)))
  message(glue("max |Δ quintile gap| vs QMD 08 (same source) = {signif(max(abs(ne - le), na.rm=TRUE),3)}"))
}

if (sys.nframe() == 0) {
  opt <- parse_args(commandArgs(trailingOnly = TRUE))
  proj_root <- find_panel_member_root()
  if (opt$verify) verify_2019(proj_root)
  else build_signeddev_bundle(proj_root, year = opt$year, runs_subdir = opt$runs_subdir,
                              n_boot = opt$n_boot)
}
