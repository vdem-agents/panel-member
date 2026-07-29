# Model selection for the 2023/2024 robustness checks

## Background

Phase 1+2 produce a 4×4 grid of 2019 AI MAE values — 4 models (70B base, FT-raw, FT-anon,
FT-summ) × 4 conditions (codebook, evidence, anonymized, summarized). Phase 3 (2023
test-year replication, mechanism tests, agreement test; the few-shot ablation moved to
2019/base — see `docs/experimental-design.md`) and Phase 4
(2024 Freedom-House-only holdout) are gated on identifying a single "best-performing
model" from this grid — every doc that references Phase 3/4 says "best model" without
specifying how to compute it from 16 numbers.

This matters because 2023/2024 must function as a genuine holdout: no model selection or
model-vs-model comparison should happen on that data, only on 2019 (see the test-set-
integrity discussion below). Whatever selection rule is used has to be locked using 2019
data alone, before any 2023/2024 inference is run.

The complication: "best model" and "best strategy" (best model+condition combination) are
not obviously the same thing, and a naive selection rule can conflate the two.

---

## The full 4×4 grid

| | **Codebook** | **Evidence** | **Anonymized** | **Summarized** |
|---|---|---|---|---|
| **70B base** | `codebook`<br>no text, no few-shot | `evidence`<br>raw text + few-shot | `anonymized`<br>anon text + anon few-shot | `summarized`<br>summ text + summ few-shot |
| **FT-raw** | `codebook`<br>*country-identity anchoring probe* | `evidence-zeroshot`<br>**matched (home condition)** | `anonymized-zeroshot`<br>*representation-transfer* | `summarized-zeroshot`<br>*representation-transfer* |
| **FT-anon** | `codebook`<br>*out-of-distribution probe* | `evidence-zeroshot`<br>*representation-transfer* | `anonymized-zeroshot`<br>**matched (home condition)** | `summarized-zeroshot`<br>*representation-transfer* |
| **FT-summ** | `codebook`<br>*out-of-distribution probe* | `evidence-zeroshot`<br>*representation-transfer* | `anonymized-zeroshot`<br>*representation-transfer* | `summarized-zeroshot`<br>**matched (home condition)** |

Two structural facts drive the discussion below, both confirmed in `assemble_prompt.py`:

- **Few-shot asymmetry**: base model conditions carry a calibration block (`evidence`,
  `anonymized`, `summarized`); FT conditions never do (`-zeroshot` suffix) — calibration
  is supposed to live in the adapter weights instead of the prompt.
- **Country-identity asymmetry in FT training data**: `finetuned-anon` and
  `finetuned-summ` training prompts replace the country name and year with placeholders
  ("the focal country" / "the focal year") *everywhere in the prompt*, not just in the
  evidence text. `finetuned-raw` training prompts state the real country name and year on
  every example, correlated with the target rating. Codebook-only inference always states
  the real country name and year (`_codebook_user`), regardless of model. So FT-raw's
  codebook-only cell is close to its training distribution (real country name, no evidence
  text); FT-anon's and FT-summ's codebook-only cells are genuinely out-of-distribution for
  their adapters (a real country name where the adapter never learned to use one). This
  makes the FT-row codebook-only cells a cheap, informative probe for whether raw-evidence
  fine-tuning specifically bakes in country-identity anchoring — independent of whichever
  selection rule is adopted below.

---

## Options considered

### Option 1: Single best cell (argmin over all 16 cells) — set aside

Pick whichever of the 16 model×condition cells has the lowest 2019 AI MAE; the model
that owns that cell is "the best model," carried forward across all four conditions.

This makes "best model" and "best strategy" identical by construction, and since Phase
3/4 already reruns all four conditions for the winner, the winning configuration gets
holdout-validated for free.

Set aside because picking an argmin over 16 noisy point estimates is exposed to
winner's-curse — the top cell can look best partly by chance, and a fix (CI-overlap
tie-break falling back to an aggregate criterion) reintroduces the complexity it was
supposed to avoid.

### Option 2: Condition-specific or hypothesis-driven selection — rejected

E.g., select the model with the lowest MAE specifically under the summarized condition
(motivated by the theory that summarization should isolate genuine calibration from
anchoring), or: find whichever condition has the lowest MAE on average across all four
models, then pick the best model within that condition.

Rejected. There is no literal data leakage — 2023/2024 are never touched by the selection
step — but tying model selection to a condition that is *also* a primary hypothesis-testing
arm (e.g. summarized, central to hypothesis 8) creates the appearance of selecting a
criterion designed to make that hypothesis look good. A selection rule that treats all four
conditions symmetrically avoids this regardless of which specific condition ends up
mattering most.

### Option 3 ("Path A"): Average MAE across the four 2019 conditions per model

Run the full 4×4 grid (16 cells). For each model, average its AI MAE across all four
conditions; the model with the lowest average is "best," carried forward across all four
conditions in Phase 3/4.

- Symmetric across conditions — doesn't favor any one condition or hypothesis (avoids the
  Option 2 problem).
- Less exposed to winner's-curse than Option 1, since it's an average of four numbers
  rather than an argmin over sixteen.
- Matches what Phase 3/4 actually needs: a model that performs reasonably across all four
  conditions, not one with a single spectacular cell and three mediocre ones.
- Requires the full 16-cell grid — all four conditions run for all three FT variants,
  including the nine "representation-transfer" cells (FT model trained on one text
  representation, evaluated on another).
- Under this option, "best strategy" (the applied deployment recommendation) is not locked
  from 2019 — it's read off the winning model's 2023 results after the fact: whichever of
  its four conditions has the lowest 2023 AI MAE. This is arguably better than locking a
  "best cell" from 2019, since it's holdout-validated rather than resting on the same data
  used to select the model.

### Option 4 ("Path B"): Matched-condition design, headline results only

Drop the nine representation-transfer cells. Run: 70B base × all four conditions (4 cells,
unchanged — this is the backbone of the primary identification claims and isn't a
selection candidate), plus each FT variant against its own matched condition only:
FT-raw × evidence, FT-anon × anonymized, FT-summ × summarized (3 cells). Add the three
FT-row codebook-only anchoring-probe cells cheaply, since they need no new evidence text
(FT-raw × codebook, FT-anon × codebook, FT-summ × codebook). Total: 10 cells instead of 16.

- No global "best model" argmin or average needed. Base always advances to Phase 3/4 (it's
  structurally required for the identification-delta replication). Separately, whichever
  FT variant beats base on its own matched comparison (e.g. FT-anon-on-anonymized vs.
  base-on-anonymized) is the one worth carrying forward for the applied "does fine-tuning
  beat few-shot prompting" question — under its own matched condition only, not all four.
- Substantially cheaper: 3 FT cells instead of 12.
- Preserves the codebook-only anchoring probe (FT-raw vs. FT-anon/FT-summ vs. base) at
  near-zero marginal cost.
- Loses the `FT-anon vs. FT-raw` / `FT-summ vs. FT-raw` comparison (does *training-data*
  representation matter, holding *inference-time* representation fixed) — this requires
  observing FT-raw on anonymized/summarized text, which this design never runs.
- Loses within-FT-model replication of the primary identification deltas — you can't ask
  "does Δ(Evidence−Codebook) hold for FT-anon specifically" if FT-anon only ever produces
  one non-codebook data point.
- The headline fine-tuning-vs-prompting comparison per strategy survives fully intact,
  and arguably better reflects real deployment decisions — nobody would deploy FT-anon on
  raw text in practice, so the matched cells are the practically relevant ones anyway.

---

## Summary of tradeoffs

| | Cells run | Resolves "best model" automatically? | Preserves representation-transfer diagnostic? | Preserves within-FT-model delta replication? | Compute |
|---|---|---|---|---|---|
| Option 1 (single best cell) | 16 | Yes, by construction | Yes | Only for the winning model | Full grid |
| Option 2 (condition-specific) | 16 | Yes, but methodologically compromised | Yes | Only for the winning model | Full grid |
| Option 3 / Path A (average MAE) | 16 | Yes — lowest average wins | Yes | Only for the winning model | Full grid |
| Option 4 / Path B (matched + codebook probes) | 10 | Mostly — base always advances; FT winner decided per matched pair | No | No | ~60% of full grid |

---

## Decision (locked 2026-07-24)

**Path A (Option 3) adopted.** The full 16-cell 4×4 grid runs on 2019: all three FT
variants × all four conditions, including the nine representation-transfer cells. The
"best model" selection rule is the average AI MAE across each model's four 2019
conditions; the model with the lowest average is carried forward across all four
conditions in Phase 3/4. Because the panel mean is a fixed reference shared by all models
(see `docs/experimental-design.md`, Outcome section), this is equivalent to selecting on
the substitution-check criterion as well, so no separate rule is needed there.

This resolves Phase 1+2 scoping: FT inference runs under all four conditions per variant,
not just the matched condition, so the representation-transfer and within-FT-model delta
questions (FT-anon vs. FT-raw, FT-summ vs. FT-raw; does Δ(Evidence−Codebook) replicate
within each FT model) are answered rather than designed away.

**Featuring**: the matched/diagonal cells (base × all four; FT-raw × evidence-zeroshot;
FT-anon × anonymized-zeroshot; FT-summ × summarized-zeroshot) and the three codebook-only
anchoring-probe cells carry the main-text results. The nine off-diagonal
representation-transfer cells are reported in the appendix. See
`preregistration/hypothesis-cell-map-and-featuring-plan.md` for the full cell-by-cell
featuring plan; that doc's checklist against `docs/experimental-design.md` (replacing
"best-performing model" language, designating co-primary hypotheses, pre-specifying the
conditional promotion of the anchoring probe) is still open and tracked there separately.

"Best strategy" (the applied deployment recommendation) is still not locked from 2019 —
per Option 3's original rationale, it is read off the winning model's 2023 results after
the fact: whichever of its four conditions has the lowest 2023 AI MAE. This is
holdout-validated rather than resting on the same data used to select the model.

Options 1, 2, and 4 (Path B) were considered and rejected/set aside per the discussion
above; that reasoning is preserved for the record and is unchanged by this decision.
