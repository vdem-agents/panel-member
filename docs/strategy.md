# Panel Member: Research Strategy

*Updated July 2026. IRT dropped — panel-mean deviation test replaces the sequential
replacement experiment. Prompt engineering expanded to four stages. Raw panel means
replace calibration-weighted means (no empirical difference in practice). Persona
prompting retained as exploratory condition; see `notes/persona-prompting-design-archive.md`.*

## Research questions

1. Which prompt condition and model scale produces AI ratings closest to the human expert
   panel's raw mean across 12 V-Dem indicators?
2. How many human coders can AI replace before the raw panel mean shifts detectably?

---

## Stage 1: Prompt engineering calibration

### The four conditions

**Condition 1 — Codebook-only**: global comparative framing + V-Dem codebook question
text + response scale + output instruction. No source text. Measures the baseline signal
from the model's pretraining alone. If frontier and large open-weights models already
produce well-calibrated ratings from codebook text, the evidence pipeline adds cost without
commensurate benefit.

**Condition 2 — Evidence packets**: adds section-extracted State Dept and Freedom House
text. Same prompt structure as bridge-coder Stage 1. Measures what structured primary
source text adds over codebook-only.

**Condition 3 — Anonymized summaries**: an LLM agent rewrites the extracted sections to
remove country-identifying information (country name, named organizations, leaders,
recognizable events) before the coding call. Motivated by the regime-type anchoring bias
observed in bridge-coder preliminary results for 2020: models appear to use country
identity as a shortcut rather than reasoning from evidence. Anonymization forces the coding
model to reason from described political conditions alone.

**Condition 4 — Fine-tuning**: QLoRA fine-tune on (anonymized section text, raw panel
mean) pairs. Training text uses the same anonymization pipeline as Condition 3, so the
fine-tuned model's inference distribution matches its training distribution. Measures what
fine-tuning adds beyond the best few-shot condition.

### Country-year pool (calibration)

2020 as the primary calibration year (broadest coverage, overlap with bridge-coder
preliminary analysis). Expand to 2018–2020 if a larger evaluation set is needed for
reliable per-condition MAD estimates. Pool: all countries with raw panel mean available
in V-Dem v15 coder-level data for each indicator in the target year(s).

### Models

| Model | Scale | Platform | Conditions run |
|---|---|---|---|
| Claude Sonnet 4.6 | Frontier | Claude API | 1, 2, 3 |
| Llama 405B Instruct | 405B open | GW 8×A100 80GB | 1, 2, 3 |
| Llama 3.3 70B Instruct | 70B open | GW A100 80GB | 1, 2, 3 |
| Llama 3.2 9B Instruct | 9B open | GW V100 16GB | 1, 2, 3 |
| Llama 3.3 70B (fine-tuned) | 70B ft | GW A100 80GB | 4 |

Fine-tuning (Condition 4) runs on Llama 70B. If a model performs poorly in Conditions
1–3, it is still informative for the scale-effects comparison but may not be used as an
AI panel member in Stage 2. Which models advance to the replacement experiment depends
on Stage 1 results.

### Outcome

**MAD**: `mean(|AI_rating − raw_panel_mean|)` across pool, per condition × model ×
indicator. Primary calibration metric.

**Signed deviation by democracy quintile**: diagnostic for compression (systematic
tendency to rate autocracies too high or democracies too low). Motivated by the
bridge-coder preliminary finding that few-shot prompting with country-identified evidence
exhibits this pattern.

---

## Stage 2: Replacement experiment

### Design

Take well-formed panels (≥8 distinct coders) from the evaluation window. For each panel
and k = 1, 2, 3:

1. Randomly draw k coders to remove from the human panel
2. Substitute AI ratings from the best Stage 1 condition for the removed coders
3. Compute the AI-augmented panel mean
4. Compare to full-panel mean: `divergence_k = |mean_aug_k − mean_full|`

Bootstrap across removal draws (B = 500). Report divergence curve by k (mean + 95% CI).
The **replacement tolerance** is the k at which the lower bound of the 95% CI on
divergence_k first exceeds a pre-specified threshold (to be pre-registered before running).

### Country-year pool (replacement)

Well-formed panels with ≥8 distinct coders in 2018–2022. Stratified by democracy quintile
(10 country-years per quintile = 50 total). Lock to `data/processed/cy_pool.csv` before
running any LLM calls.

### AI panel member variation

Three sources of distinct AI panel members, used in separate analyses:

**Primary — Model variation**: each model is a distinct AI panel member. For k = 2
replacements, two different models provide the two AI ratings (e.g., Claude + Llama 70B).
For k = 3, three models. This is methodologically grounded: each model has genuinely
different pretraining and produces genuinely different ratings. The constraint is that the
number of available well-calibrated models caps the practical k.

**Exploratory — Persona variation**: 2 conditions (strict framing / lenient framing) added
to the best-performing model. Pre-registered as exploratory. Expected to be null or weak
per the archived persona design evidence (see `notes/persona-prompting-design-archive.md`
and Morocho et al. 2026). Included because: (a) it would be a cheap source of additional
distinct AI panel members if effects are systematic, and (b) the test is informative
regardless of outcome.

**Sensitivity — Temperature variation**: re-run the best model at temperature 0.7 on
the evaluation pool. Reports the spread of ratings as a measure of model uncertainty
rather than as distinct panel members. Not used in the main replacement analysis.

### Coder removal strategy

**Primary**: random removal (uniform draw over panel coders). Expected-case replacement
effect under realistic augmentation where the deploying researcher does not know which
human coders are best.

**Bounds**: worst-first removal (remove k coders with highest individual deviation from
panel mean) and best-first removal (remove k coders with lowest individual deviation).
Reports worst-case and best-case bounds on the divergence curve.

---

## Stage 3: Augmentation of attrited panels (secondary)

Apply AI augmentation to panels degraded by post-2013 coder attrition. For countries
with well-formed panels in 2015 (≥8 coders) that have thin panels by 2022 (≤5 coders):

- `mean_thin` = raw mean of the 2022 thin human panel
- `mean_aug` = raw mean of 2022 thin panel + k AI ratings (k = 1, 2)
- `mean_ref` = raw mean of the 2015 thick panel (treated as reference)

Does AI augmentation move the panel mean toward the historical thick-panel reference?
This conflates panel thinning with temporal democratic change; frame as an application
illustration, not a clean validation. Report the limitation explicitly.

---

## Source documents and pipeline

Both stages use section extraction (State Dept + Freedom House), shared with the
bridge-coder pipeline. No ChromaDB. The anonymization agent (Conditions 3 and 4) is a
new LLM call inserted between section extraction and the coding model.

### Source window

| Stage | Years | Notes |
|---|---|---|
| Calibration | 2020 primary; 2018–2020 expanded | Overlap with bridge-coder preliminary |
| Replacement | 2018–2022 | Requires ≥8 coders per panel |
| Fine-tuning training | 2010–2015 | Held out from all evaluation pools |
| Augmentation (attrition) | 2015 (ref) + 2022 (thin) | Post-2013 attrition window |
| Deployment (historical) | 1975–1989 | FH from 1972; State Dept from 1977 |

---

## Compute

| Task | Platform | Est. cost / time |
|---|---|---|
| Calibration, Claude (3 cond × 12 ind × ~150 CY) | Claude API | ~$80 |
| Calibration, Llama 405B (3 cond × 12 ind × ~150 CY) | GW 8×A100 | Free, ~4–6 hr |
| Calibration, Llama 70B (3 cond × 12 ind × ~150 CY) | GW A100 | Free, ~2–3 hr |
| Calibration, Llama 9B (3 cond × 12 ind × ~150 CY) | GW V100 | Free, ~1 hr |
| Fine-tuning 70B (200–500 pairs × 12 ind, QLoRA 4-bit) | GW A100 80GB | Free, ~12–24 hr |
| Replacement experiment (best model, k=1–3, B=500) | Claude API or GW | ~$30 or free |

Llama 405B requires the GW 8×A100 80GB nodes (640GB aggregate; 405B at 4-bit needs
~200GB). Llama 70B and fine-tuning fit on a single A100 80GB. Llama 9B fits on any
V100 16GB node.

---

## Key open questions

- [ ] Lock calibration pool: year(s), minimum ratings per country-indicator, confirmed N
- [ ] Lock fine-tuning training window and confirm no overlap with evaluation pools
- [ ] Pre-register divergence threshold for replacement experiment (in raw rating points)
- [ ] Confirm Llama 405B availability on GW Pegasus (may require allocation request)
- [ ] Decide scope of persona exploratory condition: all 12 indicators or focused subset?
- [ ] Decide whether fine-tuning runs on 9B as well as 70B (lower bound on scale effects)
