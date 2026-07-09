# Panel Member: Project Overview

## The problem

V-Dem estimates country-year democracy scores via an IRT model that pools ordinal ratings
from multiple expert coders. The reliability of those estimates depends directly on panel
size: with 13 coders, the posterior is well-identified and robust to individual outliers;
with 2 coders, a single high-reliability coder anchors the estimate.

Analysis of V-Dem v15 (corrected for a row-vs-distinct-coder counting issue) reveals three
distinct thin-panel pathologies:

### Pathology 1: Historical sparsity (the primary target)

59% of pre-1990 country-year observations have ≤3 distinct coders. This is structural:
V-Dem's retrospective coding relied on 1–2 country specialists who coded entire national
histories back to 1789. It affects major countries (Germany, France, UK all have 100+ years
of 2-coder panels) as much as small ones.

At n=1–2, the IRT posterior ≈ the hierarchical prior. Pre-1900 cross-national comparisons
are largely comparing the model's prior beliefs about countries at given development levels
in given regions — not the data. The core historical coders are also, by construction, the
most regionally immersed coders in the pool: a single expert coding 200 years of history
produces an internally coherent time series, but one whose threshold placement relative to
the global mean is poorly identified.

Practical deployment window: roughly 1975–1989, where Freedom House (from 1972) and State
Department reports (from late 1970s) provide evidence packets.

### Pathology 2: Chronic thin coverage (~35 contemporary countries)

About 35 countries have mean panel size < 8 distinct coders in 2010–2024: predominantly
small island states, small African states, and hard-access authoritarian regimes. Haiti,
Chad, Guinea-Bissau, Solomon Islands, Vanuatu are the clearest cases.

### Pathology 3: Leading-edge attrition (growing gap)

The post-2013 cohort of coders is aging out without replacement. Annual attrition of
45–133 coders/year with essentially 0 new coders added who code only recent years. By
2024, median panel size (~5.8) has returned to pre-2005 levels. This is operationally the
most urgent gap: universal across countries, growing at ~0.5 coders/year.

---

## The approach

The paper tests whether AI-generated ratings can substitute for human expert coders in
V-Dem's measurement system, and whether a fine-tuned model generalizes to indicators it
was not trained on. The design has three components:

**Component 1 — Prompt engineering calibration**: test three prompt conditions across five
models. Conditions: (1) codebook-only (no source text — measures baseline signal from model
training data alone), (2) evidence packets (section-extracted State Dept and Freedom House
text + few-shot calibration examples), (3) anonymized summaries (an agent rewrites the
extracted text to strip country-identifying information before coding). Models: Claude
Sonnet 4.6 (frontier), Llama 405B, Llama 70B, Llama 9B, and fine-tuned Llama 70B (QLoRA
adapter trained on individual coder ratings from V-Dem v15; runs on the anonymized prompt
format without few-shot examples, since calibration is in the weights). Outcome: MAD from
raw panel mean across all five models; MAE against individual coder ratings for fine-tuned
model.

**Component 2 — Generalization test (primary novel finding)**: the fine-tuned model is
trained on 12 V-Dem indicators and evaluated on X held-out indicators from the same modules
(same evidence sources, unseen during training). If MAE on held-out indicators approximates
MAE on trained indicators, the result supports a general V-Dem AI coder claim — a model
that can code indicators beyond those it was explicitly trained on. This is the core
contribution: not just calibration on known indicators, but transferability across V-Dem's
measurement system.

**Component 3 — Integration robustness (secondary)**: using the best-calibrated model,
test whether adding one AI coder to a well-formed human panel shifts the raw panel mean
detectably. Simplified replacement experiment (k=1) on a subset of country-year-indicators.
Serves as a robustness check on the calibration finding, not the paper's primary claim.

The pipeline shares source documents, ingestion, and section extraction infrastructure with
the bridge-coder paper. No separate data collection is needed for the contemporary window.

---

## Indicators

12 V-Dem Type C indicators spanning seven modules, selected for evidentiary coverage by
State Dept and Freedom House reports. Selection rationale:
`initial-exploration/explore-indicators/02-indicator-selection.html`.

| Tag | Indicator | Module | Observability |
|---|---|---|---|
| v2clkill | Political killings | Civil liberties | High |
| v2cltort | Torture | Civil liberties | High |
| v2mecenefm | Media censorship (formal) | Media | High |
| v2csreprss | Civil society repression | Civil society | High |
| v2jupoatck | Government attacks on judiciary | Judiciary | High |
| v2mecenefi | Media censorship (informal) | Media | Medium |
| v2juhcind | High court independence | Judiciary | Medium |
| v2clacfree | Academic freedom | Civil liberties | Medium |
| v2clslavef | Freedom from forced labor | Civil liberties | Medium |
| v2psoppaut | Opposition party autonomy | Political parties | Medium |
| v2excrptps | Public sector corruption | Executive | Medium |
| v2pepwrsoc | Political power by social group | Political equality | Low |

Expect calibration MAD to vary systematically by observability tier: high-observability
indicators (discrete, named events) should be easiest for AI to code from annual reports;
low-observability indicators (diffuse evaluative judgments) hardest.

---

## Contribution claim

**The key contribution is not that AI coders are as good as human experts.** It is three
related findings in sequence:

1. **Calibration**: which prompt strategy and model scale produces AI ratings closest to
   human panel means across 12 V-Dem indicators? This answers the practical question of how
   to build an AI coder and whether more expensive options (larger models, anonymization,
   fine-tuning) are justified.

2. **Generalization**: does a fine-tuned model transfer to V-Dem indicators it was not
   trained on? If yes, the result supports a scalable AI coder that could be applied across
   V-Dem's full measurement system — not just the 12 indicators studied here. This is the
   primary novel finding.

3. **Safe integration**: does adding one AI coder to an existing human panel shift the raw
   panel mean detectably? This answers the deployment question for thin and attriting panels.
   Reported as a robustness check on the calibration finding.

Secondary: the codebook-only condition tests whether large frontier and open-weights models
already have latent calibration from their training data, independent of evidence — with
implications for whether the evidence pipeline is necessary at all.

---

## Paper framing (APSR target)

**"How close can AI coders come to replacing human expert coders for democracy measurement,
and what prompt strategy and model scale is needed to achieve reliable substitution?"**

The bridge-coder paper (Political Analysis target) addresses a different problem — linking
disconnected national panels via IRT — and is a separate paper sharing the same source
document infrastructure.

---

## Deployment targets (after validation)

**Target 1: Historical sparse panels (1975–1989)**
59% of pre-1990 country-years have ≤3 distinct coders. Freedom House (1972–) and State
Dept (1977–) provide evidence packets. Adding AI ratings moves these from prior-dominated
to data-informed.

**Target 2: Chronic thin-coverage countries (contemporary)**
~35 countries with mean panel < 8 in 2010–2024: Haiti, Chad, Guinea-Bissau, Solomon
Islands, Vanuatu.

**Target 3: Leading-edge gap (2020–present)**
Mean panel size ~5.8 and declining ~0.5/year. AI ratings as interim augmentation for the
most recent wave — operationally the most urgent use case.
