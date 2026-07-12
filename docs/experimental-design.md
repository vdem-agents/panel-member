# Panel Member: Experimental Design

*Updated July 2026. Three prompt conditions, five models. Inference on a proportional
stratified sample of ~80 indicators (one third per module, floor of 2; same set for all
models), required for clean cross-model comparison. Training on all strong + partial Type C
indicators (~174; ~1.95M coder-CYI examples from V-Dem v15). Coverage-tier gradient
as within-study moderating variable. Raw panel means throughout.
See `notes/persona-prompting-design-archive.md` for archived persona design.*

---

## Design overview

The experiment addresses two questions:

**Question 1 (substitution)**: Which prompt condition and model scale produces AI ratings
closest to the human expert panel's raw mean across the ~60–70 evaluation indicators, and
does this vary with coverage tier?

**Question 2 (generalization)**: Does LOO MAE degrade as source-coverage tier weakens?
The evaluation indicator set spans strong, partial, and weak coverage, making coverage
tier a within-study moderating variable rather than a separate experimental condition.

The design is a **3 × 6 experiment** (3 prompt conditions × 6 models) on a proportional
stratified sample of ~80 evaluation indicators (one third per module, floor of 2, spanning
all coverage tiers), with a **k=1 replacement check** as supplementary analysis. The same
indicator set is used for all models: using different sets for small vs. large models
would confound model scale with indicator selection in cross-model comparisons.
The two fine-tuned variants (FT-raw, trained on non-anonymized evidence; FT-anon, trained
on anonymized evidence) are both trained on all strong + partial indicators (~174; ~1.95M
coder-CYI training examples from V-Dem v15 2013–2018) and evaluated on the same
stratified set as all other models.

---

## Part 1: Substitution experiment

### Conditions

| Label | Prompt content | New element |
|---|---|---|
| Codebook-only | Global framing + codebook text | — |
| Evidence | + raw section text + few-shot calibration examples | Structured source evidence + anchors |
| Anonymized | + anonymized section text + anonymized few-shot examples | Country-identity stripped |

Each condition is additive: Evidence adds source text and few-shot calibration anchors to
Codebook-only; Anonymized strips country identity from both the focal evidence and the
few-shot examples.

### Models

| Model | Scale | Platform | Conditions |
|---|---|---|---|
| Claude Sonnet 4.6 | Frontier | Claude API | Codebook, Evidence, Anonymized |
| Llama 405B Instruct | 405B open | GW 8×A100 80GB | Codebook, Evidence, Anonymized |
| Llama 3.3 70B Instruct | 70B open | GW GH200 (preferred) or A100 80GB | Codebook, Evidence, Anonymized |
| Llama 3.2 9B Instruct | 9B open | GW GH200 or V100 16GB | Codebook, Evidence, Anonymized |
| Llama 3.3 70B (FT-raw) | 70B ft | GW GH200 (preferred) or A100 80GB | All 3 conditions; no few-shot block; trained on raw evidence |
| Llama 3.3 70B (FT-anon) | 70B ft | GW GH200 (preferred) or A100 80GB | All 3 conditions; no few-shot block; trained on anonymized evidence |

Both fine-tuned variants participate in all three conditions with the same codebook, evidence,
and anonymization structure as the base models, but without a few-shot calibration block in
any condition — calibration is embedded in the adapter weights. **FT-raw** is trained on
non-anonymized evidence text; **FT-anon** on anonymized evidence text. Both are trained on
all strong + partial Type C indicators (~174) from 2013–2018 (~1.95M coder-CYI training
examples each). The key comparisons: FT-raw vs. base 70B isolates what fine-tuning adds
over few-shot; FT-anon vs. FT-raw shows whether anonymization during training changes
calibration — independent of the anonymization manipulation at inference.

### Country-year pool (calibration)

Primary: **2019** (~150–170 country-year-indicator cells per indicator with v15 raw panel
means). 2019 is the clean one-year temporal holdout after the fine-tuning training window
(2013–2018) with full panels and no exogenous anomalies. 2020 is avoided as a primary
test year: COVID-19 emergency restrictions systematically distort civil society, judicial,
and media indicators, making the human panel mean itself a noisier target.

Robustness check: **2022** — best-performing model only. Falls outside the 2013–2018
training window, has stable State Department and Freedom House report production, and
is within the coding window for all retained modules. The originally planned year (2024)
was set aside due to DOGE-related disruption to State Department operations in early
2025 (see `initial-exploration/explore-indicators/05-section-mapping-and-coverage.qmd`
section 5).

### Outcome

**LOO MAE**: for each CYI, compare `|AI_rating − panel_mean|` against the human baseline
`mean(|rating_i − mean(panel \ {i})|)`. Bootstrap at the CYI level (B=500). Report as
a forest plot (indicators as rows grouped by module, paired AI vs. human estimates or
difference centered on zero) and a supplementary table (rows = condition × model, columns
= 25–30 indicators with coverage tier noted). Secondary: signed deviation by democracy
quintile.

### What each comparison tells you

| Comparison | What it isolates |
|---|---|
| Codebook vs. Evidence (same model) | Marginal value of source evidence + few-shot anchors |
| Evidence vs. Anonymized (same model) | Marginal value of anonymization |
| Anonymized (70B base) vs. Fine-tuned 70B | Marginal value of fine-tuning over few-shot |
| Models (same condition) | Scale effects on calibration |
| Quintile signed deviation | Regime-type anchoring bias |

---

## Part 2: Coverage-tier moderation (generalization embedded in main analysis)

### Design

The fine-tuned Llama 70B adapter is trained on all strong + partial coverage Type C
indicators (~174 indicators). The ~60–70 evaluation indicators are drawn from all
coverage tiers: strong (directly addressed by dedicated report sections), partial
(addressed but not systematically), and weak (only tangentially covered).

Coverage tier is a within-study moderating variable, not a separate experimental
condition. There is no training/held-out split: the model is trained on strong + partial
indicators and we observe how well it codes across the coverage gradient.

Exact evaluation indicators are TBD pending qualitative section-mapping review.
Candidates from weak-coverage modules include Legislature (v2lg*), State bureaucracy
(v2st*), Sovereignty (v2sv*), Education content (v2ed*), and Media curriculum (v2med*).

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

k=2 and k=3 are contingent on persona exploratory results: if persona prompting on the
best fine-tuned model produces reliably distinct ratings, those additional draws serve
as distinct AI panel members. The k=1 test is the primary and most policy-relevant
scenario; k=2/k=3 are added as secondary if persona results support them.

---

## Part 3: Augmentation of attrited panels (secondary)

**Target**: countries with well-formed panels in 2015 (≥8 coders) and thin panels by
2022 (≤5 coders) due to post-2013 attrition.

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

### Persona variation (exploratory)

Add 2 persona conditions (strict framing / lenient framing) to the best-performing
model. Run on a subset of indicators (suggest: 4 high-observability indicators to
maximize sensitivity).

**Pre-registered as exploratory.** Expected: null or weak effects per archived evidence
(Morocho et al. 2026; anchor-to-indicator null result in our own data). If persona
conditions produce systematic, reliable shifts in the direction of their framing, they
provide a cheap additional source of distinct AI panel members. If not, the test
contributes to the growing evidence that persona prompting does not reliably shift
ordinal ratings in structured coding tasks.

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

## Outcome variables

| Variable | Definition | Role |
|---|---|---|
| LOO MAE | `mean(\|AI_rating − panel_mean\|)` vs. `mean(\|rating_i − mean(panel \ {i})\|)` with bootstrap CIs | Calibration primary |
| Exact match rate | `% (AI_rating == round(panel_mean))` | Calibration secondary |
| Adjacent agreement | `% (\|AI_rating − round(panel_mean)\| ≤ 1)` | Calibration secondary |
| Signed deviation by quintile | `mean(AI_rating − panel_mean)` by v2x_polyarchy quintile | Compression diagnostic |
| divergence_k | `\|mean_aug_k − mean_full\|` | Replacement check |
| Augmentation gain | `\|mean_aug_k − mean_ref\| < \|mean_thin − mean_ref\|`? | Augmentation |

LOO MAE is the primary metric. Human LOO MAE is the baseline: the error of a randomly
held-out human coder against the rest of their panel. Bootstrap resampling at the CYI
level (B=500) yields CIs and a paired significance test. Primary display is a forest
plot; supplementary display is a model × indicator table (5 models × ~60–70 indicators
grouped by module, with coverage tier noted). See `notes/evaluation-metrics.md` for
full rationale and CS background.

---

## Indicators

### Training set (~174 indicators)

All strong + partial coverage Type C indicators from V-Dem v15, 2013–2018. Modules:
Civil liberties, Media freedom, Digital/social media, Civil society, Elections, Judiciary,
Academic freedom (strong); Civic activism, Executive, Political parties, Political equality
(partial). Weak and none coverage indicators excluded from training.
Full list: `initial-exploration/explore-indicators/02-indicator-selection.html`.

### Evaluation set (25–30 indicators, TBD)

Proportional stratified random sample: one third of each module's indicators, rounded to
the nearest integer, with a floor of 2 per module. The floor prevents tiny modules (e.g.,
Sovereignty with 3 total, Executive legitimation with 4) from contributing only 1 indicator
while mid-size modules (Deliberation and State bureaucracy with 7 each) contribute 2. At
this fraction the 16 retained modules yield approximately **78–82 indicators** total. Same
set for all models — a prerequisite for clean cross-model comparison (different indicator
sets for different models would confound model scale with indicator difficulty). Exact list
locked after section-mapping completion (GitHub issue #1). Must span all three coverage
tiers to preserve the tier-gradient as a within-study moderating variable.

Expect LOO MAE to vary with observability tier and coverage tier. Report calibration
results by both dimensions.

---

## Pre-registration checklist

Lock all of the following before running any LLM calls or accessing v15 coder-level data
for the replacement pool:

**Calibration pool**
- [ ] Year(s): 2019 primary; 2022 robustness check (best model only)
- [ ] Minimum ratings per country-indicator for inclusion
- [ ] Final N per condition (confirm before running)

**Robustness check**
- [ ] Year: 2022 (best model only)
- [ ] Source documents: download Freedom House and State Dept for 2022

**Replacement pool**
- [ ] Eligibility: ≥8 distinct coders, 2019 only (same year as evaluation pool — AI ratings already exist)
- [ ] No sampling cap — use all eligible CYs from the evaluation pool
- [ ] Pool saved to `data/processed/cy_pool.csv`

**Fine-tuning**
- [ ] Training window: 2013–2018 (rationale: post-lateral-coder drop; pre-attrition panels; no overlap with 2019 test year or 2022 robustness check)
- [ ] Training data: individual coder ratings from V-Dem v15 coder-level dataset — one row
      per coder per CYI, covering all strong + partial Type C indicators (~174 indicators);
      training set saved to `data/processed/training_set.csv`
- [ ] Hyperparameters: LoRA rank, alpha, learning rate, batch size, epochs, base model commit hash
- [ ] Evaluation metrics: LOO MAE against panel mean (primary); exact match and adjacent
      agreement (secondary); coverage-tier gradient analysis

**Models**
- [ ] Claude Sonnet 4.6 API version pinned
- [ ] Llama 405B commit hash (HuggingFace)
- [ ] Llama 3.3 70B Instruct commit hash
- [ ] Llama 3.2 9B commit hash
- [ ] Llama 3.3 70B fine-tuned: base model commit hash + adapter checkpoint path

**Replacement experiment**
- [ ] Divergence threshold value and justification (in rating points on 0–4 scale)
- [ ] Bootstrap B = 500; CI = 2.5–97.5%
- [ ] Coder removal strategy: random (uniform draw)
- [ ] k values: 1 (primary); k=2, 3 contingent on persona exploratory results
      producing reliably distinct AI draws (see exploratory analyses)
- [ ] If k>1 phase is triggered: pre-register stopping rule (maximum k, tolerance threshold)

**Persona exploratory**
- [ ] Strict and lenient framing text locked
- [ ] Indicator subset for persona test specified

**Anonymization**
- [ ] Anonymization agent system prompt locked
- [ ] Anonymization applied consistently to both few-shot examples and evaluation text
