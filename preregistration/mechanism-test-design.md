# Mechanism Test Design: Re-identification, Name Swap, Information Shift, and 2024 Holdout

*From design discussion 2026-07-18. Related: issue #25, issue #26, issue #28.*

## The unified claim

All three mechanism tests address the same underlying question: does the calibration
gain from the evidence conditions come from the model reading the text, or from routing
through country-identity priors? Rather than three separate robustness checks, these
should be presented as a single mechanism test section with three interlocking pieces —
each ruling out a different alternative explanation. The 2024 temporal holdout is a
fourth, complementary test that addresses the same question via structural exclusion
rather than experimental manipulation.

---

## How this compares to the original plan

Original plan had five independent robustness checks:
1. Test-year replication (2023)
2. Few-shot calibration ablation (2023)
3. Information shift (2024) — transition-adjacent vs. stable
4. Re-identification (2023)
5. Agreement test / Applied performance (2023)

Proposed structure:
1. Test-year replication (2023) — unchanged
2. Few-shot calibration ablation — moved to **2019, 70B base only**, as part of the
   primary analysis (decided 2026-07-24: the few-shot comparators are the base model's
   primary-grid cells, and the contrast is undefined for FT models, which are zero-shot
   everywhere — so 2019/base is the only placement that needs no extra few-shot runs)
3. **Unified mechanism tests (2023)** — re-identification + name swap (new) + information shift (moved from 2024 to 2023)
4. Agreement test / Applied performance (2023) — unchanged
5. **2024 FH-only temporal holdout** — reframed and expanded from original 2024 information shift

The key conceptual upgrade: the original five checks had no explicit connection to each
other. The proposed structure makes the analytical logic explicit — each piece rules out
a different alternative explanation for the main result.

On the few shot calibration ablation test, my thinking is that there as argument that if it doesn't show anything it could go in the appendix. However, if it doesn't show anything, that could also constitute evidence that the model is ignoring the prompt and instead is relying prior activated by the country name. 

---

## The three mechanism tests (all 2023, best model)

### 1. Re-identification — characterizes identity leakage

Characterizes how much country identity leaks through each text treatment. Necessary
baseline for interpreting the name swap and information shift. Current results (2019
data, reidentification experiment):

- Top-1 accuracy: **46.9%** for summaries, **61.2%** for anonymization
- Top-3 accuracy: **54.1%** for summaries, **75.5%** for anonymization
- Countries identifiable under both treatments: 11
- Countries identifiable only from anonymized text: 6
- Countries identifiable only from summaries: 2
- Countries identifiable under neither: 4

The 46.9% figure for summaries is the critical calibration input for the name swap
(see below): roughly half the time the model can see through a name swap by recognizing
the source country from the text alone, independent of the name given.

### 2. Name swap — direct conflict test (proposed, issue #25)

Creates a controlled conflict between name prior and text content to test directly
whether names or evidence drive ratings. Setup uses transition-adjacent country-years
(where pretraining knowledge of the transition exists) paired with stable neighbors
from the same regime type (controls the Xie et al. coherence problem —
see `_literature/annotated-bibliography.md`).

**Three conditions:**

- **Condition A**: Name + codebook only — pure name/identity prior, no text
- **Condition B**: Name + correct summary — name prior confirmed by matching evidence
- **Condition C**: Name + swapped summary — name prior contradicted by mismatched evidence

**In Condition A, if name priors dominate**, the model rates Country A correctly even
without text (it knows about the transition from pretraining). The swap in Condition C
then doesn't hurt performance against the *named* country's actual panel mean — the
model ignores the mismatched text and still rates from the name prior. This is the
crucial clarification for Scenario 1: the swap is invisible to a name-prior model, so
MAE stays low regardless.

**Measuring MAE against two benchmarks simultaneously in Condition C:**
- MAE vs. the *named* country's actual panel mean
- MAE vs. the *source* country's panel mean (whose text was injected)

**What each scenario predicts:**

| Scenario | A vs. B | C vs. named mean | C vs. source mean |
|---|---|---|---|
| Name prior dominates | A ≈ B (text adds nothing) | Low (model ignores swap) | High (ratings don't track source) |
| Evidence-reading | B < A (text helps) | High (text contradicts name) | Low (ratings track source) |
| Event-pattern prior via text | B < A | High | Low — indistinguishable from evidence-reading without re-id conditioning |

**Resolving the event-pattern-prior confound using re-identification:**

The 46.9% re-identification rate for summaries means Condition C results are a mixture:
- ~47% of cases: model re-identifies source country from text → ratings track source
  country's mean (via event-pattern prior, not necessarily genuine evidence-reading)
- ~53% of cases: model does not re-identify → either anchors on named country's prior
  or reads evidence literally

Stratifying Condition C results by re-identification success isolates the mechanism.
In non-re-identified cases, if ratings still move toward the source country's panel
mean, that is the closest isolable signal of genuine evidence-reading — the model
neither recognized the source country nor anchored on the named country's prior, yet
still updated on the described conditions.

**Three-cell interpretation framework for Condition C:**

| Cell | Re-id | Interpretation |
|---|---|---|
| ~47% | Succeeds | Ratings track source mean — event-pattern prior confirmed |
| ~53% × ? | Fails, ratings track named country | Name prior dominating |
| ~53% × ? | Fails, ratings track described conditions | Genuine evidence-reading |

**Implementation notes:**
- Use indicator-specific summaries, not anonymized raw packets. Summaries describe
  *what happened* in generic political terms; anonymized packets retain institutional
  vocabulary (ministry names, legislative procedures) that fingerprints the country
  even after named-entity removal. The 14-point lower re-identification rate for
  summaries (46.9% vs 61.2%) confirms they are meaningfully less identifiable.
- Pair selection: within regime type (v2x_regime), one transition-adjacent CY and one
  stable neighbor. Within-tier matching keeps political vocabulary similar enough that
  swapped text remains fluent (Xie et al. coherence control).
- Consider a second anonymization pass on summaries before swapping to strip residual
  country-distinctive vocabulary.

### 3. Information shift — tests the positive prediction (issue #28)

Tests the positive prediction: if the model reads evidence, the gain from adding text
should be largest where pretraining knowledge is most outdated — transition-adjacent
country-years where the political situation changed substantially. This is the hardest
claim to fake with a prior-based story, because it requires the model's priors to be
selectively wrong for high-change cases.

**Why move this from 2024 to 2023?** The original design put this test on 2024 data
because the post-cutoff year maximizes prior obsolescence. Moving it to 2023 weakens
it slightly (the model may know about 2023 transitions from pretraining), but allows
it to be integrated into the unified mechanism section alongside re-identification and
the name swap. Running it on both years is an option: 2023 as part of the mechanism
tests, and the year-level version (2024 > 2023?) as part of the temporal holdout.

**Measuring regime shift: ERT vs. |Δv2x_polyarchy|**

ERT (Episodes of Regime Transformation) is a V-Dem-affiliated dataset (Boese, Edgell,
Hellmeier, Maerz, Lindberg) that identifies sustained episodes of democratic change —
both democratization and autocratization. An onset year marks when a sustained episode
begins; a peak year marks the year of maximum change within that episode. Episodes are
defined by sustained directional change of at least 0.1 in v2x_polyarchy or v2x_libdem
over the course of the episode, filtering out short-term fluctuations.

|Δv2x_polyarchy| is the year-over-year change in the polyarchy score — continuous,
captures all magnitudes, but includes noise from electoral cycles and measurement.

They measure different things:
- ERT identifies *narratively meaningful* political transitions that generate news
  coverage, appear in human rights reports, and are represented in LLM training data
  as events. Better as the binary treatment variable.
- |Δv2x_polyarchy| captures the gradient of change. Better as the continuous
  moderator for statistical power.

**Recommendation**: keep both as in the original design. ERT onset/peak as the binary
treatment (transition-adjacent vs. stable CYs); |Δv2x_polyarchy| as the continuous
moderator within that classification. The combination is more defensible than either
alone: ERT provides theoretical motivation, polyarchy change provides statistical
resolution.

Pre-registered prediction: Δ(Evidence − Codebook) is more negative (larger improvement
from evidence) in ERT-tagged transition-adjacent cases than in stable cases.

---

## The 2024 FH-only temporal holdout

### Why FH-only

The 2024 State Department Human Rights Reports changed substantially under Trump 2.0 —
not just format and length, but content: different political priorities, less coverage
of certain rights categories, different editorial mandate. This is not just a mapping
problem (remapping sections to indicators, ~half a day of work) — it's a content
problem. Even with remapped sections, a 2023 SD report written under one political
mandate and a 2024 SD report written under another are not comparable. The content
shift confounds the temporal comparison independently of the format shift.

Freedom House maintained its format and editorial independence through 2024. Using
FH-only for both 2023 and 2024 gives a clean within-source temporal comparison.
The cost is that the 2023 results in this comparison use only one source instead of
two, requiring a separate FH-only inference run for 2023. This is additional compute
but not a design problem.

The SD 2024 change is worth a footnote: it illustrates exactly the kind of
source-document instability that makes the decomposition question consequential —
if AI coding relies on source documents that are politically contingent, that is
itself a finding about the limits of the approach.

### Why it's different from the mechanism tests

The mechanism tests test evidence-reading vs. prior-reliance through *experimental
manipulation* — creating conflicts, swapping content, stratifying by transition.

The 2024 holdout tests the same question through *structural exclusion*: Llama 3.3's
training cutoff is 2023, so the model structurally cannot have parametric priors about
2024 events. Any improvement from the evidence conditions over codebook-only in 2024
is by definition coming from reading the text, not from stored knowledge. This is
arguably a stronger warrant for the evidence-reading claim than any of the mechanism
tests, and it comes essentially for free once the 2023 analysis is complete.

### What to report

- Full primary conditions (codebook, FH-evidence, anonymized, summarized) on 2024
- Same conditions run on 2023 FH-only (for clean comparison)
- Primary display: Δ(Evidence − Codebook) and Δ(Anonymized − Codebook) for 2023
  FH-only vs. 2024 FH-only — if evidence gains are larger in 2024, that is the
  year-level version of the information shift result
- Secondary: re-identification rates on 2024 summaries/anonymized text — expected to
  be lower than 2023 for post-cutoff events (model has no 2024-specific knowledge to
  draw on for re-id), which would itself be a useful data point
- Applied performance (AI MAE vs. human panel MAE) for 2024 as an out-of-sample
  generalization check

The 2024 holdout does not need its own name swap or ERT stratification — the post-
cutoff year is the manipulation. The structural exclusion of parametric priors does
what the name swap does experimentally, but more cleanly.

---

## Revised overall paper structure

| Section | Year(s) | What it tests |
|---|---|---|
| Primary analysis | 2019 | 3×5 identification experiment |
| Few-shot ablation | 2019 (70B base) | Marginal value of calibration examples |
| Test-year replication | 2023 | Do identification results generalize? |
| **Mechanism tests** | **2023** | **Re-id → name swap → info shift** |
| Agreement test | 2023 | AI MAE vs. human panel MAE |
| **2024 FH-only holdout** | **2023+2024** | **Out-of-sample, structural prior exclusion** |
