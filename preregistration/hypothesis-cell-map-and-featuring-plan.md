# Hypothesis-to-cell map and main-text featuring plan

## Background

Follow-on to `notes/model-selection-for-robustness-checks.md`. That memo posed the model-
selection question as a choice between running the full 4×4 grid (Path A) and dropping the
nine representation-transfer off-diagonals (Path B), with compute as a live constraint.
Subsequent discussion dissolved that framing: timing runs showed the full grid is
affordable, so the question is no longer **which cells to run** but **which cells to
feature in the main text**, which model-selection rule to lock, and which hypotheses each
cell actually serves.

The reframing that drove this: from a practical deployment standpoint, the headline
question is *which model best codes raw evidence packets* — the evidence column across all
four models, benchmarked against base-codebook. Under this reading, anonymization and
summarization function two ways: as inference-time identification treatments for the base
model (their original design role, carrying the identification hypotheses), and as
*training devices* for the FT variants (does training on de-identified text make a model
better at reading raw text?). The evidence column is the cleanest version of the
training-representation-transfer question — manipulate the training representation, hold
the deployment input fixed — and within the FT rows it is a fully controlled comparison:
identical `evidence-zeroshot` prompts, only the adapter differs. (Base vs. FT within the
column additionally differs in the few-shot calibration block; that is the designed
prompt-calibration-vs-weight-calibration comparison, not a confound.)

## Where the discussion landed

- **Run the full 16-cell 2019 grid.** No cells are dropped; Path A vs. Path B is moot.
- **Feature eight cells in the main text**, organized as two results sections:
  1. **Deployment** (5 cells): base-codebook baseline + the full evidence column
     (base, FT-raw, FT-anon, FT-summ). Headline applied result; the model-selection rule
     operates here.
  2. **Identification** (base row, 4 cells — 3 beyond section 1): base × {codebook,
     evidence, anonymized, summarized}, carrying H1–H3 and H8 exactly as registered.
- **Appendix**: the six FT × {anonymized, summarized} cells (representation-transfer /
  within-FT delta replication) and the three FT codebook probes (anchoring diagnostics).
- **Selection rule**: the model carried forward to the 2023/2024 robustness work is the
  one with the lowest 2019 AI MAE in the evidence column (argmin over 4 cells). Tie rule:
  if bootstrap CIs overlap, prefer base as the simpler model. This is cleaner than the
  earlier memo's options — one condition, four models — and unlike the rejected
  condition-specific rule (Option 2 there), the conditioning column is not chosen to
  flatter an identification hypothesis; it *is* the deployment target. The identification
  deltas are within-model comparisons, so selecting across models within one column does
  not bias them.
- **Conditional commitment**: if FT-raw wins the evidence column, the anchoring probe
  (FT-raw × codebook vs. FT-anon/FT-summ × codebook) moves from appendix to main text as a
  mandatory qualifier — if FT-raw-on-codebook gets most of the way to FT-raw-on-evidence,
  the "win" is substantially country-name memorization, not evidence-reading.

### Why the base identification row stays in the main text

The design doc designates Δ(Anonymized − Codebook) as *the* primary identification result,
and H2, H3, and H8 all live in the base row of columns 3–4. That machinery answers the one
question that makes the deployment column interpretable: when evidence-column MAE looks
good, is the model reading the packet or recognizing the country? Raw evidence text is
full of country names; 2019 country-level ratings are highly autocorrelated with
pretraining knowledge, so a low MAE in the featured column could come from memorized
priors ("Norway ≈ 4"). For a deployment claim this matters *more*, not less — deployment
value depends on tracking described conditions in future years. Appendixing the base-row
identification results would turn the paper into a benchmarking exercise a reviewer can
deflate with one sentence about anchoring, and would surrender what distinguishes it from
Weidman-style zero-shot benchmarking. It costs two cells (base × anonymized, base ×
summarized), both already running.

### Anchoring probe needs all three FT codebook cells

The probe is not "FT-raw × codebook vs. base × codebook" alone — that two-cell comparison
is confounded, because an FT-raw advantage on codebook could reflect either country-name
memorization or generic scale/format calibration that any fine-tuning imparts. FT-anon and
FT-summ × codebook are the controls: same generic calibration training, but their training
prompts never paired a real country name with a rating ("the focal country" everywhere).
The memorization signature is FT-raw-codebook ≪ FT-anon/FT-summ-codebook, not
FT-raw-codebook < base-codebook. All three cells are near-free (no evidence text).

## Notation

Cells are (model × condition). Models: **B** = 70B base, **R** = FT-raw, **A** = FT-anon,
**S** = FT-summ. Conditions: **Cb** = codebook, **Ev** = evidence, **An** = anonymized,
**Su** = summarized. FT-row conditions are the `-zeroshot` variants throughout (no
calibration block; see `assemble_prompt.py`).

Four of the nine registered hypotheses (H4, H5, H7, H9) run on **2023 data with the
carried-forward model**, so they use 2023 re-runs of grid cells — and in some cases extra
cells that are not in the 4×4 at all.

## Hypotheses → cells

| # | Hypothesis (short form) | Cells needed | Year | In the 4×4 grid? |
|---|---|---|---|---|
| H1 | Evidence beats codebook-only: Δ(Ev − Cb) < 0 | B×Ev vs. B×Cb | 2019 | Yes — base row |
| H2 | Anonymization beats raw evidence: Δ(An − Ev) < 0 | B×An vs. B×Ev | 2019 | Yes — base row |
| H3 | Information gain survives anonymization: Δ(An − Cb) < 0. *Currently designated the primary identification result.* | B×An vs. B×Cb | 2019 | Yes — base row |
| H4 | Evidence gain is larger in transition-adjacent country-years (ERT moderator) | Carried model × {Cb, Ev, An, Su}, split by transition status | 2023 | 2023 re-runs of one full row |
| H5 | Re-identification predicts directional bias | Carried model × {An, Su} + re-identification follow-up prompts | 2023 | 2023 re-runs + follow-up calls (not grid cells) |
| H6 | Calibration degrades with weaker source coverage | All cells — coverage tier is a moderator *within* every cell | 2019 | Yes — whole grid |
| H7 | Few-shot examples matter more as identity cues are stripped: Δ(few-shot − zero-shot) grows Ev → An → Su | B×{Ev, An, Su} plus B×{Ev-zeroshot, An-zeroshot, Su-zeroshot} | 2019 | No — the three zero-shot ablation cells are outside the grid (2019 base-model add-on runs; few-shot comparators are the base row itself); **base-only by construction** (FT rows are already zero-shot) |
| H8 | Summarization de-identifies without large calibration cost: Δ(Su − An) not substantially positive, plus top-1 re-id < 30% target | B×Su vs. B×An; re-id part shares H5's follow-ups | 2019 (delta) + 2023 (re-id) | Yes — base row (delta part) |
| H9 | Name-swap ratings track described conditions, not the named country | Custom A/B/C prompt conditions built from summarized text, carried model | 2023 | No — bespoke cells outside the grid |

Two featured comparisons that are **not** numbered hypotheses:

| Comparison | Cells needed | In the grid? |
|---|---|---|
| Deployment: which model best codes raw evidence (headline column; selection rule) | B×Ev, R×Ev, A×Ev, S×Ev (+ B×Cb as baseline) | Yes — column 2 + cell (1,1); A×Ev and S×Ev are off-diagonals |
| Anchoring probe: does raw fine-tuning bake in country-name shortcuts | R×Cb vs. A×Cb and S×Cb (vs. B×Cb) | Yes — column 1, FT rows |

## The 2019 grid, annotated

| | **Codebook** | **Evidence** | **Anonymized** | **Summarized** |
|---|---|---|---|---|
| **Base** | H1, H3 baseline; H6; deployment baseline | H1, H2; H6; **deployment** | **H3 (primary)**, H2, H8; H6 | H8; H6 |
| **FT-raw** | anchoring probe; H6 | matched cell; **deployment**; H6 | *FT-row delta replication only; H6* | *FT-row delta replication only; H6* |
| **FT-anon** | probe control; H6 | **deployment** (off-diag); H6 | matched cell; H6 | *FT-row delta replication only; H6* |
| **FT-summ** | probe control; H6 | **deployment** (off-diag); H6 | *FT-row delta replication only; H6* | matched cell; H6 |

Main text = base row + evidence column (8 cells). Appendix = everything else (8 cells:
six FT off-diagonal/matched cells in columns 3–4, plus R/A/S × codebook — with the
conditional promotion of the codebook probes noted above).

## Three things the map makes visible

1. **H1–H3 and H8 live entirely in the base row.** The four FT cells in columns 3–4 that
   are neither matched nor probes serve only the unregistered "do the deltas replicate
   within FT models" question (plus H6, which every cell serves). Weakest hypothesis
   coverage in the grid → natural appendix material.
2. **Everything on 2023 (H4, H5, H7, H9) keys off which model is carried forward** — and
   H7 must run on base regardless of who wins, since FT conditions have no few-shot block
   to ablate. If an FT variant wins, H4/H5/H9 run on it; H7's six cells run on base either
   way. The design doc's "best-performing model" language should be replaced with this
   explicit split.
3. **The five deployment cells alone carry only H1 and the deployment comparison.** H2,
   H3, and H8 — including the currently-designated primary identification result — sit in
   B×An and B×Su. This is why the featuring plan keeps the full base row in the main text
   rather than only the deployment cells.

## Required pre-registration edits (not yet made)

This re-scoping is legitimate only if done **before any Phase 1 inference runs** — amended
pre-data it is a design decision; post-results, moving identification arms to the appendix
looks like burying. As of this writing no inference has run on any fine-tuned model, so
the window is open. `docs/experimental-design.md` edits needed:

- [ ] Designate the evidence-column model comparison (with the argmin selection rule and
      CI-overlap tie rule preferring base) as the primary confirmatory applied analysis.
- [ ] Decide whether H2/H3/H8 become co-primary (eight-cell main text, as recommended
      here) or secondary; update the "primary identification result" language accordingly.
- [ ] Replace "best-performing model" throughout Part 2 with the explicit split: carried
      model = evidence-column winner for H4/H5/H9, agreement test, and the 2024 FH
      holdout; H7 (few-shot ablation) locked to base regardless.
- [ ] Pre-specify the conditional promotion of the anchoring probe to the main text if
      FT-raw wins the evidence column, and what happens if no FT variant beats base
      (carry base; report the FT comparison honestly).
- [ ] Fix internal inconsistencies flagged earlier: Models table ("All 4 conditions",
      lines ~83–85) is now accurate again under full-grid-runs, but Figure 1/2
      descriptions and the "key comparisons" paragraph (lines ~108–112) should be aligned
      with the main-text/appendix split.
- [ ] Update `notes/model-selection-for-robustness-checks.md` to record the resolution
      (Path A/B superseded by run-everything + featuring plan + evidence-column selection
      rule).
