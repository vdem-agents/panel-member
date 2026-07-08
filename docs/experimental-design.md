# Panel Member: Experimental Design

*Updated July 2026. IRT replaced by panel-mean deviation test. Four prompt conditions,
four model scales. Replacement experiment (primary), attrited-panel augmentation
(secondary), persona and temperature variation (exploratory/sensitivity). Raw panel means
throughout. See `notes/persona-prompting-design-archive.md` for archived persona design.*

---

## Design overview

The experiment addresses two questions in sequence:

**Question 1 (calibration)**: Which prompt condition and model scale produces AI ratings
closest to the human expert panel's raw mean across 12 V-Dem indicators?

**Question 2 (replacement)**: Using the best-calibrated condition, how many human coders
can AI replace before the raw panel mean shifts detectably?

The design is a **4 × 4 calibration experiment** (4 prompt conditions × 4 model scales)
followed by a **sequential replacement experiment** using the best-performing condition(s).

---

## Part 1: Calibration experiment

### Conditions

| Label | Prompt content | New element |
|---|---|---|
| Codebook-only | Global framing + codebook text | — |
| Evidence | + raw section text | Structured source evidence |
| Anonymized | + anonymized section text | Country-identity stripped |
| Fine-tuned | Anonymized text → fine-tuned 70B | Calibration in weights |

Each condition is additive: Condition 2 adds evidence to Condition 1; Condition 3 adds
anonymization to Condition 2; Condition 4 replaces few-shot with fine-tuned weights.

### Models

Claude Sonnet 4.6, Llama 405B Instruct, Llama 3.3 70B Instruct, Llama 3.2 9B Instruct.
Conditions 1–3 run on all four models. Condition 4 runs on Llama 70B (primary) and
optionally Llama 9B (lower bound on scale × fine-tuning interaction).

### Country-year pool (calibration)

Primary: 2020 (~150–170 country-year-indicator cells per indicator with v15 raw panel
means). Expand to 2018–2020 if per-condition MAD estimates are unstable at N=150.

### Outcome

**MAD**: `mean(|AI_rating − raw_panel_mean|)` across pool, per condition × model ×
indicator. Report as a table: rows = condition × model, columns = indicators (+ mean
across indicators). Secondary: signed deviation by democracy quintile.

### What each comparison tells you

| Comparison | What it isolates |
|---|---|
| Condition 1 vs. 2 (same model) | Marginal value of source evidence |
| Condition 2 vs. 3 (same model) | Marginal value of anonymization |
| Condition 3 vs. 4 (70B) | Marginal value of fine-tuning over few-shot |
| Models (same condition) | Scale effects on calibration |
| Quintile signed deviation | Regime-type anchoring bias |

---

## Part 2: Replacement experiment

### Design

Pool: well-formed panels (≥8 distinct coders) from 2018–2022. Stratify by democracy
quintile (10 country-years per quintile = 50 total). Lock to `data/processed/cy_pool.csv`
before running any LLM calls.

For each country-year (cy), k ∈ {1, 2, 3}, and bootstrap draw b ∈ {1,...,500}:

1. Randomly draw k human coders to remove from the panel
2. Substitute k AI ratings from the best Stage 1 condition (one rating per model)
3. Compute `mean_aug_k = mean(remaining_human_ratings + k_AI_ratings)`
4. Record `divergence_k = |mean_aug_k − mean_full|`

Report divergence curve: mean divergence by k with 2.5–97.5% bootstrap CI, averaged
across the 50 country-years and stratified by democracy quintile.

**Replacement tolerance** (primary finding): the k at which the lower bound of the 95%
CI on divergence_k first exceeds the pre-registered threshold. Pre-register the
threshold value and its justification before running.

### AI panel member assignment

For k > 1, AI ratings come from k distinct models. Pre-register the assignment rule:

| k | AI panel members used |
|---|---|
| 1 | Best Stage 1 model |
| 2 | Best + 2nd-best Stage 1 models |
| 3 | Best + 2nd-best + 3rd-best Stage 1 models |

"Best" defined by lowest overall MAD in Stage 1. If a model performs poorly in Stage 1,
it is excluded from the replacement experiment — this is one motivation for running Stage
1 first and locking the Stage 2 pool only after Stage 1 results are in hand.

### Coder removal strategy

**Primary**: random removal (uniform draw). Expected-case effect under realistic
deployment where the researcher does not know individual coder quality.

**Bounds** (secondary):
- Worst-first: remove k coders with highest individual deviation from panel mean
- Best-first: remove k coders with lowest individual deviation from panel mean

Report bounds as supplementary; the random-removal curve is the main result.

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

| Variable | Definition | Stage |
|---|---|---|
| MAD | `mean(\|AI_rating − raw_mean\|)` across pool | Calibration primary |
| Signed deviation | `mean(AI_rating − raw_mean)` | Calibration diagnostic |
| Quintile signed dev | Signed dev by democracy quintile | Compression diagnostic |
| divergence_k | `\|mean_aug_k − mean_full\|` | Replacement primary |
| Replacement tolerance | k at which 95% CI lower bound > threshold | Replacement finding |
| Augmentation gain | `\|mean_aug_k − mean_ref\| < \|mean_thin − mean_ref\|`? | Augmentation |

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
- [ ] Year(s): 2020 primary; specify if expanding to 2018–2020
- [ ] Minimum ratings per country-indicator for inclusion
- [ ] Final N per condition (confirm before running)

**Replacement pool**
- [ ] Eligibility: ≥8 distinct coders, year range 2018–2022
- [ ] Stratification: 10 country-years per quintile; confirm quintile cutoffs from v15 θ
- [ ] Pool saved to `data/processed/cy_pool.csv`
- [ ] AI panel member assignment rule for k = 2, 3 (model priority order)

**Fine-tuning**
- [ ] Training window: 2010–2015 (confirm no country-year overlap with calibration/replacement pools)
- [ ] Training set saved to `data/processed/training_set.csv`
- [ ] Hyperparameters: LoRA rank, alpha, learning rate, batch size, epochs, base model commit hash

**Models**
- [ ] Claude Sonnet 4.6 API version pinned
- [ ] Llama 405B commit hash (HuggingFace)
- [ ] Llama 3.3 70B commit hash
- [ ] Llama 3.2 9B commit hash

**Replacement experiment**
- [ ] Divergence threshold value and justification (in rating points on 0–4 scale)
- [ ] Bootstrap B = 500; CI = 2.5–97.5%
- [ ] Coder removal: random primary; worst/best-first as bounds
- [ ] k values: 1, 2, 3

**Persona exploratory**
- [ ] Strict and lenient framing text locked
- [ ] Indicator subset for persona test specified

**Anonymization**
- [ ] Anonymization agent system prompt locked
- [ ] Anonymization applied consistently to both few-shot examples and evaluation text
