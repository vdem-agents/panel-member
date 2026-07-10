# Panel Member: Research Strategy

*Updated July 2026. IRT dropped — panel-mean deviation test replaces the sequential
replacement experiment. Three prompt conditions across five models. Raw panel means replace
calibration-weighted means. Training on all strong + partial Type C indicators (~174);
evaluation on 25–30 selected indicators spanning all coverage tiers. Persona prompting
retained as exploratory condition; see `notes/persona-prompting-design-archive.md`.*

## Research questions

1. Which prompt condition and model scale produces AI ratings closest to the human expert
   panel's raw mean across the 25–30 evaluation indicators?
2. Does LOO MAE degrade as source-coverage tier weakens — and if not, how many human
   coders can AI replace before the raw panel mean shifts detectably?

---

## Stage 1: Prompt engineering calibration

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

### The five models

All three conditions run on four base models. Fine-tuned Llama 70B is a fifth model that
uses the anonymized prompt format without the few-shot block; calibration is embedded in
the adapter weights.

| Model | Scale | Platform | Conditions |
|---|---|---|---|
| Claude Sonnet 4.6 | Frontier | Claude API | Codebook, Evidence, Anonymized |
| Llama 405B Instruct | 405B open | GW 8×A100 80GB | Codebook, Evidence, Anonymized |
| Llama 3.3 70B Instruct | 70B open | GW A100 80GB | Codebook, Evidence, Anonymized |
| Llama 3.2 9B Instruct | 9B open | GW V100 16GB | Codebook, Evidence, Anonymized |
| Llama 3.3 70B (fine-tuned) | 70B ft | GW A100 80GB | Anonymized format, no few-shot |

Fine-tuning uses QLoRA on (anonymized section text, individual coder rating) pairs from
V-Dem v15 — one row per coder per CYI, not panel means. Training window: 2013–2018.
Training covers all strong + partial coverage Type C indicators (~174 indicators). Primary
evaluation: LOO MAE against panel mean on the 25–30 evaluation indicators. Secondary:
exact match rate and adjacent-category agreement.

### Country-year pool (calibration)

**2019** as the primary calibration year — clean one-year temporal holdout after the
2013–2018 training window, full panels, no exogenous anomalies. 2020 is avoided as
primary: COVID-19 emergency restrictions distort civil society, media, and judicial
indicators and make the human panel means noisier targets than usual.

Secondary robustness: **2024** — best-performing model only. Tests generalization to
the thin-panel recent years that are the paper's primary deployment target. Panel size
~4,421 coders by 2024 (vs. 8,212 in 2018); frame as deployment simulation, not
primary validation. Addresses the reviewer question "does it work for recent years?"
while tying the answer directly to the paper's motivation.

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
Supplementary: model × indicator table (5 models × 25–30 indicators, with coverage tier noted).

**Exact match rate and adjacent-category agreement** (secondary): proportion of AI ratings
equal to, or within ±1 of, the rounded panel mean. Readable calibration summaries for a
mixed audience.

**Signed deviation by quintile** (diagnostic): `mean(AI_rating − panel_mean)` by
v2x_polyarchy quintile. The human baseline is ~0 by construction; any systematic AI
deviation reveals directional compression bias — rating autocracies too generously or
democracies too harshly. Report as a figure. See `notes/evaluation-metrics.md`.

---

## Stage 2: Coverage-tier generalization (embedded in main analysis)

### Design

The fine-tuned Llama 70B adapter is trained on all strong + partial coverage Type C
indicators (~174 indicators). The 25–30 evaluation indicators are selected to span all
three source-coverage tiers (strong, partial, weak), providing a within-study
generalization test without requiring a separate held-out training split.

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

---

## Stage 3: Integration robustness (secondary / supplemental)

### Design

k=1 replacement check only. For all country-years in the 2019 calibration pool with
≥8 distinct coders, add one AI rating from the best-calibrated model and compare the
AI-augmented panel mean to the full human panel mean. Bootstrap B=500. Report mean
divergence ± 95% CI. No pool size cap — AI ratings for these CYs already exist from
the calibration run, so there is no cost to using the full eligible set.

k=2 and k=3 are contingent on persona exploratory results: if persona prompting on the
best fine-tuned model produces reliably distinct ratings, those additional draws could
serve as distinct AI panel members. The k=1 check is the primary and most realistic
deployment scenario; k=2/k=3 would be added as secondary if persona results support them.

### Coder removal strategy

Random removal (uniform draw) only. Worst/best-first bounds dropped given secondary
status — keep the analysis simple.

---

## Stage 4: Augmentation of attrited panels (secondary)

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
| Calibration (primary) | 2019 | Clean holdout; full panels; no COVID anomaly |
| Calibration (robustness) | 2020 | Best model only; COVID stress test |
| Deployment robustness | 2024 | Best model only; thin panels; reviewer generalization check |
| Replacement (k=1 check) | 2019 | All ≥8-coder CYs from calibration pool; no extra ingestion needed |
| Fine-tuning training | 2013–2018 | Post-lateral-coder; pre-attrition; 6 years |
| Augmentation (attrition) | 2015 (ref) + 2022 (thin) | Post-2013 attrition window |
| Deployment (historical) | 1975–1989 | FH from 1972; State Dept from 1977 |

---

## Compute

| Task | Platform | Est. cost / time |
|---|---|---|
| Calibration, Claude (3 cond × ~28 ind × ~180 CY) | Claude API (laptop) | ~$600–800 |
| Calibration, Llama 405B (3 cond × ~28 ind × ~180 CY) | Pegasus `gpu`, `gpu:a100:4` | Free, ~10–14 hr |
| Calibration, Llama 70B (3 cond × ~28 ind × ~180 CY) | Pegasus `gpu`, `gpu:a100:1` | Free, ~4–6 hr |
| Calibration, Llama 9B (3 cond × ~28 ind × ~180 CY) | Pegasus `gpu`, `gpu:v100:1` | Free, ~2 hr |
| Fine-tuning 70B (~174 ind, QLoRA 4-bit, 2013–2018) | Pegasus `gpu`, `gpu:a100:1` | Free, ~10–18 hr |
| Inference, fine-tuned 70B (~28 ind × ~180 CY) | Pegasus `gpu`, `gpu:a100:1` | Free, ~4 hr |
| Replacement experiment (best model, k=1, B=500) | Claude API or Pegasus | ~$30 or free |

Claude runs from laptop (no HPC queue, no internet firewall uncertainty). All Llama
models run on Pegasus using TRES resource requests. Llama 405B requires 4× A100 80GB
(320 GB; 405B at 4-bit needs ~200 GB). Llama 70B and fine-tuning fit on a single A100
80GB. Llama 9B fits on any V100 16GB node. See `notes/hpc-sequencing-strategy.md` for
confirmed partition names, GRES strings, and run sequence.

---

## Key open questions

- [ ] Lock calibration pool: year(s), minimum ratings per country-indicator, confirmed N
- [ ] Select and lock 25–30 evaluation indicators (3–4 per module, spanning coverage
      tiers); verify section mappings and codebook text before any inference runs
- [ ] Qualitative section-mapping review: read sample report sections to confirm
      section-to-indicator assignments are evidentiarily relevant, not just thematically
      adjacent; update `config/indicator_sections.yaml` to cover all evaluation indicators;
      reference `initial-exploration/explore-indicators/02-indicator-selection.html`
- [ ] Lock fine-tuning training window: 2013–2018 (post-lateral-coder drop; pre-attrition;
      no overlap with 2019 test year or 2024 deployment check)
- [ ] Confirm Llama 405B availability on GW Pegasus (may require allocation request)
- [x] Decide scope of persona exploratory condition: **retained**. Narrow 2-condition test
      (strict / lenient framing) on the best fine-tuned model. If persona shifts produce
      reliable, directional rating changes, k=2/k=3 from persona draws becomes viable.
- [ ] Decide whether fine-tuning runs on 9B as well as 70B (lower bound on scale ×
      generalization interaction)
