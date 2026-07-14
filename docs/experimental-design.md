# Experimental Design

## Overview

The experiment addresses a central decomposition question: when large language models code
political texts, what information are they actually drawing on — pretrained political
knowledge, structured source evidence, or country identity — and how much does each source
contribute to calibration quality?

The design answers this through three prompt conditions that constitute an identification
strategy. The codebook-only condition provides no source text, measuring the baseline
calibration available from pretraining alone. The evidence condition adds raw section text
and few-shot calibration examples, isolating what structured primary source evidence
contributes over pretrained knowledge. The anonymized condition strips country-identifying
information from both the evidence and the calibration examples, isolating how much country
identity, rather than described conditions, drives the ratings. A coverage-tier gradient
— the evaluation indicator set spans strong, partial, and weak source coverage — serves as
a within-study moderating variable that tests whether calibration quality degrades as
source evidence weakens.

The primary design is a **3 × 5 experiment** (3 prompt conditions × 5 models) run on the
full universe of ~205 mapped Type C indicators. The same indicator set is used for all
models: using different sets for small vs. large models would confound model scale with
indicator difficulty in cross-model comparisons. A proportional stratified sample (one
third per module, floor of 2, ~60–70 total, fixed seed) is pre-registered as a
computational fallback if 405B inference cannot complete within 3 job submissions; see
`notes/evaluation-indicator-scope.md` for rationale and compute implications. The two
fine-tuned variants (FT-raw, trained on non-anonymized evidence; FT-anon, trained on
anonymized evidence) are trained on all 206 mapped Type C indicators (~898K coder-CYI
training examples from V-Dem v15 2016–2018) and evaluated on the same set as all other
models.

Five robustness analyses all run on 2023 data using the best-performing model from the
primary 2019 analysis. Four retest the identification claims: a test-year replication,
a few-shot calibration ablation (zero-shot conditions), an information shift test
(transition-adjacent vs. stable country-years), and a re-identification test (does
residual country-identity leakage drive the anonymization result?). A fifth — the
agreement test — compares AI MAE to the average deviation of individual human coders
from the same panel mean. Thin-panel augmentation (k=1 addition to panels ≤8 coders)
is reported as an exploratory illustration in the appendix.

## Part 1: Identification experiment

### Conditions

| Label | Prompt content | Models | New element |
|---|---|---|---|
| Codebook-only | Global framing + codebook text | All | — |
| Evidence | + raw section text + calibration examples | All | Source evidence + calibration anchors |
| Anonymized | + anonymized section text + anonymized calibration examples | All | Country-identity stripped |
| Evidence, no calibration examples | + raw section text only | Best base model | Evidence without anchors |
| Anonymized, no calibration examples | + anonymized section text only | Best base model | Anonymization without anchors |

The first three conditions are additive: Evidence adds source text and calibration examples
to Codebook-only; Anonymized strips country identity from both the focal evidence and the
calibration examples. Conditions 4 and 5 repeat the evidence and anonymization manipulations
without the calibration block, allowing a direct read on how much of the observed improvement
comes from the source text versus the few-shot anchors. These two conditions run on the
best-performing base model only, on **2023 data**, as part of the robustness section — not
the primary 2019 analysis. See the Few-shot calibration ablation section below.

### Models

| Model | Scale | Platform | Conditions |
|---|---|---|---|
| Llama 405B Instruct* | 405B open | GW 8×A100 80GB | Codebook, Evidence, Anonymized |
| Llama 3.3 70B Instruct | 70B open | GW GH200 (preferred) or A100 80GB | Codebook, Evidence, Anonymized |
| Llama 3.2 9B Instruct | 9B open | GW GH200 or V100 16GB | Codebook, Evidence, Anonymized |
| Llama 3.3 70B (FT-raw) | 70B ft | GW GH200 (preferred) or A100 80GB | All 3 conditions; no calibration block; trained on raw evidence |
| Llama 3.3 70B (FT-anon) | 70B ft | GW GH200 (preferred) or A100 80GB | All 3 conditions; no calibration block; trained on anonymized evidence |

**\*405B availability**: Llama 405B requires 8×A100 80GB GPUs and approximately 810 GB of
scratch storage. Its inclusion in the design is contingent on securing sufficient allocation
on GW Pegasus. If the 405B runs cannot be completed within 3 job submissions, the primary
comparison falls back to a four-model design (70B, 9B, FT-raw, FT-anon). The fallback
criterion is fixed at pre-registration; see the checklist below.

Both fine-tuned variants participate in all three primary conditions with the same codebook,
evidence, and anonymization structure as the base models, but without a calibration block —
calibration is embedded in the adapter weights rather than supplied via examples in the
prompt. **FT-raw** is trained on non-anonymized evidence text; **FT-anon** on anonymized
evidence text. Both are trained on all 206 mapped Type C indicators from 2016–2018
(~898K coder-CYI training examples each). The key comparisons: FT-raw vs. base 70B
isolates what fine-tuning adds over few-shot calibration; FT-anon vs. FT-raw shows whether
anonymization during training changes calibration independently of the anonymization
manipulation at inference.

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

### Outcome

**AI MAE**: `|AI_rating − panel_mean|` per CYI, bootstrapped at the CYI level (B=500). This is the primary metric for both the identification claims (comparing AI MAE across prompt conditions) and the substitution check in the robustness section (comparing AI MAE against the average human coder's deviation from the same panel mean). Because the panel mean is a fixed reference shared by all models, the model with the lowest AI MAE is also the model that performs best on the substitution check.

Primary display is a **coefficient plot** (Figure 1): rows = condition × model combinations, x-axis = aggregate AI MAE. The identification claims are reported as a **delta coefficient plot** (Figure 2): three panels showing Δ(Evidence − Codebook), Δ(Anonymized − Codebook), and Δ(Anonymized − Evidence), with rows = models and a reference line at 0. Negative values indicate the added element improved calibration. Δ(Anonymized − Codebook) is the primary identification result: it shows that the information gain from source evidence holds even when country identity is stripped, ruling out anchoring bias as the source of apparent calibration. Δ(Anonymized − Evidence) shows the additional gain from removing country identity from text that already provides source evidence.

Supplementary display: a module-level summary table (indicators grouped by V-Dem module, coverage tier noted) reporting condition × model AI MAE. Secondary: signed deviation by democracy quintile.

### Significance of each comparison

| Comparison | Isolates |
|---|---|
| Codebook vs. Evidence (same model) | Combined value of source evidence and calibration examples |
| Codebook vs. Anonymized (same model) | Combined value of anonymized evidence and calibration examples |
| Evidence vs. Anonymized (same model) | Marginal cost of exposing country identity in the evidence |
| Evidence vs. Evidence, no calibration examples (best base model) | Marginal value of the few-shot calibration block |
| Anonymized vs. Anonymized, no calibration examples (best base model) | Marginal value of calibration examples under anonymization |
| Anonymized (70B base) vs. Fine-tuned 70B | Marginal value of embedding calibration in model weights vs. prompt |
| Models (same condition) | Scale effects on calibration |
| Quintile signed deviation | Regime-type anchoring bias |

## Part 2: Robustness and validation analyses

All five analyses run on 2023 data using the best-performing model from the primary 2019
analysis.

### Identification robustness

These four analyses retest the paper's identification claims on the 2023 holdout.

### Test-year replication (2023)

The winning model from the primary analysis is re-run on 2023 data under all three primary
conditions. The delta estimates from Figure 2 — Δ(Evidence − Codebook), Δ(Anonymized −
Codebook), and Δ(Anonymized − Evidence) — are recomputed for 2023 and compared to the
2019 estimates. If the identification results replicate in direction and magnitude, the
decomposition generalizes beyond the primary test year. Source documents for 2023 are already
ingested and confirmed clean (issue #14, closed 2026-07-12).

### Few-shot calibration ablation (2023)

The evidence and anonymized conditions both include a few-shot calibration block — five
examples spanning the 0–4 scale — alongside the source evidence. This ablation isolates
what those examples contribute over the source evidence alone.

The best-performing base model from the primary 3×5 analysis is re-run on **2023 data**
under two additional conditions: evidence without calibration examples and anonymized text
without calibration examples. Source documents for 2023 are already ingested and confirmed
clean, so no additional ingestion is required.

| Comparison | What it isolates |
|---|---|
| Evidence (zero-shot) vs. Codebook-only | Model reads the text even without calibration anchors |
| Evidence (few-shot) vs. Evidence (zero-shot) | Marginal contribution of calibration examples given named evidence |
| Anonymized (zero-shot) vs. Codebook-only | Text still helps without country identity or calibration anchors |
| Anonymized (few-shot) vs. Anonymized (zero-shot) | Marginal contribution of calibration examples when country identity is also stripped |

The key prediction follows from the anchoring mechanism: in the evidence condition the
model has two scale anchors — the few-shot examples and country-identity priors activated
by the named country. In the anonymized condition, country identity is stripped, so the
model relies more heavily on the calibration examples to map described conditions onto the
0–4 scale. The predicted signature is that the gap between few-shot and zero-shot
performance is **larger under anonymization than under raw evidence** — removing the
country-identity anchor raises the value of the calibration examples. See hypothesis 7.

**Figure**: coefficient plot with two panels — Δ(few-shot − zero-shot) for the evidence
condition (Panel A) and the anonymized condition (Panel B) — each showing bootstrapped
CIs around the AI MAE difference. Reference line at 0; negative values indicate few-shot
improves on zero-shot.

### Information shift test (2023)

The identification design rests on the claim that the model reads and uses the provided
evidence rather than drawing on stored knowledge of the country. The stiffest test of this
is country-years where political conditions changed substantially: if the model is genuinely
reading the text, it should update more in response to evidence precisely where that evidence
carries new information — that is, where the country's political situation differs from what
pretraining would lead the model to expect.

Country-years in the 2023 evaluation pool are tagged as transition-adjacent using the V-Dem
Episodes of Regime Transformation (ERT) dataset (onset or peak year flag). The continuous
moderator is |Δv2x_polyarchy| from year t−1 to t. AI MAE is computed separately for
transition-adjacent and stable country-years under each condition. The pre-registered
hypothesis: Δ(Evidence − Codebook) is more negative — that is, the gain from adding evidence
is larger — in transition-adjacent country-years than in stable ones.

**Figure**: Coefficient plot with two panels — Δ(Evidence − Codebook) and
Δ(Anonymized − Codebook) — each showing three dots with bootstrapped CIs: all country-years,
stable, and transition-adjacent. Reference line at 0.

### Re-identification test

The anonymization condition assumes that stripping country names, named institutions, and
recognizable events removes enough identifying information to prevent the coding model from
anchoring on prior beliefs about the country. This assumption is tested directly.

After each anonymized coding call in the 2023 run, a follow-up message is sent with the
full conversation as context: *"Based only on the political conditions described in the text
you just reviewed, what are your top three guesses for which country this describes? List
them in order of confidence and briefly note the cue that led to each."* The rating from
the first call is already locked before the follow-up is sent, so the identification prompt
cannot contaminate the rating.

Re-identification has been shown to succeed at surprisingly high rates even in formally
anonymized text, as language models can reconstruct country identity from indirect cues —
institutional descriptions, event sequences, and geographic references — that rule-based
anonymization does not remove. The purpose here is both to characterize how often this
occurs and to test whether residual leakage is driving the compression signature observed
in the main results.

**Metrics**: top-1 accuracy (first guess correct) and top-3 accuracy (correct country
appears in any of the three guesses), bootstrapped at the CYI level (B=500). The primary
diagnostic is the signed deviation (AI rating − panel mean) for correctly re-identified
versus non-re-identified cases. If correctly re-identified cases show larger directional
bias — rated too high for autocracies, too low for democracies — this confirms that
residual country-identity leakage in the anonymized text is the mechanism behind any
remaining compression.

**Figures**:
- *Accuracy*: coefficient plot, rows = regime type (Panel A) and region (Panel B), x-axis =
  re-identification accuracy, vertical reference line at overall accuracy.
- *Signed deviation*: same two-panel structure, x-axis = mean signed deviation by
  re-identified vs. not, reference line at 0.

### Applied performance

### Agreement test (2023)

The best-performing model from the primary 2019 analysis is evaluated on 2023 data by
comparing its AI MAE against the human panel MAE — the average deviation of individual
human coders from the same panel mean. Both are computed against the full panel mean for
each CYI. If AI MAE is at or below the human panel MAE, the AI deviates from the panel
consensus by no more than a typical human coder. This is reported for all three primary
conditions to show whether the result holds across the full prompt design, not only under
the best condition.

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
| Exact match rate | `% (AI_rating == round(panel_mean))` | Calibration secondary |
| Adjacent agreement | `% (\|AI_rating − round(panel_mean)\| ≤ 1)` | Calibration secondary |
| Signed deviation by quintile | `mean(AI_rating − panel_mean)` by v2x_polyarchy quintile | Compression diagnostic |
| Top-1 re-identification accuracy | `% (first country guess == true country)`, bootstrap CIs, by regime type and region | Anonymization integrity |
| Top-3 re-identification accuracy | `% (true country in top 3 guesses)`, bootstrap CIs, by regime type and region | Anonymization integrity |
| Signed deviation by re-identification | `mean(AI_rating − panel_mean)` for re-identified vs. not, by regime type | Anchoring mechanism test |
| divergence_k | `\|mean_aug_k − mean_full\|` | Replacement check |
| Augmentation gain | `\|mean_aug_k − mean_ref\| < \|mean_thin − mean_ref\|`? | Panel augmentation |

AI MAE against the raw panel mean is the primary metric. Bootstrap resampling at the CYI level (B=500) yields confidence intervals and a paired significance test for each delta metric. The human panel MAE — the average deviation of individual human coders from the same panel mean — serves as the substitution benchmark in the robustness section; because the panel mean is a fixed reference, model selection on AI MAE is equivalent to selection on the substitution criterion. Formal paired difference tests are reported in the appendix; the main figures communicate the same comparisons visually. Supplementary display: a module-level summary table (indicators grouped by V-Dem module, coverage tier noted) reporting AI MAE by condition and model. See `notes/evaluation-metrics.md` for full rationale.

## Indicators

### Training set (206 indicators)

All mapped Type C indicators from V-Dem v15, 2016–2018 — all coverage tiers included.
Full list: `initial-exploration/explore-indicators/02-indicator-selection.html`.

### Evaluation set (~205 indicators)

The full universe of all mapped Type C indicators in `config/indicator_sections.yaml`
(~205 total). Same set for all models — a prerequisite for clean cross-model comparison
(different indicator sets for different models would confound model scale with indicator
difficulty). Spans all three coverage tiers, preserving the tier-gradient as a within-study
moderating variable. Section mapping complete per issue #1 (closed 2026-07-11). Few-shot
examples locked when `data/fewshot_examples.json` is populated (issue #8).

**Pre-registered fallback**: if 405B inference cannot complete within 3 job submissions
(the binding HPC constraint — only 2 eight-A100 nodes cluster-wide), the evaluation set
falls back to a proportional stratified random sample: one third of each module's
indicators, rounded to the nearest integer, with a floor of 2 per module (~60–70 total).
The floor prevents small modules (e.g., Sovereignty with 3 indicators, Executive
legitimation with 4) from being underrepresented. The sampling rule, random seed, and
trigger condition are all fixed at pre-registration, before any inference runs. See
`notes/evaluation-indicator-scope.md` for the full rationale and per-model compute
comparison.

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
   country identity from both the evidence and calibration examples reduces deviation
   further, reflecting the cost of named-entity anchoring in the evidence condition.

3. **Clean information gain is independent of anchoring** (Δ(Anonymized − Codebook) < 0):
   the gain from anonymized evidence over codebook-only holds even without country identity,
   establishing that the model is reading and using the source text rather than relying
   on pretrained knowledge of the country.

4. **Evidence matters more in transition years**: Δ(Evidence − Codebook) is more negative
   for country-years tagged as transition-adjacent (ERT onset or peak year) than for stable
   country-years, reflecting that source evidence contributes most when stored knowledge
   of the country is most outdated.

5. **Re-identification predicts bias**: in the anonymized condition, cases where the model
   correctly identifies the country show larger directional deviation from the panel mean —
   positive for autocracies, negative for democracies — consistent with anchoring on a
   known country prior.

6. **Calibration degrades with weaker source coverage**: AI MAE is higher for weak-coverage
   indicators than for strong-coverage indicators, across all conditions and models.

7. **Few-shot calibration contributes more under anonymization than under raw evidence**:
   the improvement from adding calibration examples — Δ(few-shot − zero-shot) AI MAE —
   is larger in the anonymized condition than in the evidence condition. When country
   identity is present in the evidence, the model can use country-identity priors as a
   secondary scale anchor, reducing its dependence on the few-shot examples. When country
   identity is stripped, that anchor is gone and the calibration examples carry more weight.
   The predicted signature is a larger few-shot gap under anonymization than under raw
   evidence.

### Evaluation sample

- **Primary year**: 2019. All country-year-indicator cells with a raw panel mean in V-Dem
  v15 and a processed source document in both State Department and Freedom House archives.
- **Minimum coders**: [ ] to be confirmed before running.
- **Robustness year**: 2023, best-performing model only. Source documents confirmed clean
  (issue #14, closed 2026-07-12).
- **k=1 replacement pool**: country-years in the 2019 evaluation pool with ≥8 distinct
  coders. No sampling cap.

### Primary outcomes

AI MAE against the raw panel mean is the primary metric throughout. The three delta metrics —
Δ(Evidence − Codebook), Δ(Anonymized − Codebook), Δ(Anonymized − Evidence) — are the
direct tests of hypotheses 1–3. All are bootstrapped at the CYI level (B=500,
CI = 2.5–97.5%). Signed deviation by v2x_polyarchy quintile is the compression diagnostic.
Exact match rate and adjacent agreement are secondary calibration summaries.

### Modeling choices locked before running

- **Fine-tuning window**: 2016–2018. Rationale: source documents reliably available from
  2016; no overlap with 2019 test year or 2023 robustness year; captures the post-Arab
  Spring democratic backsliding period.
- **No-calibration-example conditions**: run only after the best-performing base model is
  identified from the primary 3×5 results, on 2023 data as part of the robustness section.
  Uses the identical prompt structure as conditions 2 and 3 minus the calibration block.
  Not part of the primary 2019 analysis.
- **Anonymization**: system prompt for the anonymization agent locked before any anonymized
  condition runs; applied identically to focal evidence and calibration examples.
- **405B fallback**: if Llama 405B cannot complete inference within 3 job submissions,
  the primary comparison falls back to a four-model design (70B, 9B, FT-raw, FT-anon).
  Trigger criterion is fixed here, before any inference runs.
- [ ] Indicator fallback seed: fixed random seed for the proportional stratified sample
  (~60–70 indicators) recorded before any inference runs.
- [ ] Divergence threshold for the k=1 replacement check: value and justification (in
  rating points on the 0–4 scale) confirmed before running.

### Robustness analyses locked before running

- **Information shift**: ERT onset/peak year flag is the primary transition-adjacent
  indicator; |Δv2x_polyarchy| is the continuous moderator. Threshold for the continuous
  moderator fixed before running. Applied to 2023 data.
- **Re-identification**: follow-up prompt text locked before the 2023 anonymized condition
  runs. Top-1 accuracy: first guess matches true country. Top-3 accuracy: true country
  appears in any of the three guesses. Signed deviation by re-identification status is
  pre-specified as the primary mechanism test (hypothesis 5).
