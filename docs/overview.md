# Panel Member: Project Overview

## The problem

V-Dem estimates country-year democracy scores (θ_ct) via an IRT model that pools ordinal
ratings from multiple expert coders. The reliability of those estimates depends directly on
panel size: with 13 coders, the posterior is well-identified and robust to individual
outliers; with 2 coders, the posterior is prior-dominated and a single high-reliability
coder anchors the estimate.

Analysis of V-Dem v15 (corrected for a row-vs-distinct-coder counting issue) reveals two
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
Department reports (from late 1970s) provide evidence packets. Pre-1975 is technically
possible for well-documented countries but evidence packet construction is harder.

### Pathology 2: Chronic thin coverage (~35 contemporary countries)

About 35 countries have mean panel size < 8 distinct coders in 2010–2024: predominantly
small island states, small African states, and hard-access authoritarian regimes. Haiti,
Chad, Guinea-Bissau, Solomon Islands, Vanuatu are the clearest cases. These countries have
thin panels not because of geopolitical difficulty but because of obscurity — scholarly and
policy attention drives coder recruitment.

### Pathology 3: Leading-edge attrition (growing gap)

The post-2013 cohort of coders (recruited to code from 2005 onward) is aging out without
replacement. Annual attrition of 45–133 coders/year with essentially 0 new coders added who
code only recent years. By 2024, median panel size (~5.8) has returned to pre-2005 levels.
V-Dem's estimates for the current coding year are always based on the thinnest panels in the
dataset. This is operationally the most urgent gap: universal across countries, growing at
~0.5 coders/year, and directly testable with current evidence.

## The approach

AI personas — LLM instances given persona specifications matching empirically observed coder
profiles — serve as synthetic panel members. Their ratings enter the IRT model as additional
data, moving the posterior away from prior dominance toward data-identification.

The key contribution is not that AI coders are as good as human experts. It is that:

1. **Adding 3–5 well-calibrated AI ratings to a 1–2 coder country-year moves estimates
   from prior-dominated to data-informed** — a categorical improvement regardless of whether
   the AI ratings are perfect.

2. **Persona specification grounded in the empirical coder distribution** (via β_r and
   γ_{r,k} posteriors from V-Dem's CurateND archive) allows IRT to model the AI's
   threshold and reliability parameters from data, rather than requiring pre-calibration.

## Stage 1: What persona attributes shift LLM coding behavior?

A fractional factorial experiment randomizes persona attributes across configurations. One
LLM per (configuration × country-year) cell. The human panel mean for each country-year
serves as the benchmark.

**Attributes under investigation:**

| Attribute | Levels | Predicted direction |
|---|---|---|
| Threshold tendency | strict / neutral / lenient | signed deviation |
| Reliability profile | high / medium / low | absolute deviation |
| Democracy conception | liberal / majoritarian / participatory / deliberative | indicator-specific |
| Domestic framing | yes / no | negative (stricter) |
| Diligence | high / standard | absolute deviation |
| Packet richness | full / partial / minimal | absolute deviation |
| Source type | State Dept only / + Freedom House / + Wikipedia | TBD |

**Design**: algorithmic fractional factorial (R `AlgDesign`), 32–48 configurations for main
effects, 64 if the source type × domestic framing interaction is pre-specified.

**Outcomes**: two in parallel:
- *Signed deviation* (LLM rating − human panel mean): for attributes with directional
  predictions (threshold tendency, domestic framing)
- *Absolute deviation* |LLM rating − human panel mean|: for precision attributes
  (reliability, diligence, packet richness)

**Country-year pool**: N_cy = 30–50 country-years with ≥8 distinct coders (2010–2019),
same pool across all configurations. ~130–175 eligible per year; subsampling is trivial.

## Stage 2: Sequential replacement test

Remove human coders one at a time, replacing with AI personas matched to empirical coder
profiles (drawn from β_r and γ_{r,k} posteriors). Rerun IRT after each replacement. Track
when θ_aug begins to diverge meaningfully from θ_full. This answers "how many human coders
can AI replace before panel quality degrades?" — a practically meaningful number.

## Stage 3: Deployment

Apply to one or more of: (a) historical 1975–1989 sparse panels, where evidence packets
from Freedom House and State Dept reports are available; (b) chronically thin-coverage
contemporary countries (Haiti, Chad, small island states); (c) the 2020–2024 leading-edge
gap as an interim coding mechanism.
