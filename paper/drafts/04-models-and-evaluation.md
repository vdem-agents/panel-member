# Section Title

("right MAE is not enough, the error shape has to match")

Reference this memo for explaining logic of human LOO mean: notes/loo-benchmark-metric-decision.md

### Measurement

- **Panels, not individual coder scores.** The target is a panel aggregate; a new rater is
  judged by whether it shifts that aggregate and by whether its error behaves like a coder's,
  not by its standalone accuracy.
- **High persistence.** Most country-indicator scores barely change year to year — ~87% of
  cells move < 0.25 between 2018 and 2019; only ~0.3% move ≥ 1.0. Naive carry-forward (last
  year's panel mean) has MAE ≈ 0.10 continuous / ≈ 0.26 rounded, beating both base models
  (~0.58–0.60) and a typical human coder (~0.71) on the full pool.
  (`analysis/09-regime-transition-2019.qmd` §4; `notes/stage1-preliminary-observations.md`.)
  [in-repo]

### The rounding floor and SESOI (introduce here, alongside persistence)

- Panel means are fractional; a rater that emits integers has a mechanical floor of
  ≈ 0.22 mean absolute deviation from the mean (`round(mean) − mean`). The **SESOI** is half
  that — ≈ 0.115 (2019), ≈ 0.113 (2023) — the equivalence band used throughout the paper.
  (`helpers/bootstrap_helpers.R`.) [in-repo]

### Consequence for how a synthetic panel member is judged

- "Beat the naive baseline on distance to the panel mean" is nearly unbeatable and the wrong
  bar. The useful target is the **goldilocks zone**: off the sticky carry-forward value (it
  contributes independent signal) but not past the human-reference SESOI band. → sets up §2
  criterion 1 and Figure 1.

## 2. What a good synthetic panel member has to do (two criteria)

- Criterion 1 — right magnitude of error: land in the goldilocks zone from §1 (between naive
  carry-forward and beyond the human-reference SESOI band). → Figure 1.
- Criterion 2 — right *shape* of error: track case difficulty like a human coder (difficulty
  slope) and carry no directional / regime bias (signed deviation). Getting the MAE right is
  not enough — set this up here so Figures 2–3 carry the surprise. [cite: J for the
  "match the human error distribution" idea]
- Phraseology available but not central: consensus oracle vs. debater / panel member.

## 3. Readout modes (lay out up front, do not back into)

- Greedy (mode) readout → a panelist: one ordinal judgment, reflecting the coder distribution
  the model learned. [cite: I]
- Expectation (mean) readout → a consensus oracle: probability-weighted mean, aimed at the
  panel mean. The naive carry-forward model is hard to beat on this objective (see §1).
- Cross-entropy on individual coder labels makes `p(rating | X)` approximate the coder
  distribution; mode and mean are two readouts of the same trained object. [cite: I]
- A main reason the preregistration is treated as advisory: the greedy/expectation distinction
  reorganizes what the hypotheses were testing.

