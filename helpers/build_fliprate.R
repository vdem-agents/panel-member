# build_fliprate.R — the deployment figures: does a synthetic seat change a panel's VERDICT,
# and does it do so more than ordinary human coder turnover?
#
# Both outcomes below appear as the two panels of ONE figure, drawn by fig_fliprate_quad():
# mechanic = "add" is the main-text deployment figure (augmentation, the scenario the paper
# motivates) and mechanic = "rep" its appendix companion (replacement). Section numbers are
# not named here because the appendix has renumbered twice.
#
# A verdict is round(panel mean) = floor(mean + 0.5) — the panel's own rounded judgement, the
# same rounding the SESOI derives from in build_bundles.R. It is NOT V-Dem's published `_ord`,
# which comes from the measurement model, so nothing here licenses a claim about how many
# published scores would change.
#
# Outcomes, both against a REAL held-out-coder churn benchmark:
#   flip      share of panels whose verdict changes            -> Panel A
#   netd      (down-flips - up-flips), minus churn's own       -> Panel B
#
# Why churn has to be plotted rather than assumed: build_augmentation.R can zero-reference
# because a mean SHIFT from refilling a seat is zero in expectation. A verdict FLIP from churn
# is emphatically not zero — it runs 16-42% here — so it is measured, not assumed away.
#
# THE DESIGN. A real-churn benchmark needs spare real coders, and thin panels do not have any.
# So thinness is constructed rather than observed, holding the BASE panel size fixed (a base of
# m-k would shrink as k grows and confound the dose-response with panel size):
#
#   B = 4          base panel size; its verdict is the baseline
#   source panels  >= B + KMAX = 8 coders  (7,775 panels, 110 countries in 2023)
#   per MC draw    randomly permute the panel's coders
#                    ranks 1..B        -> the base panel
#                    ranks B+1..B+KMAX -> held-out humans, the churn arm's seats
#
#   --mechanic augmentation   ADD k seats;     panel grows B -> B+k
#   --mechanic degradation    REPLACE k seats; panel size stays at B
#
# Both arms start from the identical base panel, so the AI-vs-churn contrast is within-panel and
# panel size cannot drive it.
#
# TRADE-OFF that must travel with the figure: source panels are ones that HAVE >= 8 coders, the
# deepest ~quarter of 2023, which are not the thin panels in the field. This is a controlled
# experiment on constructed thinness. See notes/mockups/flip-rate-concept.md for the
# observational counterpart (real thin panels, resampled churn) and why its benchmark is weaker.
#
# ROUNDING PARITY, augmentation only. With B=4 the base mean is a multiple of 0.25, so exact
# half-integers are common and floor(x+0.5) rounds them up: a base at 2.5 has verdict 3, so any
# added rating below the mean drops it while additions above merely confirm — a built-in downward
# push. It then alternates with k, because k=1,3 give panel sizes 5 and 7 where a new mean can
# never land on .5, while k=2,4 give 6 and 8 where ties are possible. Human churn shows the same
# zigzag, which is the tell that it is arithmetic. Both arms face identical base panels and
# identical parity, so `netd` (differenced against churn, paired at the panel level) cancels it.
# Under --mechanic degradation the denominator never changes, so the alternation cannot arise and
# raw net-down for churn comes out flat (-0.1 to -0.3 pts).
#
# Usage:
#   Rscript helpers/build_fliprate.R --mechanic augmentation
#   Rscript helpers/build_fliprate.R --mechanic degradation

suppressPackageStartupMessages({
  library(data.table); library(tidyverse); library(jsonlite); library(glue)
})

build_fliprate <- function(proj_root,
                           mechanic = c("augmentation", "degradation"),
                           year     = 2023L,
                           B        = 4L,
                           kmax     = 4L,
                           n_mc     = 30L,
                           n_boot   = 2000L,
                           seed     = 42L,
                           write    = TRUE) {
  mechanic <- match.arg(mechanic)
  yr <- year   # data.table masks `year` with the column of the same name
  source(file.path(proj_root, "helpers", "bootstrap_helpers.R"))
  dd <- file.path(proj_root, "data", "processed")
  rd <- file.path(proj_root, "data", "output", "runs", as.character(year))
  rnd <- function(x) floor(x + 0.5)
  set.seed(seed)

  fams <- c("llama-70b", "qwen-72b", "gemma-27b")
  pool <- rbind(CJ(model_key = fams,
                   condition = c("codebook", "evidence", "anonymized", "summarized")),
                CJ(model_key = paste0(fams, "-ft-raw"),
                   condition = c("codebook", "evidence-zeroshot")))
  pool[, `:=`(cell = paste(model_key, condition, sep = "|"), is_ft = grepl("ft-raw", model_key))]
  SAME_CELL <- "qwen-72b-ft-raw|evidence-zeroshot"

  needed <- c("country", "year", "indicator", "condition", "model_key", "rating")
  rr <- function(f) { con <- file(f, "r"); on.exit(close(con))
    stream_in(con, verbose = FALSE) |> as_tibble() |> select(all_of(needed)) }
  ai <- rbindlist(lapply(list.files(rd, pattern = "jsonl$", full.names = TRUE), rr))[
    , model_key := sub("-local$", "", model_key)][year == yr][
    , cell := paste(model_key, condition, sep = "|")][cell %in% pool$cell]
  setnames(ai, "country", "country_text_id")
  ai <- unique(ai, by = c("cell", "country_text_id", "indicator"))[
    , key := paste(country_text_id, indicator)]

  hr <- fread(file.path(dd, "human_ratings.csv"))[
    year == yr & indicator %in% unique(ai$indicator),
    .(country_text_id, indicator, rating)][, key := paste(country_text_id, indicator)]
  big <- hr[, .N, by = key][N >= B + kmax, key]
  hr  <- hr[key %in% big]

  A <- dcast(ai[key %in% big], key ~ cell, value.var = "rating")
  A <- A[complete.cases(A)]; setcolorder(A, c("key", pool$cell))
  hr <- hr[key %in% A$key]
  pan <- unique(hr[, .(key, country_text_id)]); setkey(pan, key); setkey(A, key)
  pan <- pan[A[, .(key)]]
  AM <- as.matrix(A[, -1]); rownames(AM) <- NULL
  FT_IDX <- which(pool$is_ft); SAME_IDX <- which(pool$cell == SAME_CELL)
  message(glue("[{mechanic}] source panels (n>={B+kmax}): {nrow(pan)} | ",
               "countries: {uniqueN(pan$country_text_id)}"))

  # k AI seats drawn WITHOUT replacement from a regime's cells, as cumulative prefix sums
  prefix_sums <- function(Amat, idx, kmax) {
    U <- matrix(runif(nrow(Amat) * length(idx)), nrow(Amat), length(idx))
    RK <- matrix(0L, nrow(Amat), length(idx))
    for (j in seq_along(idx)) RK[, j] <- rowSums(U < U[, j])
    As <- Amat[, idx, drop = FALSE]
    vapply(seq_len(kmax), function(k) rowSums(As * (RK < k)), numeric(nrow(Amat)))
  }
  boot_ci <- function(v, ctry) {
    agg <- data.table(c = ctry, v = v)[, .(s = sum(v), m = .N), by = c]
    W <- country_boot_weights(agg$c, n_boot, seed = seed); w <- W[agg$c, , drop = FALSE]
    est <- colSums(w * agg$s) / colSums(w * agg$m)
    a <- which(colnames(W) == "Apparent"); b <- setdiff(seq_along(est), a)
    list(est = est[a], lo = unname(quantile(est[b], .025)), hi = unname(quantile(est[b], .975)))
  }

  regimes <- list("Same AI (Qwen FT)" = SAME_IDX, "Mixed FT (6 cells)" = FT_IDX,
                  "Mixed pool (18 cells)" = seq_len(nrow(pool)))
  arm_nm <- c(names(regimes), "Human churn")
  flipA <- dirA <- array(0, c(nrow(pan), kmax, length(arm_nm)))

  for (i in seq_len(n_mc)) {
    h <- copy(hr)[, u := runif(.N)]
    setorder(h, key, u); h[, rk := seq_len(.N), by = key]
    base <- h[rk <= B, .(Sb = sum(rating)), by = key]
    setkey(base, key); base <- base[pan[, .(key)]]
    Sb <- base$Sb; old <- rnd(Sb / B)

    held <- h[rk > B & rk <= B + kmax][, cum := cumsum(rating), by = key]
    HM <- as.matrix(dcast(held, key ~ rk, value.var = "cum")[, -1])

    if (mechanic == "degradation") {
      # seats vacated: the k highest base ranks (a random subset, the panel being permuted)
      drop <- h[rk <= B][, rr2 := B - rk + 1L]
      setorder(drop, key, rr2); drop[, dcum := cumsum(rating), by = key]
      DM <- as.matrix(dcast(drop, key ~ rr2, value.var = "dcum")[, -1])
      denom <- matrix(B, nrow(pan), kmax)
    } else {
      DM <- matrix(0, nrow(pan), kmax)
      denom <- outer(rep(B, nrow(pan)), seq_len(kmax), `+`)
    }

    arms <- c(lapply(names(regimes), function(rg)
                if (rg == "Same AI (Qwen FT)") outer(AM[, SAME_IDX], seq_len(kmax))
                else prefix_sums(AM, regimes[[rg]], kmax)),
              list(HM))
    for (a in seq_along(arms)) {
      d <- rnd((Sb - DM + arms[[a]]) / denom) - old
      flipA[, , a] <- flipA[, , a] + (d != 0)
      dirA[, , a]  <- dirA[, , a]  + sign(d)
    }
  }
  flipA <- flipA / n_mc; dirA <- dirA / n_mc

  CHURN <- which(arm_nm == "Human churn")
  effects <- rbindlist(lapply(seq_along(arm_nm), function(a)
    rbindlist(lapply(seq_len(kmax), function(k) {
      f  <- boot_ci(flipA[, k, a], pan$country_text_id)
      g  <- boot_ci(-dirA[, k, a], pan$country_text_id)
      hd <- boot_ci(-(dirA[, k, a] - dirA[, k, CHURN]), pan$country_text_id)
      data.table(regime = arm_nm[a], k = k,
                 flip = f$est, flip_lo = f$lo, flip_hi = f$hi,
                 net  = g$est, net_lo  = g$lo, net_hi  = g$hi,
                 netd = hd$est, netd_lo = hd$lo, netd_hi = hd$hi)
    }))))

  bundle <- list(effects = effects, mechanic = mechanic, year = year, B = B, kmax = kmax,
                 n_mc = n_mc, n_boot = n_boot, seed = seed, n_panels = nrow(pan),
                 n_countries = uniqueN(pan$country_text_id))
  if (write) {
    out_dir <- file.path(proj_root, "data", "derived")
    dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
    path <- file.path(out_dir, glue("fliprate_{mechanic}_{year}.rds"))
    saveRDS(bundle, path)
    message(glue("flip-rate ({mechanic}) bundle written: {path} · {nrow(effects)} rows"))
  }
  invisible(bundle)
}

parse_args <- function(a) {
  out <- list(mechanic = "augmentation", year = 2023L); i <- 1
  while (i <= length(a)) {
    switch(a[[i]],
      "--mechanic" = { out$mechanic <- a[[i + 1]]; i <- i + 2 },
      "--year"     = { out$year <- as.integer(a[[i + 1]]); i <- i + 2 },
      { i <- i + 1 })
  }
  out
}

if (sys.nframe() == 0L) {
  proj_root <- rprojroot::find_root(rprojroot::is_git_root)
  opt <- parse_args(commandArgs(trailingOnly = TRUE))
  build_fliprate(proj_root, mechanic = opt$mechanic, year = opt$year)
}
