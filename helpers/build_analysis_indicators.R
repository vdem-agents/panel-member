# build_analysis_indicators.R — the indicator set the paper's results actually rest on.
#
# Three different indicator sets circulate in this project and they are easy to confuse:
#
#   262  staged in shared/vdem-data/panel_means.csv -- what the pipeline had available
#   205  SCORED across data/output/runs/**.jsonl    -- what the paper's results rest on
#   152  analysis/01's `working_indicators`         -- a direction-coded SUBSET, built for
#        Analyses 1-3, which need a sign relative to polyarchy. Its filter keeps only
#        indicators whose 2020 values span the full 0-4 ordinal range and correlate with
#        polyarchy at |r| > 0.10, so it drops 64 indicators the paper does score.
#
# The descriptive panel-size figures should describe the analytic sample, not the
# direction-coded subset, so they use this set. Analyses 1-3 keep `working_indicators`
# because they genuinely need the direction coding.
#
# The union across all run files equals the single-run set exactly (205 either way), so
# the scored set is stable across years, models and conditions.
#
# Reads the `indicator` field by regex rather than parsing each JSONL: the run files are
# large and only one field is needed.
#
# Output: panel-member/data/derived/analysis_indicators.rds -- a list of:
#   indicators   sorted character vector of scored indicator names
#   with_nr      those carrying an _nr column in the installed vdemdata
#   with_sd      those carrying an _sd column
#   meta         file count, vdemdata version, build time
#
# Usage:
#   Rscript helpers/build_analysis_indicators.R

suppressPackageStartupMessages({ library(dplyr) })

find_panel_member_root <- function() {
  up <- tryCatch(rprojroot::find_root(rprojroot::is_git_root), error = function(e) NA_character_)
  if (!is.na(up)) return(up)
  down <- file.path(getwd(), "panel-member")
  if (dir.exists(file.path(down, ".git"))) return(down)
  stop("Could not locate the panel-member project root from working dir: ", getwd())
}

build_analysis_indicators <- function(proj_root,
                                      runs_dir = file.path(proj_root, "data", "output", "runs"),
                                      out_dir  = file.path(proj_root, "data", "derived"),
                                      write    = TRUE) {

  files <- list.files(runs_dir, pattern = "\\.jsonl$", recursive = TRUE, full.names = TRUE)
  if (!length(files)) stop("No run files found under ", runs_dir)
  message("Scanning ", length(files), " run files...")

  inds <- unique(unlist(lapply(files, function(f) {
    ln <- readLines(f, warn = FALSE)
    m  <- regmatches(ln, regexpr('"indicator"\\s*:\\s*"[^"]*"', ln))
    sub('.*"indicator"\\s*:\\s*"([^"]*)".*', "\\1", m)
  })))
  inds <- sort(inds[nzchar(inds)])
  message("Scored indicators: ", length(inds))

  vd <- tryCatch(vdemdata::vdem, error = function(e) NULL)
  with_nr <- if (is.null(vd)) character(0) else inds[paste0(inds, "_nr") %in% names(vd)]
  with_sd <- if (is.null(vd)) character(0) else inds[paste0(inds, "_sd") %in% names(vd)]
  message("With _nr: ", length(with_nr), " | with _sd: ", length(with_sd))

  out <- list(
    indicators = inds,
    with_nr    = with_nr,
    with_sd    = with_sd,
    meta = list(
      n_files          = length(files),
      runs_dir         = runs_dir,
      vdemdata_version = as.character(utils::packageVersion("vdemdata")),
      built_at         = Sys.time()
    )
  )

  if (write) {
    dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
    f <- file.path(out_dir, "analysis_indicators.rds")
    saveRDS(out, f)
    message("Wrote ", f)
  }
  out
}

if (sys.nframe() == 0) {
  res <- build_analysis_indicators(find_panel_member_root())
  cat("\nScored indicators:", length(res$indicators),
      "| with _nr:", length(res$with_nr),
      "| with _sd:", length(res$with_sd), "\n")
  cat("First 10:", paste(head(res$indicators, 10), collapse = ", "), "\n")
}
