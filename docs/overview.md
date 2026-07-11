# Panel Member: Project Overview

*Quick framing revision July 2026. Prose to be refined; see GitHub issue #7.*

---

## The question

When large language models are used to code political texts, what information are they
actually drawing on — pretrained political knowledge, structured source evidence, or
country identity — and how much does each source contribute to calibration quality?

This is not a question the existing AI annotation literature has answered cleanly.
Studies typically show that LLM outputs correlate with human expert ratings, but
correlation against a benchmark does not tell you whether the model is reading the
presented text or drawing on prior knowledge of the subject. Without that
decomposition, LLM-based political measurement is difficult to trust in novel,
out-of-distribution, or low-information settings.

The study answers the question using V-Dem expert coding as the application, because
V-Dem's measurement model provides an unusually well-characterized benchmark: the IRT
posterior identifies how much information each additional coder contributes, and
leave-one-out MAE against the human panel provides a theoretically grounded performance
standard.

---

## Why this question matters for V-Dem now

V-Dem estimates country-year democracy scores via an IRT model that pools ordinal
ratings from multiple expert coders. Post-2013 coder cohorts are aging out without
replacement: annual attrition of 45–133 coders with near-zero new recruitment has
reduced the median panel from ~11 in the 2010s to ~5.8 by 2024, declining at roughly
0.5 coders per year. At small panel sizes, the IRT posterior is poorly identified and
increasingly sensitive to individual coder threshold idiosyncrasies — exactly the
problem a well-calibrated AI coder could address.

This is the paper's applied contribution: evidence-based guidance on whether and how
AI ratings can augment contemporary thin panels without detectably shifting the raw
panel mean. Historical sparse panels (pre-1990) and chronically thin-coverage countries
(~35 small states) are additional potential use cases but are not what the study
validates.

---

## The identification strategy

The three prompt conditions are not robustness checks — they are an identification
design:

| Comparison | What it isolates |
|---|---|
| Codebook-only → Evidence | What structured primary source text adds over pretrained knowledge alone |
| Evidence → Anonymized | How much country identity (not text) drives ratings — regime-type anchoring |
| Anonymized (base 70B) → Fine-tuned 70B | What embedding calibration in weights adds over in-context few-shot examples |
| Models (same condition) | Scale effects on each information source |

The codebook-only condition is especially important: if frontier and large open-weights
models already produce well-calibrated ratings from codebook text alone, the evidence
pipeline is unnecessary and the source of calibration is entirely pretrained knowledge.
If evidence adds substantially, the model is reading the text. If anonymization helps
further, country-identity shortcuts were inflating apparent calibration.

---

## Why the metrics matter

The primary metric is LOO MAE against the human panel baseline — the typical error of
a held-out human coder against the rest of their panel. This answers the question "is
the AI performing within the range of normal human disagreement?" Correlation with
expert ratings, the most common metric in the existing literature, cannot detect
systematic scale compression, directional bias, or whether AI accuracy varies across
the democracy distribution. Signed deviation by democracy quintile is the complementary
diagnostic: if AI ratings anchor on country identity, the signature is positive deviation
in low-quintile autocracies (rated too high) and negative deviation in high-quintile
democracies (rated too low).

---

## Design summary

**Conditions (3)**: codebook-only; evidence (raw section text + few-shot calibration
examples); anonymized (country identity stripped + anonymized few-shot examples).

**Models (5)**: Claude Sonnet 4.6 (frontier API); Llama 405B, 70B, 9B (open weights,
GW Pegasus); Llama 70B fine-tuned on V-Dem v15 coder ratings 2013–2018 (~174 strong +
partial coverage Type C indicators; ~1–2M training examples).

**Evaluation**: 2019 (primary); 2022 (robustness check, best model only). LOO MAE with
bootstrap CIs; signed deviation by quintile; exact match and adjacent-category agreement.
Coverage tier (strong / partial / weak) as a moderating variable in the results.

**Replacement check (supplemental)**: for all 2019 CYIs with ≥8 coders, `k=1` —
does adding one AI rating shift the raw panel mean detectably?

---

## Contribution claim

**Primary (NLP / AI annotation)**: a decomposition of what LLMs draw on when coding
political texts, using a three-condition identification design. Applicable beyond V-Dem
to any structured expert annotation task with multi-annotator panels.

**Primary (political science)**: which prompt strategy and model scale produces AI
ratings that fall within the range of human expert disagreement for V-Dem democracy
indicators, and does calibration degrade across the strong → weak source-coverage
gradient?

**Applied**: evidence-based guidance on whether AI augmentation of contemporary thin
panels is safe — whether the raw panel mean shifts detectably under `k=1` substitution.

---

## Paper target

APSR. Bridge-coder companion paper (Political Analysis target) addresses a different
problem: linking disconnected national panels via IRT threshold calibration.
