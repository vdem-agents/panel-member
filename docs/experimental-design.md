# Panel Member: Experimental Design

*Updated July 2026. IRT replaced by panel-mean deviation test. Three prompt conditions,
five models. Replacement experiment (primary), attrited-panel augmentation (secondary),
persona and temperature variation (exploratory/sensitivity). Raw panel means throughout.
See `notes/persona-prompting-design-archive.md` for archived persona design.*

---

## Design overview

The experiment addresses three questions in sequence:

**Question 1 (calibration)**: Which prompt condition and model scale produces AI ratings
closest to the human expert panel's raw mean across 12 V-Dem indicators?

**Question 2 (generalization — primary novel finding)**: Does a fine-tuned V-Dem AI coder
transfer to indicators it was not trained on? Trained on 12 indicators, evaluated on X
held-out indicators from the same modules and evidence sources.

**Question 3 (integration robustness — secondary)**: Does adding one AI coder to a
well-formed human panel shift the raw panel mean detectably? Simplified replacement
experiment (k=1) reported as a robustness check on the calibration finding.

The design is a **3 × 5 calibration experiment** (3 prompt conditions × 5 models),
followed by a **generalization test** on held-out indicators, with a **k=1 replacement
check** as supplementary analysis.

---

## Part 1: Calibration experiment

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
| Llama 3.3 70B Instruct | 70B open | GW A100 80GB | Codebook, Evidence, Anonymized |
| Llama 3.2 9B Instruct | 9B open | GW V100 16GB | Codebook, Evidence, Anonymized |
| Llama 3.3 70B (fine-tuned) | 70B ft | GW A100 80GB | Anonymized format, no few-shot |

Fine-tuned Llama 70B uses the anonymized prompt format without the few-shot calibration
block; calibration is embedded in the adapter weights. Comparing it to the base 70B under
Anonymized shows what fine-tuning adds over few-shot prompting on the same model and
evidence format.

### Country-year pool (calibration)

Primary: **2019** (~150–170 country-year-indicator cells per indicator with v15 raw panel
means). 2019 is the clean one-year temporal holdout after the fine-tuning training window
(2013–2018) with full panels and no exogenous anomalies. 2020 is avoided as a primary
test year: COVID-19 emergency restrictions systematically distort civil society, judicial,
and media indicators, making the human panel mean itself a noisier target.

Deployment robustness: **2024** — best-performing model only (Condition 4 or whichever
wins calibration). Tests generalization to recent thin-panel years where AI augmentation
is most needed. Panel size ~4,421 active coders by 2024 (vs. ~8,212 in 2018), so ground
truth is uncertain; frame as deployment simulation, not primary validation.

### Outcome

**MAD**: `mean(|AI_rating − raw_panel_mean|)` across pool, per condition × model ×
indicator. Report as a table: rows = condition × model, columns = indicators (+ mean
across indicators). Secondary: signed deviation by democracy quintile.

### What each comparison tells you

| Comparison | What it isolates |
|---|---|
| Codebook vs. Evidence (same model) | Marginal value of source evidence + few-shot anchors |
| Evidence vs. Anonymized (same model) | Marginal value of anonymization |
| Anonymized (70B base) vs. Fine-tuned 70B | Marginal value of fine-tuning over few-shot |
| Models (same condition) | Scale effects on calibration |
| Quintile signed deviation | Regime-type anchoring bias |

---

## Part 2: Generalization test (primary novel finding)

### Design

The fine-tuned Llama 70B adapter is trained jointly on all 12 indicators. A set of X
held-out indicators — from the same modules and covered by the same evidence sources
(State Dept + Freedom House) — are withheld from training entirely.

**Hold-out indicator candidates** (verify against V-Dem codebook before locking):

| Candidate | Module | Evidence sources | Observability |
|---|---|---|---|
| v2clrelig (freedom of religion) | Civil liberties | State Dept §2c, FH §F | High |
| v2meharjrn (harassment of journalists) | Media | State Dept §2a, FH §D | High |
| v2cseeorgs (CSO entry and exit) | Civil society | State Dept §2b, FH §E | Medium |
| v2jucorrdc (judicial corruption decisions) | Judiciary | State Dept §1e, FH §F | Medium |

Final selection and section mappings must be verified against the V-Dem codebook and
locked in `config/indicator_sections.yaml` before any fine-tuning runs.

### Evaluation

For the 12 trained indicators and X held-out indicators, compute:
- **MAE / exact match** against held-out individual coder ratings from V-Dem v15
- **MAD** against raw panel mean (for cross-condition comparison)

**Primary finding**: if MAE on held-out indicators ≈ MAE on trained indicators, the
result supports a general V-Dem AI coder claim — a fine-tuned model that transfers
across V-Dem's measurement system. If held-out MAE is substantially worse, the result
characterizes the limits of generalization.

This test is more informative than any calibration-only result: good calibration on
training indicators could reflect memorization; good performance on held-out indicators
demonstrates genuine transferability.

---

## Part 3: Integration robustness (secondary / supplemental)

### Design

Simplified replacement experiment: k=1 only. For each country-year in the 2019
calibration pool with ≥8 distinct coders, add one AI rating from the best-calibrated
model and compare the AI-augmented panel mean to the full human panel mean.

```
divergence = |mean(human_panel + AI_rating) − mean(human_panel)|
```

Bootstrap across country-years (B=500). Report mean divergence with 95% CI.

**Purpose**: robustness check on calibration finding. If MAD is already low, this
demonstrates that the low MAD translates to negligible panel-mean distortion under
realistic deployment (k=1). Not the primary claim.

k=2 and k=3 are dropped: with a single fine-tuned model, multiple "distinct" AI
coders are not available, and mixing fine-tuned + few-shot models in the same panel
slot is conceptually awkward. The k=1 test is the cleanest and most policy-relevant
scenario regardless.

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

Re-run the best model at temperature 0.7 on the calibration pool. Compare the
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

LOO MAE is reported as a model × indicator table (5 models × 12 indicators + aggregate
column). The human LOO MAE is the baseline: it represents the error of a randomly held-out
human coder against the rest of their panel. Bootstrap resampling at the CYI level
(B=500) yields CIs and a paired significance test. See `notes/evaluation-metrics.md` for
full rationale and CS background.

---

## Indicators

All 12 selected indicators (selection rationale: `02-indicator-selection.html`):

| Tag | Indicator | Observability |
|---|---|---|
| v2clkill | Political killings | High |
| v2cltort | Torture | High |
| v2mecenefm | Media censorship (formal) | High |
| v2csreprss | Civil society repression | High |
| v2jupoatck | Government attacks on judiciary | High |
| v2mecenefi | Media censorship (informal) | Medium |
| v2juhcind | High court independence | Medium |
| v2clacfree | Academic freedom | Medium |
| v2clslavef | Freedom from forced labor | Medium |
| v2psoppaut | Opposition party autonomy | Medium |
| v2excrptps | Public sector corruption | Medium |
| v2pepwrsoc | Political power by social group | Low |

Expect MAD to vary systematically by observability tier across all conditions. Report
calibration results by tier as well as by indicator.

---

## Pre-registration checklist

Lock all of the following before running any LLM calls or accessing v15 coder-level data
for the replacement pool:

**Calibration pool**
- [ ] Year(s): 2019 primary; 2020 robustness check (best model only — COVID anomaly, not primary validation)
- [ ] Minimum ratings per country-indicator for inclusion
- [ ] Final N per condition (confirm before running)

**Deployment robustness**
- [ ] Year: 2024 (best model only)
- [ ] Source documents: download Freedom House and State Dept for 2024
- [ ] Note: 2024 panel means from thin panels (~4–6 coders); frame as deployment simulation

**Replacement pool**
- [ ] Eligibility: ≥8 distinct coders, 2019 only (same year as calibration pool — AI ratings already exist)
- [ ] No sampling cap — use all eligible CYs from the calibration pool
- [ ] Pool saved to `data/processed/cy_pool.csv`

**Fine-tuning**
- [ ] Training window: 2013–2018 (rationale: post-lateral-coder drop; pre-attrition panels; no overlap with 2019 test year or 2024 deployment check)
- [ ] Training data: individual coder ratings from V-Dem v15 coder-level dataset — one row
      per coder per CYI (~120,000 examples); training set saved to `data/processed/training_set.csv`
- [ ] Hyperparameters: LoRA rank, alpha, learning rate, batch size, epochs, base model commit hash
- [ ] Evaluation metrics: primary MAE/MSE against held-out individual coder ratings;
      secondary MAD against panel mean (for cross-model calibration comparison)

**Models**
- [ ] Claude Sonnet 4.6 API version pinned
- [ ] Llama 405B commit hash (HuggingFace)
- [ ] Llama 3.3 70B Instruct commit hash
- [ ] Llama 3.2 9B commit hash
- [ ] Llama 3.3 70B fine-tuned: base model commit hash + adapter checkpoint path

**Replacement experiment**
- [ ] Divergence threshold value and justification (in rating points on 0–4 scale)
- [ ] Bootstrap B = 500; CI = 2.5–97.5%
- [ ] Coder removal strategy: random primary; worst/best-first as sensitivity bounds
- [ ] k values: 1 (primary); k=2, 3 contingent on whether temperature or persona
      variation produces genuinely distinct AI draws (see exploratory analyses)
- [ ] Stopping rule: document at what k (if any) you cease reporting results, and
      whether you will report results beyond the tolerance threshold

**Persona exploratory**
- [ ] Strict and lenient framing text locked
- [ ] Indicator subset for persona test specified

**Anonymization**
- [ ] Anonymization agent system prompt locked
- [ ] Anonymization applied consistently to both few-shot examples and evaluation text
