# Figures and tables plan

**Status:** working draft. Single home for the figure/table list, the hypothesis→exhibit map,
and the main-text vs. appendix featuring plan. Renamed from `figure-outline.md` and rebuilt
2026-08-06 around the reinterpreted narrative (below). Supersedes the earlier two-narrative
figure plan.

**Canonical anchor:** `preregistration/preregistration-draft.qmd` is canonical. Every appendix
table maps to its hypothesis labels (B1–B4, F1–F2, R1–R5, D1–D2, A1–A9). Main-text exhibits are
numbered (Figure 1–2, Table 1–2); appendix items use `S` (Table S0–S7).

## Strategy (the reframe)

The 2019 results ran opposite to the registered directional predictions, and — importantly —
many contrasts land **within ±SESOI** (Null: sign may flip but the magnitude isn't
substantively meaningful), because MAE against a sticky panel mean is nearly a non-test on the
full pool (a naive copy-forward beats every rater). Forcing the main text to be a
hypothesis-by-hypothesis scorecard obscured this. So:

- **Main text** tells the reinterpreted story only: two figures + two descriptive tables + prose
  that still *presents* the registered hypotheses and explains why the findings diverge.
  Peripheral contrasts (e.g. Base:Su vs Base:An) are not shown here.
- **Appendix** discharges the prereg formally as a series of tables (S0–S7), each registered
  test reported with its paired ΔMAE, 95% CI, and a **verdict against registration**
  (Supported / Null / Reversed) by the prereg's own SESOI rule.

The throughline the narrative rests on (results-independent, so not goalpost-moving): a rater's
value is being an *independent observation*, not minimizing MAE against a quantity the past
already predicts. "Worse than persistence" is what an honest independent coder looks like on a
low-variance target. The question that matters is decided conditional on movement (R2 on 2023),
not on the full 2019 pool.

## Narrative arc (by year, no "acts")

The paper never jumps between datasets. **2019** selects the model and establishes the
mechanism; **2023–2024 (holdout)** is a clean out-of-sample year that replicates it and carries
the deployment tests. Every carried-model confirmatory test (R1–R5, D1, D2) is on 2023, so the
selected model is never validated on the data that selected it.

## Document family (year-keyed) and architecture

Compute is split from presentation via a saved bundle, so the paper docs render in seconds and
never rerun the bootstrap.

| Role | File | Notes |
|---|---|---|
| Compute + prototype (scratch/lab notebook) | `analysis/06-bootstrap-metrics-2019.qmd` | owns the bootstrap; serializes the bundle |
| Shared helpers (code, static) | `R/bootstrap_helpers.R` | vocab + `paired_delta()`/`cell_series()`/`ft_diag` |
| Bundle (computed results) | `data/derived/bootstrap_2019.rds` | gitignored (`*.rds`); `boot_ci, boot_results, human_ref, persist_ref, sesoi, rounding_floor, movement_bins` |
| Main text | `paper/results-2019.qmd` | Fig 1, Fig 2, Table 1, Table 2 |
| Appendix | `paper/appendix-2019.qmd` | Tables S0–S7 |
| Holdout (future) | `analysis/07-…-2023.qmd`, `paper/results-2023.qmd`, `paper/appendix-2023.qmd` | parallel family for R/D/A6–A9 |

Paper docs open with `source(".../R/bootstrap_helpers.R")` then
`list2env(readRDS(".../bootstrap_2019.rds"), environment())`, so the helper functions resolve
against the bundle's objects.

## Main text (2019)

| Exhibit | Content | Prereg touchpoint | Job |
|---|---|---|---|
| **Figure 1** | MAE landscape: all 7 cells (base ladder Cb→Ev→An→Su + FT diagonal) on a common AI-MAE axis, vs. the Naive (persistence) and human-LOO rails | selection rule reads off here; LOO line = 2019 diagnostic preview of D1 | where every synthetic coder lands; centrifugal base ladder vs. centripetal FT cluster |
| **Figure 2** | Divergence from the codebook-only prior: base de-id conditions, FT diagonal, and the human coder as paired ΔMAE from base:Cb, vs. ±SESOI | reads on B1/B2 + the identity story | one ruler for "how far from the pure prior" |
| **Table 1** | Panel-mean MAE leaderboard: persistence (rounded) vs. base:Cb, base:Ev, human LOO | motivates the reframe | nobody beats copy-forward on the full pool |
| **Table 2** | MAE by 2018→2019 movement bin (persistence / base:Cb / base:Ev) | **exploratory**; previews R2 | the reversal is a stable-cell artifact; evidence helps only where the mean moves |

Prose still walks the registered hypotheses and explains the divergence, pointing to the
appendix for the formal verdicts.

## Appendix (2019) — formal prereg tables

Standard contrast columns: Contrast | Registered prediction | ΔMAE | 95% CI | Beyond SESOI? |
Verdict. Verdict rule (as registered): CI clears zero **and** ±SESOI in the predicted direction
= Supported; opposite = Reversed; includes zero or within ±SESOI = Null. Base is few-shot, FT is
zero-shot; prompt-matched companions (base zero-shot) are shown where they sharpen a reading.

| Table | Hyps | Content | 2019 verdicts (current) |
|---|---|---|---|
| **S0** | orientation | 4×4 model×condition grid + base zero-shot ablation cells | — |
| **S1** | B1–B4 | base-model identification contrasts | B1 Null, B2 Reversed, B3 Reversed, B4 Null |
| **S2** | F1 | FT vs few-shot, matched (+ prompt-matched companion) | Raw Null, **Anon Supported**, Summ Null |
| **S3** | F2 | raw-evidence column: FT levels + adjacent contrasts | both ordering steps Null |
| **S4** | A1, A2 | few-shot ablation (zero-shot vs Cb; few-shot gap gradient) | A1: Ev Null, An Reversed, Su Reversed; A2 gradient non-monotone |
| **S5** | A3 | FT codebook anchoring: levels + adjacent contrasts | ordering holds directionally (raw<anon<summ); both steps Null |
| **S6** | A4 | training-side difference-in-differences | at the SESOI boundary (borderline — do not lean on) |
| **S7** | A5 | de-identified FT transfer to raw evidence | both Null |

Confirmatory (S1–S3) and exploratory (S4–S7) are kept under separate headers, mirroring the
prereg's own split. Ordering hypotheses (F2, A3) show levels **plus** adjacent paired contrasts
so the ordering is tested, not eyeballed.

## The 2019 grid, annotated (main vs. appendix)

Models: B = base, R = FT-raw, A = FT-anon, S = FT-summ. Conditions: Cb, Ev, An, Su. FT de-id
rows are `-zeroshot`; base has extra `-zeroshot` ablation cells (feed S4).

| | Codebook | Evidence | Anonymized | Summarized |
|---|---|---|---|---|
| **Base** | Fig 1; Fig 2 anchor; S0/S1/S5 | Fig 1; Table 1; S1/S2/S7 | Fig 1/2; S1 | Fig 1/2; S1 |
| **FT-raw** | S0/S5 (A3) | Fig 1/2 diagonal; S2/S3 (F1/F2) | S0 | S0 |
| **FT-anon** | S0/S5 (A3) | S3/S7 (F2/A5) | Fig 1/2 diagonal; S2 (F1) | S0 |
| **FT-summ** | S0/S5 (A3) | S3/S7 (F2/A5) | S0 | Fig 1/2 diagonal; S2 (F1) |

## 2023–2024 holdout (future)

Parallel `results-2023.qmd` / `appendix-2023.qmd` built off a `bootstrap_2023.rds` bundle,
carrying the Base:Ev model (selection locked on 2019). Confirmatory: R1 (replication), R2
(transitions — promoted toward central, since the 2019 movement split shows the real action is
conditional on movement), R3 (2024 FH-only holdout), R4 (name-swap), R5 (re-identification
salience), D1 (agreement), D2 (thin-panel augmentation). Exploratory: A6–A9. Exhibit layout TBD
when that bundle exists.

## Retired prototypes (in `06`, not re-homed)

The reframe drops these from the paper; they remain in `06` as a lab notebook only: the old
base-delta forest plot (B1–B3 as a figure), the divergence-from-prior variants (old Fig 3-A/3-B),
and the §8 prototype appendix figures (F1 figure, selection readout, A3 anchoring figure). Their
content is now carried by Figure 2 and the S-series tables.

## Still open

- **Figure 2 wording.** The figure/axis currently say "codebook-only prior" (reader-facing);
  decide whether to keep that or revert to the internal `base:Cb` shorthand.
- **Panel-degradation opening table (optional).** A descriptive table of thinning panel sizes
  could open the main text; its data lives in `analysis/01-panel-degradation-pathologies`, not
  the 2019 bundle, so it would be built separately if wanted.

## Superseded / related docs

- `paper/figure-outline.md` — replaced by this file.
- `paper/outline.qmd` — describes a superseded design (5 models, 3 conditions, no summarized,
  LOO-MAE-primary, sampled indicators). Full rewrite tracked separately.
- `notes/stage1-preliminary-observations.md` — the analysis/interpretation notebook this plan
  operationalizes (persistence baseline, movement split, per-hypothesis reframe).
