# Figure and narrative plan

**Status:** working draft. Single home for the figure list, the hypothesis-to-figure map,
and the main-text vs. appendix featuring plan. Supersedes `paper/figures-and-hypothesis-map.qmd`
and the featuring content of `preregistration/hypothesis-cell-map-and-featuring-plan.md`
(see "Superseded docs" below).

**Canonical anchor:** `preregistration/preregistration-draft.qmd` is canonical. Every figure
maps to its hypothesis labels (B1–B4, F1–F2, R1–R5, D1–D2, A1–A9). The old `H1–H9` scheme
and the old `R1–R10`/`F1–F5` renumbering are retired. Main-text figures are numbered 1–9;
appendix/supplementary items use `S` (Fig S1, Table S1) to avoid colliding with the A-series
hypothesis labels.

## Narrative arc

Two acts, organized by year, so the paper never jumps between datasets. 2019 selects the
model and establishes the mechanism; 2023/2024 is a clean holdout that replicates it and
carries the deployment tests. Every carried-model confirmatory test (R1–R5, D1, D2) is on
2023, so the selected model is never validated on the data that selected it.

- **Act 1 — Establish (2019).**
  - *How good / usable* — the diagonal comparison: which model is best on the input it was
    built for. The human LOO reference line on this figure doubles as the 2019 diagnostic
    preview of the agreement test.
  - *Why good — text or parametric knowledge?* — the base model is the clean instrument for
    the text-vs-identity manipulation (no training-condition confound), and the FT anchoring
    probe extends the mechanism question to the deployed models (do they read, or memorize
    country→rating shortcuts?).
- **Act 2 — Replicate and deploy (2023/2024, carried model).**
  - *Does it hold* — the identification results and mechanism tests replicated out of sample.
  - *Is it deployable* — agreement and thin-panel augmentation, the applied payoff, closing
    the paper.

## Selection rule (recap, not re-derivation)

Carried model = lowest 2019 AI MAE **in its own condition**: FT-raw on raw evidence, FT-anon
on anonymized, FT-summ on summarized, base on raw evidence (no training condition of its own).
Ties (overlapping bootstrap CIs) go to base. Full statement in the prereg Analysis Plan.

## Main-text figures

Provisional numbering. "Carried model" = the diagonal winner. Narrative-job cells are
placeholder stubs, not final copy.

### Act 1 — Establish (2019)

**How good / usable**

| Fig | Content | Scope | Prereg hyps | Narrative job (stub) |
|---|---|---|---|---|
| 1 | Diagonal: each model on its own condition (FT-raw:Ev, FT-anon:An, FT-summ:Su) + base:Cb baseline + base:Ev, with human LOO MAE reference line | base + 3 FT diagonal cells | F1; selection rule reads off here; LOO line = 2019 diagnostic preview of D1 | best deployable model on the input it was built for |

**Why good — text vs. parametric**

| Fig | Content | Scope | Prereg hyps | Narrative job (stub) |
|---|---|---|---|---|
| 2 | Base-model identification deltas: 4 panels, Δ(Ev−Cb), Δ(An−Cb), Δ(An−Ev), Δ(Su−An) | base only | B1, B2, B3, B4 | the clean instrument: is the base model reading evidence or country identity |
| 3 | FT anchoring probe: FT-raw:Cb vs. FT-anon:Cb vs. FT-summ:Cb, vs. base:Cb | FT rows + base, codebook only | A3 (promoted from appendix) | do the deployed FT models read, or bake in a memorized country→rating shortcut |

### Act 2 — Replicate and deploy (2023/2024, carried model)

**Does it hold**

| Fig | Content | Scope | Year | Prereg hyps | Narrative job (stub) |
|---|---|---|---|---|---|
| 4 | Delta replication: the Fig 2 panels, 2019 vs. 2023 overlay | carried model | 2019 vs. 2023 | R1 | do the identification results hold in a later year |
| 5 | Information shift: Δ(Ev−Cb), Δ(An−Cb), Δ(Su−Cb) × {all, stable, transition-adjacent} | carried model | 2023 | R2 | evidence carries more marginal information in transition years |
| 6 | 2024 holdout: Δ(Ev−Cb), Δ(An−Cb), 2023 FH-only vs. 2024 FH-only | carried model | 2023 vs. 2024, FH-only | R3 | the evidence gain persists past the knowledge cutoff |
| 7 | Name-swap: distance to source vs. named panel mean, by re-identification status | carried model | 2023 | R4 | swapped ratings track described conditions, not the named country |
| 8 | Re-identification salience filter: Δ(Ev−Cb) for re-identified vs. non-identified cases | carried model | 2023 | R5 | salient cases lean less on the text |

**Is it deployable** (closes the paper)

| Fig | Content | Scope | Year | Prereg hyps | Narrative job (stub) |
|---|---|---|---|---|---|
| 9 | Deployment, two panels (see below): (A) agreement, (B) thin-panel augmentation | carried model | 2023 | D1, D2 | the AI stays inside the envelope of normal human variation |

#### Figure 9 construction (D1 + D2 in one figure)

D1 and D2 don't share units (D1 is in MAE / rating points, D2 is in panel-mean-shift units),
so they can't share an x-axis, but they share a grammar: each is an AI estimate (dot + 95% CI)
judged against a human-derived reference line, where **below the line = within human range**.
Build it as two stacked panels with the same visual language and separate, labeled x-axes:

```
  Within human tolerance
  ─────────────────────────────────────────
  A · Agreement (D1)        [MAE, 2023]
        codebook      ●───┤
        evidence    ●──┤
      ▶ own cond.   ●─┤             ┆ human LOO MAE
        anonymized   ●──┤           ┆ (band = its CI)
                         left of line = within range
  ─────────────────────────────────────────
  B · Non-disruption (D2)   [panel-mean shift, 2023]
        add 1 AI      ●──┤          ┆ 90th-pct human swap
  ─────────────────────────────────────────
```

- Panel A shows the carried model's AI MAE by condition against the human LOO line (shaded
  band = the LOO CI). Highlight the carried model's **own condition** (the ▶ row, the
  registered D1 test); show the other three conditions lighter as context.
- Panel B shows the single augmentation-divergence estimate against the 90th-percentile
  human coder-swap threshold.
- Shared dot/whisker style, shared "dashed human line + shaded band, left = safe" reading;
  D2's lone CI reads as rhyming with panel A rather than stranded.
- Caption carries the asymmetric decision rules: D1 passes when the estimate sits at/below the
  LOO line; D2 flags a problem only if even the CI's lower bound clears the threshold.
- (A normalized single-axis alternative — plot each as a fraction of its own benchmark, one
  axis, reference line at 1.0 — is tighter but needs CI transforms and ratio reading. Not the
  plan; noted only as a fallback.)

Actual rendering (ggplot) is deferred; apply the dataviz conventions when we build it.

## Appendix / supplementary

| # | Content | Scope | Year | Prereg hyps | Job |
|---|---|---|---|---|---|
| Table S1 | Full 4×4 AI MAE grid, point estimates and bootstrap CIs (the old main-text orientation figure) | 16 cells | 2019 | orientation | one place to see every cell's number |
| Fig S1 | Raw-evidence column: all four models on raw evidence, vs. base:Cb | 4 models × evidence | 2019 | F2, A5 | mechanism, training side: de-identification isolated on a fixed raw input; representation transfer to raw. F2 stays confirmatory in the prereg; result stated in main-text prose |
| Fig S2 | FT off-diagonal / within-FT delta replication (anonymized and summarized columns) | 6 off-diagonal FT cells | 2019 | A4 | training-side difference-in-differences analog of B4; do the deltas replicate within FT models |
| Fig S3 | Few-shot ablation: Δ(few-shot − zero-shot) for Ev / An / Su | base only | 2019 | A1, A2 | what the calibration block contributes vs. the source text |
| Fig S4 | Re-identification accuracy and signed deviation, by regime type / region, anonymized vs. summarized | carried model | 2023 | A6, A7 | re-id rates; directional bias among re-identified cases |
| Fig S5 | Salience gap by model | all four models | 2023 | A8 | de-identified training blunts the salience effect |
| Fig S6 | Coverage-tier moderation: AI MAE by coverage tier | carried model (others where run) | 2019/2023 | A9 | calibration degrades as source coverage weakens |

## The 2019 grid, annotated (main vs. appendix)

Models: B = base, R = FT-raw, A = FT-anon, S = FT-summ. Conditions: Cb, Ev, An, Su.
FT rows are `-zeroshot` throughout (no calibration block).

| | Codebook | Evidence | Anonymized | Summarized |
|---|---|---|---|---|
| **Base** | main: Fig 1 baseline, Fig 2 (B1/B3) | main: Fig 1, Fig 2 (B1, B2) | main: Fig 2 (**B3 primary**, B2) | main: Fig 2 (B4) |
| **FT-raw** | main: Fig 3 (A3 probe) | **main: Fig 1 — diagonal** (F1); also Fig S1 (F2/A5) | appendix: Fig S2 (A4) | appendix: Fig S2 (A4) |
| **FT-anon** | main: Fig 3 (A3 control) | appendix: Fig S1 (F2/A5) | **main: Fig 1 — diagonal** (F1) | appendix: Fig S2 (A4) |
| **FT-summ** | main: Fig 3 (A3 control) | appendix: Fig S1 (F2/A5) | appendix: Fig S2 (A4) | **main: Fig 1 — diagonal** (F1) |

Main text = base row (4) + FT diagonal (3) + FT codebook probe (3) = 10 cells. Appendix =
the other 6.

## Open decisions

Settled: diagonal leads; two-act (year) arc; D1+D2 as one two-panel deployment figure closing
the paper; confirmatory D1/D2 on 2023, 2019 agreement diagnostic-only via the Fig 1 LOO line
(no separate 2019 confirmatory agreement hypothesis); F2 to appendix (still confirmatory);
few-shot ablation to appendix; FT anchoring probe (A3) promoted to the main-text mechanism
section; orientation figure demoted to Table S1.

Still open:

1. **Base model's condition in the selection argmin.** The prereg currently pins base to raw
   evidence. If B4 holds (summarization helps the base model), that slightly handicaps base,
   the mirror of the handicap we removed from the FT models. Leave base on evidence for
   simplicity, or let it compete on its own best condition. Only bites if base is a real
   contender to win the argmin.

## Superseded docs

Consolidated into this file and removed from the tree (recoverable via git history):

- `paper/figures-and-hypothesis-map.qmd`
- `preregistration/hypothesis-cell-map-and-featuring-plan.md`
- `preregistration/model-selection-for-robustness-checks.md`

Still pending, out of scope for this pass:

- `paper/outline.qmd` — describes a superseded design (5 models, 3 conditions, no summarized,
  LOO-MAE-primary, sampled indicators, 2019/2022). Full rewrite tracked separately.
