# Research Strategy

This study uses a three-condition identification design to separate two distinct sources
of bias in AI annotation: reliance on pretraining knowledge rather than the provided
evidence, and the use of syntactic cues such as country names and named institutions to
activate prior beliefs rather than reasoning from what the text reports. Using V-Dem
expert coding as the application, we assess how much each source contributes to
calibration quality and what this implies for the reliability of AI annotation across
different information environments.

## Research questions

1. How much does each information source — pretrained knowledge, structured source
   evidence, and country identity — contribute to AI calibration quality relative to
   the human expert panel baseline?
2. Does the contribution of source evidence degrade as source coverage weakens, and
   what does this imply for the generalizability of AI annotation across the full
   indicator set?
3. Under the best-performing prompt condition and model, does adding one AI rating to
   a thin human panel shift the raw panel mean detectably?

## Stage 1: Prompt engineering

### The three conditions

**Condition 1 — Codebook-only**: global comparative framing + V-Dem codebook question
text + response scale + output instruction. No source text. Measures the baseline signal
from the model's pretraining alone. If frontier and large open-weights models already
produce well-calibrated ratings from codebook text, the evidence pipeline adds cost without
commensurate benefit.

**Condition 2 — Evidence packets**: adds section-extracted State Dept and Freedom House
text plus few-shot calibration examples (one per ordinal level 0–4, globally distributed).
Measures what structured primary source text and calibration anchors add over codebook-only.

**Condition 3 — Anonymized summaries**: an LLM agent rewrites the extracted sections to
remove country-identifying information (country name, named organizations, leaders,
recognizable events) before the coding call. Few-shot examples are also anonymized.
Motivated by the regime-type anchoring bias observed in bridge-coder preliminary results
for 2020: models appear to use country identity as a shortcut rather than reasoning from
evidence. Anonymization forces the coding model to reason from described political
conditions alone.

### The models

Three base models run all three prompt conditions. Two fine-tuned variants of Llama 70B
run the corresponding condition only, with calibration embedded in the adapter weights
rather than supplied via few-shot examples.

| Model | Scale | Platform |
|---|---|---|
| Llama 3.3 70B (fine-tuned, evidence) | 70B ft | GW GH200 (superChip) |
| Llama 3.3 70B (fine-tuned, anonymized) | 70B ft | GW GH200 (superChip) |
| Llama 405B Instruct | 405B open | GW 4-8x A100 80GB |
| Llama 3.3 70B Instruct | 70B open | GW GH200 (superChip) |
| Llama 3.2 9B Instruct | 9B open | GW GH200 (superChip) |

Fine-tuning uses QLoRA on (anonymized section text, individual coder rating) pairs from
V-Dem v15 — one row per coder per country-year-indicator (CYI). Training window: 2016–2018.
Training covers all 206 mapped Type C indicators. Primary
evaluation: LOO MAE against panel mean on all ~205 evaluation indicators. Secondary:
exact match rate and adjacent-category agreement.

### Country-year pool (calibration)

**2019** as the primary evaluation year — clean one-year temporal holdout after the
2016–2018 training window, full panels, no exogenous anomalies. 2020 is avoided as
primary: COVID-19 emergency restrictions distort civil society, media, and judicial
indicators and make the human panel means noisier targets than usual.

Secondary robustness: **2023** — best-performing model only. Falls outside the
2016–2018 training window; 2023 is the last year of intact State Department and Freedom
House reporting before the 2024 format restructuring, making it the natural ceiling for
the current pipeline. Source documents already ingested and confirmed clean (all 16 SD
sections present in 193 files; all 7 FH sections present in 210 files). Panel sizes by
2023 are also smaller on average due to continued post-2013 attrition, making this a
harder test of the replacement scenario than 2022 would have been.

Pool: all countries with raw panel mean available in V-Dem v15 coder-level data for
each indicator in the target year.

If a base model performs poorly across all three conditions, it is still informative for
the scale-effects comparison but may not advance to Stage 2. Which models are used in the
replacement experiment depends on Stage 1 results.

### Outcome

**LOO MAE** (primary): for each CYI, compare `|AI_rating − panel_mean|` against the human
baseline `mean(|rating_i − mean(panel \ {i})|)` — the typical error of a held-out human
coder against the rest of their panel. Bootstrap at the CYI level (B=500) for CIs and a
paired significance test. Primary display: forest plot, indicators as rows grouped by
module, paired AI vs. human LOO MAE estimates (or difference centered on zero).
Supplementary: model × indicator table (5 models × all evaluation indicators, with coverage tier noted).

**Exact match rate and adjacent-category agreement** (secondary): proportion of AI ratings
equal to, or within ±1 of, the rounded panel mean. Readable calibration summaries for a
mixed audience.

**Signed deviation by quintile** (diagnostic): `mean(AI_rating − panel_mean)` by
v2x_polyarchy quintile. The human baseline is ~0 by construction; any systematic AI
deviation reveals directional compression bias — rating autocracies too generously or
democracies too harshly. Report as a figure. See `notes/evaluation-metrics.md`.

## Stage 2: Coverage-tier generalization (embedded in main analysis)

### Design

The fine-tuned Llama 70B adapter is trained on all 206 mapped Type C indicators,
spanning all coverage tiers. Coverage tier is a within-study moderating variable at
inference — no separate held-out training split required.

Coverage tier enters as a moderating variable in the main results. The gradient from
strong to weak coverage indicators tests whether calibration quality degrades as source
evidence weakens — and by how much.

### Outcome

| Comparison | What it shows |
|---|---|
| LOO MAE by coverage tier | Whether fine-tuning generalizes to weaker-evidence indicators |
| Fine-tuned vs. few-shot (same coverage tier) | What fine-tuning adds over prompting alone |
| Observability × coverage tier interaction | Where generalization is easiest / hardest |

**Primary finding**: if the strong → weak coverage gradient in LOO MAE is shallow, the
result supports a scalable V-Dem AI coder applicable across the full ~216 Type C indicator
set, motivating application beyond the training distribution.

## Stage 3: Integration robustness (secondary / supplemental)

### Design

k=1 replacement check only. For all country-years in the 2019 evaluation pool with
≥8 distinct coders, add one AI rating from the best-calibrated model and compare the
AI-augmented panel mean to the full human panel mean. Bootstrap B=500. Report mean
divergence ± 95% CI. No pool size cap — AI ratings for these CYs already exist from
the calibration run, so there is no cost to using the full eligible set.

k=1 is the primary and most realistic deployment scenario. k=2 and k=3 are not part of
the registered design; whether to add them as secondary analyses depends on Stage 1
results and is a post-hoc decision.

### Coder removal strategy

Random removal (uniform draw) only. Worst/best-first bounds dropped given secondary
status — keep the analysis simple.

## Stage 4: Augmentation of attrited panels (secondary)

Apply AI augmentation to panels degraded by post-2013 coder attrition. For countries
with well-formed panels in 2015 (≥8 coders) that have thin panels by 2022 (≤5 coders):

- `mean_thin` = raw mean of the 2022 thin human panel
- `mean_aug` = raw mean of 2022 thin panel + k AI ratings (k = 1, 2)
- `mean_ref` = raw mean of the 2015 thick panel (treated as reference)

Does AI augmentation move the panel mean toward the historical thick-panel reference?
This conflates panel thinning with temporal democratic change; frame as an application
illustration, not a clean validation. Report the limitation explicitly.

## Source documents and pipeline

Both stages use section extraction (State Dept + Freedom House), shared with the
bridge-coder pipeline. No ChromaDB. The anonymization agent (Conditions 3 and 4) is a
new LLM call inserted between section extraction and the coding model.

### Source window

| Stage | Years | Notes |
|---|---|---|
| Calibration (primary) | 2019 | Clean holdout; full panels; no COVID anomaly |
| Robustness check | 2023 | Best model only; outside training window; last year of intact SD/FH reporting |
| Replacement (k=1 check) | 2019 | All ≥8-coder CYs from evaluation pool; no extra ingestion needed |
| Fine-tuning training | 2016–2018 | Post-lateral-coder; pre-attrition; 6 years |
| Augmentation (attrition) | 2015 (ref) + 2022 (thin) | Post-2013 attrition window |
| Deployment (historical) | 1975–1989 | FH from 1972; State Dept from 1977 |

## Compute

Full estimates are in `notes/hpc-execution-strategy.md`. Summary for the two scenarios:

**Primary (all ~205 indicators, ~32,800 calls per condition per model)**

| Model | Total (3 conditions) | Notes |
|---|---|---|
| Llama 405B | ~20–38 hrs | 4–8× A100; binding HPC constraint |
| Llama 70B base | ~10–20 hrs | 1× GH200 preferred |
| Llama 9B | ~5–10 hrs | 1× GH200 or V100 |
| FT-anon 70B | ~4–8 hrs | Anonymized condition only |
| Fine-tuning 70B (×2 runs) | ~75–80 hrs each | QLoRA, 2016–2018, GH200 |

**Fallback (~60–70 indicators, ~11,200 calls per condition per model)**

| Model | Total (3 conditions) | Notes |
|---|---|---|
| Llama 405B | ~8–15 hrs | Fits comfortably in one overnight job |
| Llama 70B base | ~4–8 hrs | |
| Llama 9B | ~2–4 hrs | |
| FT-anon 70B | ~1.5–3 hrs | |

All Llama models run on Pegasus via TRES resource requests.
See `notes/hpc-execution-strategy.md` for confirmed partition names, GRES strings,
per-condition breakdown, and full run sequence.

## Key open questions

- [ ] Lock evaluation pool: year(s), minimum ratings per country-indicator, confirmed N
- [ ] Verify section mappings and codebook text for all ~205 indicators before any inference runs
- [ ] Qualitative section-mapping review: read sample report sections to confirm
      section-to-indicator assignments are evidentiarily relevant, not just thematically
      adjacent; update `config/indicator_sections.yaml` to cover all evaluation indicators;
      reference `initial-exploration/explore-indicators/02-indicator-selection.html`
- [ ] Lock fine-tuning training window: 2016–2018 (source document availability — SD and FH
      reliably scraped from 2016; ~1.03M coder-CYI examples sufficient; captures post-Arab
      Spring democratic backsliding period; no overlap with 2019 test year or 2023 robustness check)
- [ ] Confirm Llama 405B availability on GW Pegasus (may require allocation request)
- [x] Persona prompting: post-hoc illustration only, run on best model after main results
      are in. Not a registered condition. If persona framing (strict / lenient) produces
      reliable directional shifts, that motivates a follow-on paper on synthetic panel
      diversity — it does not affect the k=1 replacement check in this paper.
- [ ] Decide whether fine-tuning runs on 9B as well as 70B (lower bound on scale ×
      generalization interaction)
