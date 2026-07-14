# Panel Member: Experimental Design

*Updated July 2026. Five prompt conditions: three primary conditions run across all five
models; two additional no-calibration-example conditions run on the best-performing base
model to isolate the contribution of the few-shot calibration block. Inference on the full
universe of ~205 mapped Type C indicators (primary); proportional stratified sample (one
third per module, floor of 2, ~60–70 total) pre-registered as computational fallback — see
`notes/evaluation-indicator-scope.md`. Training on all 206 mapped Type C indicators
(~1.22M coder-CYI examples from V-Dem v15). Coverage-tier gradient as within-study
moderating variable. Raw panel means throughout. Llama 405B is included in the primary
design but is contingent on HPC availability — see the 405B note in the Models section.
Persona prompting is a post-hoc illustration on the best model, not a registered
condition; see `notes/persona-prompting-design-archive.md`.*

---

## Design overview

The experiment addresses two questions:

**Question 1 (substitution)**: Which prompt condition and model scale produces AI ratings
closest to the human expert panel's raw mean across the ~52–69 evaluation indicators, and
does this vary with coverage tier?

**Question 2 (generalization)**: Does LOO MAE degrade as source-coverage tier weakens?
The evaluation indicator set spans strong, partial, and weak coverage, making coverage
tier a within-study moderating variable rather than a separate experimental condition.

The primary design is a **3 × 5 experiment** (3 prompt conditions × 5 models) on the full
universe of ~205 mapped Type C indicators, with a **k=1 replacement check** as supplementary
analysis. Two additional conditions — evidence without calibration examples and anonymized
text without calibration examples — run on the best-performing base model only, isolating
the contribution of the few-shot calibration block from the contribution of source evidence
and anonymization. The same indicator set is used for all models: using different sets for
small vs. large models would confound model scale with indicator difficulty in cross-model
comparisons. A proportional stratified sample (one third per module, floor of 2, ~60–70
total, fixed seed) is pre-registered as a computational fallback if 405B inference cannot
complete within 3 job submissions; see `notes/evaluation-indicator-scope.md` for rationale
and compute implications. The two fine-tuned variants (FT-raw, trained on non-anonymized
evidence; FT-anon, trained on anonymized evidence) are trained on all 206 mapped indicators
(~1.22M coder-CYI training examples from V-Dem v15 2016–2018) and evaluated on the same
set as all other models.

---

## Part 1: Substitution experiment

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
best-performing base model only and are not part of the primary cross-model comparison.

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
(~1.22M coder-CYI training examples each). The key comparisons: FT-raw vs. base 70B
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

**LOO MAE**: for each CYI, compare `|AI_rating − panel_mean|` against the human baseline
`mean(|rating_i − mean(panel \ {i})|)`. Bootstrap at the CYI level (B=500).

Primary display is a **coefficient plot** (Figure 1): rows = condition × model combinations,
x-axis = aggregate LOO MAE, horizontal reference line at the human LOO MAE. Dots left of
the reference line indicate the AI deviates from the panel mean by less than a typical
held-out human coder.

The identification claims are reported as a **delta coefficient plot** (Figure 2): three
panels showing Δ(Evidence − Codebook), Δ(Anonymized − Codebook), and
Δ(Anonymized − Evidence), with rows = models and a reference line at 0. Negative values
indicate the added element improved calibration. Δ(Anonymized − Codebook) is the primary
identification result: it shows that the information gain from source evidence holds even
when country identity is stripped, ruling out anchoring bias as the source of apparent
calibration. Δ(Anonymized − Evidence) shows the additional gain from removing country
identity from text that already provides source evidence.

Supplementary display: a module-level summary table (indicators grouped by V-Dem module,
coverage tier noted) reporting condition × model LOO MAE. Secondary: signed deviation by
democracy quintile.

### What each comparison tells you

| Comparison | What it isolates |
|---|---|
| Codebook vs. Evidence (same model) | Combined value of source evidence and calibration examples |
| Codebook vs. Anonymized (same model) | Combined value of anonymized evidence and calibration examples |
| Evidence vs. Anonymized (same model) | Marginal cost of exposing country identity in the evidence |
| Evidence vs. Evidence, no calibration examples (best base model) | Marginal value of the few-shot calibration block |
| Anonymized vs. Anonymized, no calibration examples (best base model) | Marginal value of calibration examples under anonymization |
| Anonymized (70B base) vs. Fine-tuned 70B | Marginal value of embedding calibration in model weights vs. prompt |
| Models (same condition) | Scale effects on calibration |
| Quintile signed deviation | Regime-type anchoring bias |

---

## Part 2: Coverage-tier moderation (generalization embedded in main analysis)

### Design

The fine-tuned Llama 70B adapter is trained on all 206 mapped Type C indicators.
Coverage tier is a within-study moderating variable, not a separate experimental
condition — the model is trained across all tiers and we observe how calibration
quality varies across the strong → weak coverage gradient at inference.

Section mapping is complete (GitHub issue #1, closed 2026-07-11). The evaluation set
is the full universe of ~205 indicators in `config/indicator_sections.yaml`.
`data/fewshot_examples.json` will be populated with 5 examples per indicator (one per
ordinal level). See GitHub issue #8 for the population task.

### Evaluation

For all evaluation indicators (spanning coverage tiers), compute:
- **LOO MAE** against panel mean (primary metric, comparable across all conditions)
- **Exact match / adjacent agreement** (secondary)

**Primary finding**: if LOO MAE is stable across the strong → weak coverage gradient,
the result supports a scalable AI coder applicable across the full ~216 Type C indicator
set. If the gradient is steep, it characterizes where the approach reaches its limits.

---

## Part 3: Integration robustness (secondary / supplemental)

### Design

Simplified replacement experiment: k=1 only. For each country-year in the 2019
evaluation pool with ≥8 distinct coders, add one AI rating from the best-calibrated
model and compare the AI-augmented panel mean to the full human panel mean.

```
divergence = |mean(human_panel + AI_rating) − mean(human_panel)|
```

Bootstrap across country-years (B=500). Report mean divergence with 95% CI.

**Purpose**: robustness check on calibration finding. If MAD is already low, this
demonstrates that the low MAD translates to negligible panel-mean distortion under
realistic deployment (k=1). Not the primary claim.

k=1 is the primary and most policy-relevant scenario. k=2 and k=3 are not part of the
registered design and are not contingent on any in-paper result.

---

## Part 4: Augmentation of thinning panels (secondary)

**Target**: countries with well-formed panels in 2015 (≥8 coders) and thin panels by
2022 (≤5 coders) due to post-2013 coder departures.

**Setup**:
- `mean_ref` = 2015 thick-panel raw mean (treated as reference)
- `mean_thin` = 2022 thin-panel raw mean (baseline)
- `mean_aug_k` = 2022 thin panel + k AI ratings, k ∈ {1, 2}

**Metric**: `|mean_aug_k − mean_ref| vs. |mean_thin − mean_ref|`. Does AI augmentation
move the current thin-panel mean toward the historical thick-panel reference?

**Limitation**: this conflates panel size with temporal democratic change. A country may
have genuinely different democracy levels in 2015 and 2022. Frame as an application
illustration, not causal identification. Report the limitation explicitly in the paper.

---

## Exploratory and sensitivity analyses

### Persona variation (post-hoc illustration)

Add 2 persona conditions (strict framing / lenient framing) to the best-performing
model. Run on a subset of indicators (suggest: 4 high-observability indicators to
maximize sensitivity). This is not a registered condition — it runs after the main
results are in, on the holdout test set, as an unregistered demonstration.

The question is simply whether persona framing moves ratings reliably and directionally.
If it does, that is an illustration of how one AI coder could stand in for multiple
distinct panel members at low marginal cost — and a hook for a follow-on paper. If it
does not, it adds to the evidence (Morocho et al. 2026; our own anchor-to-indicator
null) that persona prompting does not reliably shift ordinal ratings in structured coding
tasks. Either way it is reported as an illustration, not a finding of the current paper.

Report: signed deviation (strict condition − neutral) and (lenient − neutral), by
indicator and democracy quintile.

### Temperature variation (sensitivity)

Re-run the best model at temperature 0.7 on the evaluation pool. Compare the
distribution of ratings across draws to the temperature=0 result. This is a measure of
model uncertainty — the spread of the distribution indicates how much variance the model
has around its modal answer.

Not used as a source of distinct panel members in the main replacement experiment.
Report as a diagnostic in the supplementary materials.

---

## Robustness and validation analyses

These three analyses address the two threats most likely to concern readers: whether the
identification results replicate outside the primary test year, and whether the anonymization
condition is working as intended.

### Test-year replication (2023)

The winning model from the primary analysis is re-run on 2023 data under all three primary
conditions. The delta estimates from Figure 2 — Δ(Evidence − Codebook), Δ(Anonymized −
Codebook), and Δ(Anonymized − Evidence) — are recomputed for 2023 and compared to the
2019 estimates. If the identification results replicate in direction and magnitude, the
decomposition generalizes beyond the primary test year. Source documents for 2023 are already
ingested and confirmed clean (issue #14, closed 2026-07-12).

### Information shift analysis

The identification design rests on the claim that the model reads and uses the provided
evidence rather than drawing on stored knowledge of the country. The stiffest test of this
is country-years where political conditions changed substantially: if the model is genuinely
reading the text, it should update more in response to evidence precisely where that evidence
carries new information — that is, where the country's political situation at the time of
coding differs from what pretraining would lead the model to expect.

Country-years are tagged as transition-adjacent using the V-Dem Episodes of Regime
Transformation (ERT) dataset (onset or peak year flag). The continuous moderator is
|Δv2x_polyarchy| from year t−1 to t. LOO MAE is computed separately for transition-adjacent
and stable country-years under each condition. The pre-registered hypothesis:
Δ(Evidence − Codebook) is more negative — that is, the gain from adding evidence is larger
— in transition-adjacent country-years than in stable ones.

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

---

## Outcome variables

| Variable | Definition | Role |
|---|---|---|
| LOO MAE | `mean(\|AI_rating − panel_mean\|)` vs. `mean(\|rating_i − mean(panel \ {i})\|)` with bootstrap CIs | Calibration primary |
| Δ(Evidence − Codebook) MAE | `LOO MAE_evidence − LOO MAE_codebook`, per model, bootstrap CIs | Identification claim 1: value of source evidence |
| Δ(Anonymized − Codebook) MAE | `LOO MAE_anon − LOO MAE_codebook`, per model, bootstrap CIs | Identification claim 2: clean information gain free of country-identity anchoring |
| Δ(Anonymized − Evidence) MAE | `LOO MAE_anon − LOO MAE_evidence`, per model, bootstrap CIs | Identification claim 3: cost of exposing country identity |
| Exact match rate | `% (AI_rating == round(panel_mean))` | Calibration secondary |
| Adjacent agreement | `% (\|AI_rating − round(panel_mean)\| ≤ 1)` | Calibration secondary |
| Signed deviation by quintile | `mean(AI_rating − panel_mean)` by v2x_polyarchy quintile | Compression diagnostic |
| Top-1 re-identification accuracy | `% (first country guess == true country)`, bootstrap CIs, by regime type and region | Anonymization integrity |
| Top-3 re-identification accuracy | `% (true country in top 3 guesses)`, bootstrap CIs, by regime type and region | Anonymization integrity |
| Signed deviation by re-identification | `mean(AI_rating − panel_mean)` for re-identified vs. not, by regime type | Anchoring mechanism test |
| divergence_k | `\|mean_aug_k − mean_full\|` | Replacement check |
| Augmentation gain | `\|mean_aug_k − mean_ref\| < \|mean_thin − mean_ref\|`? | Panel augmentation |

LOO MAE is the primary metric. The human LOO MAE is the reference: the typical error of a
held-out human coder against the rest of their panel, averaged across all coders and
country-year-indicator observations in the evaluation pool. It is not zero — individual
coders genuinely disagree with the panel consensus, and that disagreement is what the AI
is being asked to match. Bootstrap resampling at the CYI level (B=500) yields confidence
intervals and a paired significance test for each delta metric. Formal paired difference
tests are reported in the appendix; the main figures communicate the same comparisons
visually. Supplementary display: a module-level summary table (indicators grouped by
V-Dem module, coverage tier noted) reporting LOO MAE by condition and model.
See `notes/evaluation-metrics.md` for full rationale.

---

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

Expect LOO MAE to vary with observability tier and coverage tier. Report calibration
results by both dimensions.

---

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

6. **Calibration degrades with weaker source coverage**: LOO MAE is higher for weak-coverage
   indicators than for strong-coverage indicators, across all conditions and models.

### Evaluation sample

- **Primary year**: 2019. All country-year-indicator cells with a raw panel mean in V-Dem
  v15 and a processed source document in both State Department and Freedom House archives.
- **Minimum coders**: [ ] to be confirmed before running.
- **Robustness year**: 2023, best-performing model only. Source documents confirmed clean
  (issue #14, closed 2026-07-12).
- **k=1 replacement pool**: country-years in the 2019 evaluation pool with ≥8 distinct
  coders. No sampling cap.

### Primary outcomes

LOO MAE is the primary metric throughout. The three delta metrics —
Δ(Evidence − Codebook), Δ(Anonymized − Codebook), Δ(Anonymized − Evidence) — are the
direct tests of hypotheses 1–3. All are bootstrapped at the CYI level (B=500,
CI = 2.5–97.5%). Signed deviation by v2x_polyarchy quintile is the compression diagnostic.
Exact match rate and adjacent agreement are secondary calibration summaries.

### Modeling choices locked before running

- **Fine-tuning window**: 2016–2018. Rationale: source documents reliably available from
  2016; no overlap with 2019 test year or 2023 robustness year; captures the post-Arab
  Spring democratic backsliding period.
- **No-calibration-example conditions**: run only after the best-performing base model is
  identified from the primary 3×5 results, using the identical prompt structure as
  conditions 2 and 3 minus the calibration block.
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
  moderator fixed before running. The transition/stable split is applied to 2019 data;
  the same split is used for the 2023 replication without adjustment.
- **Re-identification**: follow-up prompt text locked before the 2023 anonymized condition
  runs. Top-1 accuracy: first guess matches true country. Top-3 accuracy: true country
  appears in any of the three guesses. Signed deviation by re-identification status is
  pre-specified as the primary mechanism test (hypothesis 5).
