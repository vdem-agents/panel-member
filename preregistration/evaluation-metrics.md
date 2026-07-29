# Evaluation Metrics

## Primary metric: AI MAE against the panel mean

The primary metric throughout the study is AI MAE — the absolute deviation of the AI
rating from the raw panel mean, per country-year-indicator (CYI):

```
AI_MAE = |AI_rating − panel_mean|
```

All identification and mechanism-test hypotheses (the B, F, and R series in
`preregistration/key-hypotheses.md`) compare AI MAE across prompt conditions, models, or
subgroups — never against the human benchmark described below. The human benchmark
matters for exactly one analysis, the agreement test (see "Human LOO MAE," below); it
drops out algebraically of every other comparison in the design, since it is common to
both sides of any within-model or within-condition delta.

### The MAE floor

AI MAE has no natural zero, for two reasons. First, ratings are integers (0–4) but the
panel mean is a fraction, so even a hypothetical oracle coder that knows the panel mean
exactly must round to the nearest integer and eat the rounding error — the **rounding
floor**, `|round(panel_mean) − panel_mean|`, averaged across the evaluation pool. Second,
the panel mean is itself an estimate from a small panel, not a directly observable ground
truth, so it carries its own sampling noise — the **panel-noise floor**, which has no
closed form but is captured empirically by the human LOO MAE below, since real human
coders face the identical integer-rounding constraint and the identical small-panel noise.

Both floors are computed from human data alone — no AI output required
(`analysis/05-human-mae-floor.qmd`):

| Year | Rounding floor | Human LOO MAE | N (CYI) |
|---|---|---|---|
| 2019 | 0.230 | 0.709 | ~34,400 |
| 2023 | 0.227 | 0.726 | ~34,300 |
| 2024 | 0.222 | 0.716 | ~30,300 |

The rounding floor is small relative to the human LOO MAE — most of a human coder's LOO
error reflects genuine inter-coder disagreement, not the integer-rounding constraint. Both
floors are stable across 2019/2023/2024 despite continued panel thinning. AI MAE should
always be read against the human LOO MAE, not against zero; the identification deltas
(Δ(Evidence − Codebook), etc.) are unaffected by either floor, since both are common to
every condition and model being compared and cancel out of the subtraction.

## Human LOO MAE — the agreement-test benchmark

For each country-year-indicator (CYI), compute the leave-one-out mean absolute error for
human coders:

```
human_LOO_error_i = |rating_i − mean(panel \ {i})|
```

where `panel \ {i}` is the panel mean with coder i removed. Average across all coders in
the panel to get the per-CYI human LOO MAE, then average across CYIs to get the aggregate.

For the AI, the analogous quantity is simply `|AI_rating − panel_mean|` — the AI is not
in the panel so nothing needs to be removed. This is the same AI MAE defined above; the
human LOO MAE exists only to give it a benchmark to be read against.

The comparison `AI MAE vs. human LOO MAE` is the agreement test: is the AI within the
range of normal human disagreement? This is the one place in the design where the human
benchmark is load-bearing rather than cancelling out of a delta. Bootstrap resample at
the CYI level (B=500) to get CIs and a paired significance test. Reporting unit: model ×
indicator table + one aggregate column. The CYI is the unit of computation, not reporting.

## Secondary metrics

**Exact match rate**: proportion of AI ratings equal to the rounded panel mean.

**Adjacent-category agreement**: proportion of AI ratings within ±1 of the rounded panel
mean. Both metrics are cheap to compute from the same output and readable for a mixed
political science / CS audience.

## Compression diagnostic: signed deviation by quintile

For each CYI, compute `AI_rating − panel_mean` (signed, not absolute). Average by
democracy quintile (v2x_polyarchy quintiles from V-Dem v15). The human baseline for
signed deviation is ~0 by construction — individual human ratings are balanced around
their own panel mean. Any systematic AI deviation away from zero by quintile reveals
directional compression bias: positive deviations in low quintiles indicate AI rates
autocracies too generously; negative deviations in high quintiles indicate AI rates
democracies too harshly. Report as a figure: signed deviation on y-axis, quintile on
x-axis, one line per model (or condition).

Note: AI MAE by quintile (absolute, stratified) and signed deviation by quintile
(directional) answer different questions and both should be reported. AI MAE by quintile
shows whether accuracy varies across regime types; signed deviation shows which way the
AI is biased.

## Metric table

| Metric | Role | Reported at |
|---|---|---|
| AI MAE vs. panel mean, with bootstrap CIs | Primary metric throughout | Model × condition × indicator table + aggregate |
| Human LOO MAE | Agreement-test benchmark only | Model × indicator table + aggregate |
| Exact match rate | Secondary — readable calibration summary | Same table or supplement |
| Adjacent-category agreement (±1) | Secondary — readable calibration summary | Same table or supplement |
| Signed deviation by quintile | Compression / directional bias diagnostic | Separate figure |

## Relationship to replacement experiment

The LOO framework unifies with the k=1 replacement check. The human LOO error — how much
the panel mean shifts when one human coder is removed — is the same quantity as the
"divergence" in the replacement experiment when one AI coder is added. The two analyses
share the same infrastructure.

## Why AI MAE uses the panel mean, not individual coder scores

A natural alternative to `|AI_rating − panel_mean|` is to average the AI's absolute
deviation from each individual coder:

```
Option B: mean_j(|AI_rating − rating_j|) over all coders j
```

By Jensen's inequality (absolute value is convex), Option B ≥ Option A always. The gap
between them equals the within-panel disagreement. Concrete example:

Coders: 2, 3, 3, 4 → panel mean = 3.0, AI rating = 3

- Option A: |3 − 3.0| = 0.0
- Option B: mean(|3−2|, |3−3|, |3−3|, |3−4|) = 0.5

An AI that perfectly replicates the panel consensus still receives nonzero MAE under
Option B, because Option B conflates AI error with normal human disagreement. This makes
it uninterpretable across indicators with different panel dispersion: a high Option B
score could mean poor AI calibration or simply a diffuse panel.

Option A is the cleaner identification metric: it measures only the AI's distance from
the consensus, holding human disagreement constant across conditions and models.

The LOO framework is the principled operationalization of the spirit behind Option B for
the substitution check: rather than averaging deviations from each individual coder, it
asks whether the AI performs *within the range* of normal human panel disagreement.
See `notes/loo-mae-computation.md`.

## Why not raw AI MAE alone, without the human benchmark?

AI MAE alone conflates genuine AI error with normal human disagreement. Without a human
baseline, an AI MAE of 0.4 is uninterpretable: it might be excellent for a diffuse
indicator like `v2pepwrsoc` and poor for `v2clkill`. Human LOO MAE provides that baseline
automatically. Reporting a bare deviation-from-consensus score with no human comparator —
sometimes labeled "MAD" (mean absolute deviation) in other work — is also not standard in
either political science (where inter-rater reliability is typically ICC or Krippendorff's
alpha) or contemporary CS/NLP (see below).

Signed deviation (`mean(AI_rating − panel_mean)`) is retained for the compression
diagnostic since AI MAE is absolute and cannot show directional bias.

## CS background: distribution-aware evaluation

The field has been moving away from aggregating annotator labels to a single ground truth
and toward evaluating against the *distribution* of human judgments. Key references:

- Plank, B. (2022). The "problem" of human label variation: On ground truth in data,
  modeling and evaluation. *EMNLP 2022*. Argues that annotator disagreement is signal,
  not noise, and that models should be evaluated against the distribution of human labels
  rather than a majority-vote gold standard.

- Davani, A. M., Díaz, M., & Prabhakaran, V. (2022). Dealing with disagreements: Looking
  beyond the majority vote in subjective annotations. *Transactions of the Association for
  Computational Linguistics*, 10, 92–110. Shows that majority-vote aggregation discards
  systematic minority perspectives and proposes multi-annotator evaluation.

LOO MAE operationalizes this intuition in a way that is interpretable for a political
science audience: rather than asking "does the AI match the gold label?", it asks "does
the AI perform within the range of human expert disagreement?" Verify exact titles and
venues before citing.
