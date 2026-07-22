# Experimental Design

## Overview

The experiment addresses a central decomposition question: when large language models code
political texts, what information are they actually drawing on — pretrained political
knowledge, structured source evidence, or country identity — and how much does each source
contribute to calibration quality?

The design answers this through four prompt conditions that constitute an identification
strategy. The codebook-only condition provides no source text, measuring the baseline
calibration available from pretraining alone. The evidence condition adds raw section text
and few-shot calibration examples, isolating what structured primary source evidence
contributes over pretrained knowledge. The anonymized condition strips named entities —
country identity, named institutions and officials, datable events — from both the
evidence and the calibration examples, isolating how much country identity, rather than
described conditions, drives the ratings. The summarized condition goes further: an LLM
rewrites the assembled evidence as a generic, indicator-targeted description of political
conditions, discarding not just names but the content fingerprints (distinctive
institutional arrangements, treaty relationships, electoral structures) that survive
named-entity anonymization. A coverage-tier gradient — the evaluation indicator set spans
strong, partial, and weak source coverage — serves as a within-study moderating variable
that tests whether calibration quality degrades as source evidence weakens.

The primary design is a **4 × 4 experiment** (4 prompt conditions × 4 models) run on the
full universe of ~205 mapped Type C indicators, all eligible country-years — no indicator
sampling. The four models are Llama 3.3 70B Instruct (base) and three fine-tuned variants
of the same base model — FT-raw, FT-anon, FT-summ — trained on raw, anonymized, and
summarized evidence respectively (all 206 mapped Type C indicators, ~898K coder-CYI
training rows from V-Dem v15 2016–2018, subsampled to a shared indicator-stratified ~100K
cases per variant with early stopping; see `notes/finetuning-epochs.md`). Llama 405B and
8B, originally part of the design as a scale comparison, are not run: 405B does not fit
within GW Pegasus's available allocation (2 eight-A100 nodes cluster-wide), and 8B was
dropped to keep the design focused on information-source effects rather than an
underpowered scale comparison. No frontier-model API calls are made anywhere in the
design. Because there is a single base scale, the design carries no scale-effect claim;
the four-model comparison is entirely about what each information-source treatment and its
embedded (fine-tuned) analog contribute.

Beyond the primary 2019 analysis, robustness and validation work runs on 2023 and 2024
data using the best-performing model from the primary analysis. A test-year replication
reruns all four conditions on 2023 data. A few-shot calibration ablation reruns the
evidence, anonymized, and summarized conditions without calibration examples. A unified
mechanism-test section combines three pieces on 2023 data — re-identification, a name-swap
test, and an information-shift test — that each rule out a different alternative
explanation for the main result. An agreement test compares AI MAE to the average
deviation of individual human coders from the same panel mean. A 2024 Freedom-House-only
temporal holdout reruns all four conditions on data entirely outside the model's
pretraining cutoff, giving a structural test of evidence-reading versus prior-reliance.
Thin-panel augmentation (k=1 addition to panels ≤8 coders) is reported as an exploratory
illustration in the appendix.

## Part 1: Identification experiment

### Conditions

| Label | Prompt content | Models | New element |
|---|---|---|---|
| Codebook-only | Global framing + codebook text | All | — |
| Evidence | + raw section text + calibration examples | All | Source evidence + calibration anchors |
| Anonymized | + anonymized section text + anonymized calibration examples | All | Country-identity stripped |
| Summarized | + summarized section text + summarized calibration examples | All | Content fingerprints stripped, not just names |
| Evidence, no calibration examples | + raw section text only | Best model | Evidence without anchors |
| Anonymized, no calibration examples | + anonymized section text only | Best model | Anonymization without anchors |
| Summarized, no calibration examples | + summarized section text only | Best model | Summarization without anchors |

The first four conditions are additive: Evidence adds source text and calibration examples
to Codebook-only; Anonymized strips named entities from both the focal evidence and the
calibration examples; Summarized replaces the evidence and calibration examples with
LLM-generated generic descriptions, stripping content fingerprints that survive
named-entity anonymization. The no-calibration-examples conditions repeat the evidence,
anonymization, and summarization manipulations without the calibration block, allowing a
direct read on how much of the observed improvement comes from the source text versus the
few-shot anchors. These three conditions run on the best-performing model only, on
**2023 data**, as part of the robustness section — not the primary 2019 analysis. See the
Few-shot calibration ablation section below.

### Models

| Model | Scale | Platform | Conditions |
|---|---|---|---|
| Llama 3.3 70B Instruct | 70B open | GW GH200 (preferred) or A100 80GB | Codebook, Evidence, Anonymized, Summarized |
| Llama 3.3 70B Instruct (FT-raw) | 70B ft | GW GH200 (preferred) or A100 80GB | All 4 conditions; no calibration block; trained on raw evidence |
| Llama 3.3 70B Instruct (FT-anon) | 70B ft | GW GH200 (preferred) or A100 80GB | All 4 conditions; no calibration block; trained on anonymized evidence |
| Llama 3.3 70B Instruct (FT-summ) | 70B ft | GW GH200 (preferred) or A100 80GB | All 4 conditions; no calibration block; trained on summarized evidence |

**Llama 405B and 8B were dropped from the design.** 405B requires 8×A100 80GB GPUs and
approximately 810 GB of scratch storage; GW Pegasus has only 2 eight-A100 nodes
cluster-wide, insufficient to run three full-universe conditions within a reasonable
number of job submissions. Llama 3.1 8B was dropped to keep the design focused on
information-source effects: with only 70B remaining as a base scale, retaining a single
smaller model would add an underpowered, uninterpretable one-point scale comparison rather
than a genuine scale gradient. No frontier-model API calls (e.g., Claude, GPT) are made
anywhere in the design. An early two-condition (codebook, evidence) smoke test on Llama 8B
validated pipeline mechanics only; its output was never analyzed and is not part of the
confirmatory results. Because 405B and 8B are dropped outright rather than contingently
included, there is no indicator-sampling fallback tied to their availability (see
Evaluation set, below) — the full ~205-indicator universe is run unconditionally.

All three fine-tuned variants participate in all four primary conditions with the same
codebook, evidence, anonymization, and summarization structure as the base model, but
without a calibration block — calibration is embedded in the adapter weights rather than
supplied via examples in the prompt. **FT-raw** is trained on raw evidence text;
**FT-anon** on anonymized evidence text; **FT-summ** on summarized evidence text. All
three are trained on all 206 mapped Type C indicators from 2016–2018 (~898K coder-CYI
rows total, subsampled to a shared indicator-stratified ~100K cases per variant with early
stopping on held-out validation loss; see `notes/finetuning-epochs.md`). The key
comparisons: FT-raw vs. base 70B isolates what fine-tuning adds over few-shot calibration;
FT-anon vs. FT-raw and FT-summ vs. FT-raw show whether anonymizing or summarizing the
training data changes calibration independently of the corresponding manipulation at
inference; FT-anon vs. FT-summ shows whether the stronger de-identification of
summarization changes what fine-tuning learns.

As of pre-registration, no inference has been run on any fine-tuned model. One full
training run per variant was completed and then discarded upon discovery of a defective
internal train/eval split, without any inference or evaluation of the resulting adapters
(see Pilot work disclosure); the training script now splits its internal validation set
by country-year-indicator cell (`notes/finetune-validation-split-leakage.md`), and all
three variants are being retrained from scratch under the corrected split.
Anonymization and summarization of the 2016–2018 training window and the 2019/2023
evaluation pools are complete.

### Country-year pool (calibration)

Primary: **2019** (~150–170 country-year-indicator cells per indicator with v15 raw panel
means). 2019 is the clean one-year temporal holdout after the fine-tuning training window
(2016–2018) with full panels and no exogenous anomalies. 2020 is avoided as a primary
test year: COVID-19 emergency restrictions systematically distort civil society, judicial,
and media indicators, making the human panel mean itself a noisier target.

Robustness check: **2023** — best-performing model only. Falls outside the 2016–2018
training window; the last year of intact SD and Freedom House reporting before the 2024
format restructuring. Source documents already ingested and confirmed clean. Panel sizes
by 2023 are smaller on average due to continued post-2013 attrition, making this a harder
test of the replacement scenario.

Structural holdout: **2024, Freedom House only** — best-performing model only. Falls
entirely outside Llama 3.3's pretraining cutoff (2023), so any calibration gain from
evidence is attributable to reading the text rather than stored knowledge. Freedom House
only, because the 2024 State Department reports changed substantially in content and
editorial mandate under a new administration, confounding a clean temporal comparison;
Freedom House maintained format and editorial continuity through 2024. See Part 2,
"2024 Freedom-House-only temporal holdout."

### Outcome

**AI MAE**: `|AI_rating − panel_mean|` per CYI, bootstrapped at the CYI level (B=500). This is the primary metric for both the identification claims (comparing AI MAE across prompt conditions) and the substitution check in the robustness section (comparing AI MAE against the average human coder's deviation from the same panel mean). Because the panel mean is a fixed reference shared by all models, the model with the lowest AI MAE is also the model that performs best on the substitution check. An alternative — averaging the AI's absolute deviation from each individual coder — is always ≥ AI MAE by Jensen's inequality; the gap equals within-panel disagreement. That alternative conflates AI error with normal human variance and is uninterpretable across indicators with different panel dispersion. The LOO framework (used for the human benchmark, not the AI metric) is the principled operationalization of comparing the AI to individual coders. See `notes/evaluation-metrics.md`.

Primary display is a **coefficient plot** (Figure 1): rows = condition × model combinations, x-axis = aggregate AI MAE. The identification claims are reported as a **delta coefficient plot** (Figure 2): four panels showing Δ(Evidence − Codebook), Δ(Anonymized − Codebook), Δ(Anonymized − Evidence), and Δ(Summarized − Anonymized), with rows = models and a reference line at 0. Negative values indicate the added element improved calibration. Δ(Anonymized − Codebook) is the primary identification result: it shows that the information gain from source evidence holds even when country identity is stripped, ruling out anchoring bias as the source of apparent calibration. Δ(Anonymized − Evidence) shows the additional gain from removing country identity from text that already provides source evidence. Δ(Summarized − Anonymized) shows whether stripping residual content fingerprints — beyond named entities — yields a further calibration gain, or instead costs calibration by discarding evaluatively relevant specificity.

Supplementary display: a module-level summary table (indicators grouped by V-Dem module, coverage tier noted) reporting condition × model AI MAE. Secondary: signed deviation by democracy quintile.

### Significance of each comparison

| Comparison | Isolates |
|---|---|
| Codebook vs. Evidence (same model) | Combined value of source evidence and calibration examples |
| Codebook vs. Anonymized (same model) | Combined value of anonymized evidence and calibration examples |
| Codebook vs. Summarized (same model) | Combined value of summarized evidence and calibration examples |
| Evidence vs. Anonymized (same model) | Marginal cost of exposing country identity in the evidence |
| Anonymized vs. Summarized (same model) | Marginal cost of residual content fingerprints beyond named entities |
| Evidence vs. Evidence, no calibration examples (best model) | Marginal value of the few-shot calibration block |
| Anonymized vs. Anonymized, no calibration examples (best model) | Marginal value of calibration examples under anonymization |
| Summarized vs. Summarized, no calibration examples (best model) | Marginal value of calibration examples under summarization |
| Anonymized (70B base) vs. FT-anon; Summarized (70B base) vs. FT-summ | Marginal value of embedding calibration in model weights vs. prompt |
| Quintile signed deviation | Regime-type anchoring bias |

## Part 2: Robustness and validation analyses

Robustness and validation analyses use the best-performing model from the primary 2019
analysis (of the four: 70B base, FT-raw, FT-anon, FT-summ). Four analyses run on 2023
data; a fifth reruns all four primary conditions on 2024 Freedom-House-only data as a
structural holdout. The analytical logic is explicit: test-year replication and the
few-shot ablation retest generalization and prompt-structure sensitivity; the
mechanism-test section and the 2024 holdout each rule out the same alternative explanation
— model priors rather than evidence-reading — for the main identification result, one
experimentally and one structurally.

### Test-year replication (2023)

The winning model from the primary analysis is re-run on 2023 data under all four primary
conditions. The delta estimates from Figure 2 — Δ(Evidence − Codebook), Δ(Anonymized −
Codebook), Δ(Anonymized − Evidence), and Δ(Summarized − Anonymized) — are recomputed for
2023 and compared to the 2019 estimates. If the identification results replicate in
direction and magnitude, the decomposition generalizes beyond the primary test year. Source
documents for 2023 are already ingested and confirmed clean (issue #14, closed 2026-07-12).

### Few-shot calibration ablation (2023)

The evidence, anonymized, and summarized conditions all include a few-shot calibration
block — five examples spanning the 0–4 scale — alongside the source evidence. This
ablation isolates what those examples contribute over the source evidence alone.

The best-performing model from the primary 4×4 analysis is re-run on **2023 data** under
three additional conditions: evidence, anonymized, and summarized text, each without
calibration examples. Source documents for 2023 are already ingested and confirmed clean,
so no additional ingestion is required.

| Comparison | What it isolates |
|---|---|
| Evidence (zero-shot) vs. Codebook-only | Model reads the text even without calibration anchors |
| Evidence (few-shot) vs. Evidence (zero-shot) | Marginal contribution of calibration examples given named evidence |
| Anonymized (zero-shot) vs. Codebook-only | Text still helps without country identity or calibration anchors |
| Anonymized (few-shot) vs. Anonymized (zero-shot) | Marginal contribution of calibration examples when country identity is also stripped |
| Summarized (zero-shot) vs. Codebook-only | Text still helps without content fingerprints or calibration anchors |
| Summarized (few-shot) vs. Summarized (zero-shot) | Marginal contribution of calibration examples when content fingerprints are also stripped |

The key prediction follows from the anchoring mechanism: in the evidence condition the
model has two scale anchors — the few-shot examples and country-identity priors activated
by the named country. Under anonymization and, more so, under summarization, those anchors
are progressively removed, so the model should rely more heavily on the calibration
examples to map described conditions onto the 0–4 scale. The predicted signature is that
the few-shot vs. zero-shot gap **grows from evidence to anonymized to summarized**. See
hypothesis 7. A null result under all three conditions is itself informative here: it would
suggest the model is not using the calibration examples — and possibly not the prompt
content generally — a signal worth flagging directly rather than filing quietly in the
appendix (see `notes/mechanism-test-design.md`).

**Figure**: coefficient plot with three panels — Δ(few-shot − zero-shot) for the evidence
condition (Panel A), the anonymized condition (Panel B), and the summarized condition
(Panel C) — each showing bootstrapped CIs around the AI MAE difference. Reference line at
0; negative values indicate few-shot improves on zero-shot.

### Mechanism tests (2023)

Three pieces, run together on 2023 data with the best-performing model, address the same
underlying question through different manipulations: does the calibration gain from the
evidence conditions come from the model reading the text, or from routing through
country-identity priors activated by surface cues? Each piece rules out a different
alternative explanation. See `notes/mechanism-test-design.md` for the full design
discussion (issues #25, #26, #28).

#### 1. Re-identification

Characterizes how much country identity leaks through the anonymized and summarized text
treatments — the necessary baseline for interpreting the name-swap test. After each
anonymized or summarized coding call, a follow-up message is sent with the full
conversation as context: *"Based only on the political conditions described in the text
you just reviewed, what are your top three guesses for which country this describes? List
them in order of confidence and briefly note the cue that led to each."* The rating from
the first call is already locked before the follow-up is sent, so the identification
prompt cannot contaminate the rating.

**Metrics**: top-1 accuracy (first guess correct) and top-3 accuracy (correct country
appears in any of the three guesses), bootstrapped at the CYI level (B=500), reported for
both the anonymized and summarized treatments. The primary diagnostic is the signed
deviation (AI rating − panel mean) for correctly re-identified versus non-re-identified
cases, under each treatment. If correctly re-identified cases show larger directional bias
— rated too high for autocracies, too low for democracies — this confirms that residual
identity leakage is a mechanism behind any remaining compression.

**Figures**:
- *Accuracy*: coefficient plot, rows = regime type (Panel A) and region (Panel B), x-axis =
  re-identification accuracy, one series per treatment (anonymized, summarized), vertical
  reference line at overall accuracy.
- *Signed deviation*: same two-panel structure, x-axis = mean signed deviation by
  re-identified vs. not, reference line at 0.

#### 2. Name swap

Creates a controlled conflict between a country-name prior and text content to test
directly whether names or evidence drive ratings. Pairs a transition-adjacent country-year
with a stable neighbor of the same regime type (v2x_regime), using summarized text
(indicator-targeted summaries carry less residual institutional vocabulary than anonymized
packets, per the re-identification results above).

**Three conditions**: (A) Name + codebook only — pure name/identity prior, no text; (B)
Name + correct summary — name prior confirmed by matching evidence; (C) Name + swapped
summary — name prior contradicted by mismatched evidence (the named country's actual
summary is replaced with the paired country's summary).

**Predictions**: if name priors dominate, A ≈ B (text adds nothing) and Condition C's
rating stays close to the *named* country's actual panel mean (the swap is invisible to a
name-anchored model). If the model reads evidence, B < A (text helps) and Condition C's
rating tracks the *source* country's panel mean instead. MAE is computed against both
benchmarks simultaneously in Condition C to distinguish these. Because summaries still
carry some residual identifiability (see re-identification above), Condition C results are
stratified by whether the model separately re-identifies the source country: in
non-re-identified cases, a rating that still moves toward the source country's mean is the
most isolable signal of genuine evidence-reading, since the model neither recognized the
source country nor anchored on the named country's prior.

**Figure**: coefficient plot, rows = {A vs. B, C vs. named mean, C vs. source mean},
stratified by re-identification status, reference line at 0 (for deviation) or at the
between-condition difference.

#### 3. Information shift

Tests the positive prediction directly: if the model reads evidence, the calibration gain
from adding text should be largest where pretraining knowledge is most outdated —
country-years where political conditions changed substantially. Country-years in the 2023
evaluation pool are tagged as transition-adjacent using the V-Dem Episodes of Regime
Transformation (ERT) dataset (onset or peak year flag); the continuous moderator is
|Δv2x_polyarchy| from year t−1 to t. AI MAE is computed separately for transition-adjacent
and stable country-years under each condition. Pre-registered hypothesis: Δ(Evidence −
Codebook) is more negative — the gain from adding evidence is larger — in
transition-adjacent country-years than in stable ones.

**Figure**: coefficient plot with two panels — Δ(Evidence − Codebook) and
Δ(Anonymized − Codebook) — each showing three dots with bootstrapped CIs: all
country-years, stable, and transition-adjacent. Reference line at 0.

### Applied performance

### Agreement test (2023)

The best-performing model from the primary 2019 analysis is evaluated on 2023 data by
comparing its AI MAE against the human panel MAE — the average deviation of individual
human coders from the same panel mean. Both are computed against the full panel mean for
each CYI. If AI MAE is at or below the human panel MAE, the AI deviates from the panel
consensus by no more than a typical human coder. This is reported for all four primary
conditions to show whether the result holds across the full prompt design, not only under
the best condition.

### 2024 Freedom-House-only temporal holdout

The mechanism tests above rule out prior-reliance through experimental manipulation. The
2024 holdout tests the same question through structural exclusion: Llama 3.3's pretraining
cutoff is 2023, so the model cannot hold parametric priors about 2024 events. Any
improvement from the evidence conditions over codebook-only in 2024 is, by construction,
coming from reading the text rather than stored knowledge — arguably a stronger warrant
for the evidence-reading claim than any experimental mechanism test, and it comes largely
for free once the 2023 analysis is complete.

**Why Freedom House only**: the 2024 State Department Human Rights Reports changed
substantially in content and editorial mandate under a new administration, not just
format — a 2023 SD report and a 2024 SD report are not a clean content comparison
independent of that shift. Freedom House maintained format and editorial continuity
through 2024. The comparison year (2023) is rerun Freedom-House-only for a clean
within-source match; this requires a separate FH-only inference pass for 2023 in addition
to the two-source 2023 run used elsewhere in Part 2.

**What is reported**: all four primary conditions on 2024 FH-only data, and on 2023 FH-only
data for comparison. Primary display: Δ(Evidence − Codebook) and Δ(Anonymized − Codebook)
for 2023 FH-only vs. 2024 FH-only — a larger evidence gain in 2024 is the year-level
version of the information-shift result. Secondary: re-identification rates on 2024
anonymized/summarized text (expected to be lower than 2023, since the model has no
2024-specific knowledge to draw on for re-identification cues). Applied performance (AI MAE
vs. human panel MAE) is also reported for 2024 as an out-of-sample generalization check.
The 2024 holdout does not need its own name-swap or ERT stratification — the post-cutoff
year is itself the manipulation.

## Part 3: Exploratory and sensitivity analyses

### Thin-panel augmentation (exploratory / appendix)

For each country-year in the 2023 evaluation pool with ≤8 distinct coders, add one AI
rating from the best-calibrated model and compare the AI-augmented panel mean to the
human-only panel mean.

```
divergence = |mean(human_panel + AI_rating) − mean(human_panel)|
```

Bootstrap across country-years (B=500). Report mean divergence with 95% CI. 2023 is the
natural year for this test: panel sizes have thinned substantially relative to 2019 due to
continued post-2013 attrition, making thin panels the norm rather than the exception.
k=1 is the only registered scenario. Reported as an applied illustration; motivates the
substitution experiment in `notes/substitution-experiment-future-paper.md`.

### Coverage-tier moderation and evidence transfer (exploratory / appendix)

The full evaluation set spans three source-coverage tiers (strong, partial, weak). A
pre-registered question (hypothesis 6) is whether AI MAE is higher for weak-coverage
indicators than for strong-coverage ones. A sharper unregistered question sits inside it:
for indicators with no directly relevant section in either source document, does the
evidence packet provide *any* calibration benefit over codebook-only, or is source text
only useful when it directly addresses the indicator?

Of the 206 indicators in `config/indicator_sections.yaml`:
- **3 indicators** have no section mapping in either source (`v2dlcommon`, `v2dlcountr`,
  `v2exl_legitlead`) — they receive the executive summary alone as their evidence packet.
- **26 indicators** have no State Dept section but do have a Freedom House section —
  they receive FH text plus the SD executive summary.
- The remaining indicators have at least one direct section in each source.

The question is whether Δ(Evidence − Codebook) < 0 for the no-direct-section group. If
the executive summary alone (general political context, not indicator-specific text)
still reduces deviation from the panel mean, the model is transferring general political
knowledge encoded in the source document to a specific coding task — a form of
cross-indicator transfer. If the gap is near zero or positive, the evidence benefit
requires direct section relevance and does not generalize to unmapped indicators.

This is unregistered and exploratory: it runs on the same output already generated for
the main analysis, requires no additional inference, and is reported as a post-hoc
decomposition of the coverage-tier gradient rather than a primary finding.

**Analysis**: compute Δ(Evidence − Codebook) AI MAE separately for three groups —
no-section indicators (exec summary only), single-source indicators (FH only), and
dual-source indicators (both SD and FH sections). Compare group means with bootstrapped
CIs. **Figure**: coefficient plot with three rows (one per mapping tier), x-axis =
Δ(Evidence − Codebook), reference line at 0.

### IRT-corrected reference check (exploratory / appendix)

V-Dem's primary measurement outputs are IRT-derived rather than raw panel averages. For
each indicator and country-year, V-Dem publishes an ordinal transformation (`_ord`) —
the posterior modal category from the Bayesian IRT model, which corrects for coder-level
reliability differences and threshold idiosyncrasies before aggregating across the panel.
The `_ord` score and the raw panel mean are derived from the same underlying coder ratings
but differ wherever IRT corrections are non-trivial: most commonly when coders are
regionally immersed and systematically shift the autocratic floor upward, or when a panel
contains outlier coders whose ratings receive low reliability weights.

This analysis computes AI MAE against `_ord` as a secondary reference target alongside
the primary `panel_mean` metric, on **2023 data** using all four models. Two questions
motivate the comparison:

**Weidman comparability.** Weidman et al. (2025) evaluate zero-shot GPT-4o and
Llama-3.1 70B against `_ord` for 2023. Reporting AI MAE against `_ord` on the same year
allows direct positioning relative to their findings: specifically, how much does
fine-tuning and structured source evidence reduce the deviation from the IRT-corrected
consensus that Weidman document for zero-shot models?

**Finetuning bias diagnostic.** If finetuning on individual coder ratings embeds the
regional threshold biases present in those ratings, the finetuned models (FT-raw, FT-anon,
FT-summ) should show a characteristic asymmetry: lower AI MAE against `panel_mean` than base models
(the finetuning target), but not necessarily lower AI MAE against `_ord` (the IRT-corrected
target). A gap between the two reference targets — `|FT − panel_mean|` vs.
`|FT − _ord|` — that is larger for the finetuned models than for the base models would
indicate that finetuning absorbs the systematic biases embedded in raw coder ratings rather
than converging on the IRT-corrected consensus.

This analysis requires no new inference — it runs on the same 2023 output already
generated for the Agreement test. Implementation requires adding the `_ord` column from
V-Dem v15 to the panel-means lookup and computing a second MAE column in
`pipeline/substitution_eval.py`.

**Display**: a supplementary table reporting, for each model × condition, both
`|AI − panel_mean|` and `|AI − _ord|` side by side on 2023 data. A brief narrative in
the appendix notes the comparison to Weidman et al. and flags whether the finetuning
asymmetry is present.

### Persona variation and temperature sensitivity (feasibility checks for future work)

These are not registered analyses for the current paper. Persona variation (strict vs.
lenient framing) and temperature sampling (draws at temperature > 0) are run as
post-hoc illustrations after the main results are in. Their purpose is to establish
whether the AI produces meaningfully distinct ratings under different framings — a
prerequisite for the substitution experiment planned as a follow-on paper (see
`notes/substitution-experiment-future-paper.md`). Results are reported as supplementary
diagnostics, not findings of the current paper.

## Outcome variables

| Variable | Definition | Role |
|---|---|---|
| AI MAE | `mean(\|AI_rating − panel_mean\|)` per CYI, bootstrap CIs | Calibration primary |
| Human panel MAE | `mean(\|rating_i − panel_mean\|)` averaged across coders per CYI | Substitution benchmark (robustness) |
| Δ(Evidence − Codebook) MAE | `AI MAE_evidence − AI MAE_codebook`, per model, bootstrap CIs | Identification claim 1: value of source evidence |
| Δ(Anonymized − Codebook) MAE | `AI MAE_anon − AI MAE_codebook`, per model, bootstrap CIs | Identification claim 2: clean information gain free of country-identity anchoring |
| Δ(Anonymized − Evidence) MAE | `AI MAE_anon − AI MAE_evidence`, per model, bootstrap CIs | Identification claim 3: cost of exposing country identity |
| Δ(Summarized − Anonymized) MAE | `AI MAE_summ − AI MAE_anon`, per model, bootstrap CIs | Hypothesis 8: cost/benefit of stripping residual content fingerprints |
| Exact match rate | `% (AI_rating == round(panel_mean))` | Calibration secondary |
| Adjacent agreement | `% (\|AI_rating − round(panel_mean)\| ≤ 1)` | Calibration secondary |
| Signed deviation by quintile | `mean(AI_rating − panel_mean)` by v2x_polyarchy quintile | Compression diagnostic |
| Top-1 re-identification accuracy | `% (first country guess == true country)`, bootstrap CIs, by regime type and region, by treatment (anonymized, summarized) | De-identification integrity |
| Top-3 re-identification accuracy | `% (true country in top 3 guesses)`, bootstrap CIs, by regime type and region, by treatment | De-identification integrity |
| Signed deviation by re-identification | `mean(AI_rating − panel_mean)` for re-identified vs. not, by regime type, by treatment | Anchoring mechanism test |
| Name-swap MAE (vs. named / source mean) | `\|AI_rating − panel_mean\|` against both benchmarks in the swapped condition, stratified by re-identification status | Mechanism test: evidence-reading vs. prior-reliance |
| divergence_k | `\|mean_aug_k − mean_full\|` | Replacement check |
| Augmentation gain | `\|mean_aug_k − mean_ref\| < \|mean_thin − mean_ref\|`? | Panel augmentation |

AI MAE against the raw panel mean is the primary metric. Bootstrap resampling at the CYI level (B=500) yields confidence intervals and a paired significance test for each delta metric. The human panel MAE — the average deviation of individual human coders from the same panel mean — serves as the substitution benchmark in the robustness section; because the panel mean is a fixed reference, model selection on AI MAE is equivalent to selection on the substitution criterion. Formal paired difference tests are reported in the appendix; the main figures communicate the same comparisons visually. Supplementary display: a module-level summary table (indicators grouped by V-Dem module, coverage tier noted) reporting AI MAE by condition and model. See `notes/evaluation-metrics.md` for full rationale.

## Indicators

### Training set (206 indicators)

All mapped Type C indicators from V-Dem v15, 2016–2018 — all coverage tiers included.
Full list: `initial-exploration/explore-indicators/02-indicator-selection.html`.

### Evaluation set (~205 indicators)

The full universe of all mapped Type C indicators in `config/indicator_sections.yaml`
(~205 total), all eligible country-years — no indicator sampling. Same set for all four
models — a prerequisite for clean cross-model comparison. Spans all three coverage tiers,
preserving the tier-gradient as a within-study moderating variable. Section mapping
complete per issue #1 (closed 2026-07-11). Few-shot examples locked
(`data/fewshot_examples.json`, `data/fewshot_examples_anonymized.json`,
`data/fewshot_examples_summarized.json`; issue #8).

**No fallback sampling.** The proportional-stratified-sample fallback originally
pre-registered as a contingency for Llama 405B failing to complete within 3 job
submissions no longer applies: 405B is dropped from the design outright (see Models,
above), not contingently included, so there is no compute-availability trigger left to key
a fallback to. The full ~205-indicator universe runs unconditionally, at roughly ~32,800
CYI cells per condition per model per year. See `notes/evaluation-indicator-scope.md` for
the retired rationale.

Expect AI MAE to vary with observability tier and coverage tier. Report calibration
results by both dimensions.

## Pre-registration

The following hypotheses, sample decisions, and analysis choices are locked before any
LLM calls are made or v15 coder-level data is accessed for the evaluation pool. Model
weights, fine-tuning hyperparameters, and adapter checkpoint identifiers are recorded in
the replication package rather than here.

### Hypotheses

The three identification comparisons yield directional predictions:

1. **Evidence improves on codebook-only** (Δ(Evidence − Codebook) < 0): providing source
   text and calibration examples reduces deviation from the human panel mean relative to
   codebook text alone.

2. **Anonymization improves on raw evidence** (Δ(Anonymized − Evidence) < 0): stripping
   named entities from both the evidence and calibration examples reduces deviation
   further, reflecting the cost of named-entity anchoring in the evidence condition.

3. **Clean information gain is independent of named-entity anchoring**
   (Δ(Anonymized − Codebook) < 0): the gain from anonymized evidence over codebook-only
   holds even without named entities, establishing that the model is reading and using the
   source text rather than relying on pretrained knowledge of the country.

4. **Evidence matters more in transition-adjacent country-years**: Δ(Evidence − Codebook)
   is more negative for country-years tagged as transition-adjacent (ERT onset or peak
   year) than for stable country-years, reflecting that source evidence contributes most
   when stored knowledge of the country is most outdated. Tested on 2023 data as part of
   the mechanism-test section; replicated at the year level via the 2023-vs-2024
   Freedom-House-only comparison in the temporal holdout.

5. **Re-identification predicts bias**: in the anonymized and summarized conditions, cases
   where the model correctly identifies the country show larger directional deviation from
   the panel mean — positive for autocracies, negative for democracies — consistent with
   anchoring on a known country prior.

6. **Calibration degrades with weaker source coverage**: AI MAE is higher for weak-coverage
   indicators than for strong-coverage indicators, across all conditions and models.

7. **Few-shot calibration contributes more as identity cues are removed**: the improvement
   from adding calibration examples — Δ(few-shot − zero-shot) AI MAE — grows from the
   evidence condition, to anonymized, to summarized. When country identity or content
   fingerprints are present, the model can use them as a secondary scale anchor, reducing
   its dependence on the few-shot examples; as those anchors are progressively stripped,
   the calibration examples carry more of the scaling burden.

8. **Summarization strips residual anchoring without large calibration cost**
   (Δ(Summarized − Anonymized) not substantially positive): summarization achieves
   materially lower re-identification than anonymization (pre-registered target: top-1
   re-identification below 30% for summarized text, vs. ~51–61% for anonymized text,
   consistent with the 98-CYI pilot) without a large offsetting increase in AI MAE. A
   materially positive Δ(Summarized − Anonymized) would indicate that the abstraction loss
   from summarization costs more evaluative specificity than the de-identification gain is
   worth.

9. **Name-swap ratings track described conditions, not the named country**: in the
   name-swap test's swapped condition (Condition C), among cases where the model does not
   independently re-identify the source country, AI ratings move toward the source
   country's panel mean rather than staying anchored to the named country's panel mean —
   the mechanism-test signature of genuine evidence-reading rather than prior-reliance.

### Evaluation sample

- **Primary year**: 2019. All country-year-indicator cells with a raw panel mean in V-Dem
  v15 and a processed source document in both State Department and Freedom House archives.
- **Minimum coders**: none for the primary evaluation pool — any CYI with a raw panel
  mean (n_coders ≥ 1) and a processed source document in both archives is included.
  Empirically inconsequential either way: cells below 3 coders are 0.17% of the 2019 pool
  and 0.78% of the 2023 pool (22 and 42 cells respectively have exactly 1 coder). A floor
  of n_coders ≥ 2 applies only to the agreement test's human LOO benchmark, which is
  mathematically undefined at n=1 (removing the sole coder leaves nothing to average
  against); those same ~0.1% of cells are excluded from that one supplementary analysis
  only, not from the primary pool.
- **Robustness year**: 2023, best-performing model only. Source documents confirmed clean
  (issue #14, closed 2026-07-12).
- **Structural holdout year**: 2024, Freedom House only, best-performing model only.
  Requires a Freedom-House-only 2023 companion run for a clean within-source comparison.
- **k=1 replacement pool**: country-years in the 2019 evaluation pool with ≥8 distinct
  coders. No sampling cap.

### Primary outcomes

AI MAE against the raw panel mean is the primary metric throughout. The four delta
metrics — Δ(Evidence − Codebook), Δ(Anonymized − Codebook), Δ(Anonymized − Evidence), and
Δ(Summarized − Anonymized) — are the direct tests of hypotheses 1–3 and 8. All are
bootstrapped at the CYI level (B=500, CI = 2.5–97.5%). Signed deviation by v2x_polyarchy
quintile is the compression diagnostic. Exact match rate and adjacent agreement are
secondary calibration summaries.

### Modeling choices locked before running

- **Fine-tuning window**: 2016–2018. Rationale: source documents reliably available from
  2016; no overlap with 2019 test year or 2023 robustness year; captures the post-Arab
  Spring democratic backsliding period.
- **Training subsample**: each fine-tuning variant (FT-raw, FT-anon, FT-summ) trains on a
  shared, indicator-stratified ~100K-case subsample of the ~898K-row pool, with early
  stopping on held-out validation loss and epoch extension over the same pool rather than
  a fixed epoch count. See `notes/finetuning-epochs.md`.
- **No-calibration-example conditions**: run only after the best-performing model is
  identified from the primary 4×4 results, on 2023 data as part of the robustness section.
  Uses the identical prompt structure as the evidence, anonymized, and summarized
  conditions minus the calibration block. Not part of the primary 2019 analysis.
- **Anonymization**: system prompt for the anonymization agent locked before any anonymized
  condition runs; applied identically to focal evidence and calibration examples.
- **Summarization**: system prompt for the summarizer agent locked before any summarized
  condition runs; indicator-targeted (not generic) summarization, ~300–400 words, applied
  identically to focal evidence and calibration examples. Exec_summary is included in the
  evidence packet only as a fallback when no body sections are mapped for a source — never
  alongside present body sections — across the raw, anonymized, and summarized conditions
  alike (see `notes/exec-summary-policy-and-summarization-condition.md`).
- **Model scope**: Llama 405B and 8B are dropped outright, not contingently included —
  405B does not fit GW Pegasus's allocation, and 8B was dropped to avoid an underpowered
  one-point scale comparison. No frontier-model API calls are made. Because these are
  fixed exclusions rather than contingencies, there is no fallback trigger tied to model
  availability.
- **Minimum coders**: no floor for the primary evaluation pool; n_coders ≥ 2 required only
  for the agreement test's human LOO benchmark (a computability constraint, not a design
  choice — see Evaluation sample, above).
- **Divergence threshold for the k=1 replacement check**: set empirically rather than as
  an arbitrary fixed number. Using only the 2023 human-only panel data (the same ≤8-coder
  pool used for augmentation), compute the one-coder swing
  `|mean(full panel) − mean(panel \ coder i)|` for every coder i in every CYI in that
  pool — the human-only analog of adding one AI rating. The threshold is the **90th
  percentile** of that empirical distribution: the AI-augmentation divergence must exceed
  what all but the most extreme 10% of ordinary single-human-coder swaps produce before
  the k=1 result counts as exceeding normal replacement tolerance. Computed once from
  human data alone, before any AI ratings are examined. "Exceeded" is defined as the 95%
  CI **lower bound** of the AI-augmentation divergence clearing this threshold, not just
  the point estimate.
- **Name-swap pairing rule**: mandatory exact match on regime type (`v2x_regime`) and
  region; within the matched bucket, nearest-neighbor match on the transitioning country's
  *pre-transition* `v2x_polyarchy` level; ties broken by a fixed random seed; one-to-one
  matching without replacement, so no stable country-year is used in more than one pair.
  Fallback order if a bucket has no eligible candidate, fixed here before any pairs are
  drawn: (1) relax region — search globally within the same regime type; (2) if still
  empty, relax to the adjacent regime-type category within the original region.

### Robustness analyses locked before running

- **Information shift**: ERT onset/peak year flag is the primary transition-adjacent
  indicator; |Δv2x_polyarchy| is the continuous moderator. Threshold for the continuous
  moderator fixed before running. Applied to 2023 data as part of the mechanism-test
  section; replicated at the year level via the 2023-vs-2024 FH-only comparison.
- **Re-identification**: follow-up prompt text locked before the 2023 anonymized and
  summarized condition runs. Top-1 accuracy: first guess matches true country. Top-3
  accuracy: true country appears in any of the three guesses. Signed deviation by
  re-identification status is pre-specified as the primary mechanism test (hypothesis 5),
  reported separately for the anonymized and summarized treatments.
- **Name swap**: pairing procedure (transition-adjacent country-year matched with a
  stable, same-regime-type neighbor), the three-condition prompt structure (A/B/C), and
  the benchmark-comparison rule (MAE vs. named-country mean and vs. source-country mean in
  Condition C, stratified by re-identification status) are locked before running (see
  hypothesis 9 and `notes/mechanism-test-design.md`).
- **2024 Freedom-House-only holdout**: FH-only 2023 companion run and FH-only 2024 run,
  both under all four primary conditions, best-performing model only. No name-swap or ERT
  stratification is run on 2024 data — the post-cutoff year is the manipulation.

### Pilot work disclosure

A small number of design decisions in this pre-registration were informed by preliminary,
non-confirmatory pilot runs, disclosed here for transparency:

- A 98-CYI sample (2019 data) was used to compare re-identification rates with and without
  executive-summary text included in the evidence packet, motivating the
  exec-summary-fallback-only assembly policy and the decision to add the summarized
  condition (`notes/exec-summary-policy-and-summarization-condition.md`,
  `pipeline/run_reid_no_exec.py`). This sample is small relative to the ~32,800-CYI
  confirmatory 2019 evaluation pool (~0.3%). [ ] Confirm before running whether these 98
  CYIs are excluded from, or flagged as non-independent within, the confirmatory 2019
  analysis.
- An unanalyzed two-condition (codebook, evidence) smoke test on Llama 8B validated output
  schema and pipeline mechanics only. No metric was computed from it and it played no role
  in any design decision; it is not part of the confirmatory results, and Llama 8B is not
  otherwise part of the design (see Models, above).
- One full fine-tuning run per variant (FT-raw, FT-anon, FT-summ; SLURM jobs
  73473530–73473532, July 2026) was completed and then discarded upon discovery that the
  training script's internal train/eval split was drawn at the coder-row level, letting
  byte-identical prompts appear on both sides of the split and rendering the early-stopping
  and checkpoint-selection metric unreliable
  (`notes/finetune-validation-split-leakage.md`). No inference was run on any of the three
  discarded adapters and no evaluation metric was computed from them; the only quantities
  ever read from these runs are their training-log loss curves, used to diagnose the split
  defect itself. All adapters and checkpoints from these runs were deleted, and all three
  variants retrained from scratch under a corrected split that holds out whole
  country-year-indicator cells. The discarded runs used the same training pool, hyperparameters,
  and stopping rule as the corrected runs, so their existence conveys no information about
  2019/2023/2024 evaluation outcomes.
