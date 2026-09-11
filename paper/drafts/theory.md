# Framing / problem section — working skeleton

*Scaffold only. Built from `scratch.md` (Entries 1–2). Bullets are claim-stubs and structural
notes, not draft prose — EJT writes the prose. `[cite: X]` tags point at groups in
`theory-citations.md`; `[in-repo]` means the stat/figure already exists in this repo.
Figure numbers follow `paper/figures-and-tables.qmd` as it stands now. Old §§5–7 + the
justification caveat are in `results.md`.*

*Draw on `scratch.md` and `seraphine-questions.md` for the motivation prose — the latter is
EJT's own statement of the rationale (social-science hook = the leakage/information question;
Benoit assumes summaries drive ratings but manifestos are in pretraining; contextual vs.
parametric knowledge; why fixed packets not tool-calling; why Llama-3.3-70B; why State Dept +
FH; the "not that LLMs should never use priors, but they must update on new information" line).*

## Open structural decisions (framing)

- **What this section is called.** Not "Theory". Frame it as an exploration of a general
  problem — expert-coded data sources and what it takes to maintain them — with V-Dem as the
  vehicle, not the subject. Decide the actual heading.
- **What splits to the Introduction.** The broad "expert-coded measures are costly and several
  have decayed" framing belongs partly in the intro; the coder-panel decline is a crucial
  motivator from a political-science / deployment standpoint but not a methods one. Decide the
  intro/section division so neither repeats the other.
- **One figure here is OK** (2026-09-06). The coder-attrition figure — mean/median panel size
  by year, `analysis/01-panel-degradation-pathologies.qmd` chunk `context-pyramid` — goes in
  §1, not the intro (the earlier objection was a figure *in the intro*). Open: crop to
  ~2000–2024 so the story is the 2005 build-up and post-2013 decline, not the pre-2005 flat
  stretch (partly a retrospective-coding / fewer-indicators artifact); and decide whether the
  Analysis-4 posterior-SD time series (the *consequence* — rising IRT uncertainty) is the
  better choice or a second panel.
- Readout / calibration scope: introduce greedy vs. expectation here; keep the
  entropy/calibration-to-disagreement result light or out (follow-on territory). Maerz found
  the prereg confusing — argues for keeping this minimal.
- One-big-surprise constraint: the arc must land the surprise on Figures 2–3, not Figure 1 —
  so criterion 2 ("right MAE is not enough, the error shape has to match") must be set up
  *before* Fig 1 appears.

## Overview paragraph

Conceptual measurement in political science frequently features expert-coded data produced by trained coders who read primary sources and score them against a detailed codebook. Most projects in this space, including Polity, Freedom House's Freedom in the World, the Comparative Manifesto Project and many conflict datasets, rely on a single coder or a small adjudicating team. Others gather judgments from multiple experts and average them across country cases in a panel framework. Prominent examples of panel-based projects include the Chapel Hill Expert Survey, the Perceptions of Electoral Integrity project, and the World Justice Project's Rule of Law Index. The Varieties of Democracy project (V-Dem) and related efforts modeled on it represent a unique framework in which many independent experts rate each case and a measurement model estimates each coder's reliability and scale use before the ratings are aggregated [cite: L]. 

Sustaining a panel of this kind asks more of its members than single-coder projects do. In the case of V-Dem, a country expert typically codes one country across its full time series for a block of about 100 indicators in their area, and experts recruited after 2013 are responsible for every year from 2005 forward. Consequently, the assignment grows with each round, from roughly 10 country-years in 2015 to nearly 20 by 2024 [cite: L]. 

(put a footnote here instead of a citation)

When an expert stops coding, their countries either lose a panelist or pass to colleagues who already carry a full load, and the experts who remain are disproportionately those willing to absorb the extra work. Attrition of this sort tends to compound. Through the 2010s V-Dem lost on the order of 50 to 130 coders a year with almost no replacement, and only about 10 experts active in 2024 had joined since 2005 [cite: L]. Figure @fig-attrition shows the mean and median panel returning to their pre-2005 level of roughly five experts per country-year, after the post-2005 cohort was recruited and then thinned. Thinner panels degrade the measurement model directly. V-Dem's published posterior standard deviations widen as panels shrink, by about 0.012 scale units for each coder lost, and post-2013 attrition has raised average estimate uncertainty by roughly 12 percent relative to its 2008 to 2010 low [cite: L]. The codebook advises against using any estimate that rests on three or fewer coders, a bound a growing share of contemporary country-years now sits near [cite: L].

A synthetic coder may help in maintaining panel integrity but only if it lands near the human consensus without merely echoing it, errs on the same cases a human would, and rates from the evidence it is given rather than from a stored impression of the country. The remainder of this section elaborates on these challenges and how they might be met in the context of the V-Dem project. 

### What makes it a distinctive measurement problem (the methods hook)

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

## 4. Predictions on the two levers

### Evidence (content)

- Two directions evidence could push the rating: toward consensus, or toward defensible
  disagreement ("debate"). Which one depends on the content, on whether it matches what other
  panel members are reading, and — the key hinge — on *how* the AI reads it.
- The hinge: absorbing the content vs. using entity cues in the text to activate a prior.
  [cite: B, C, D]
- Prediction for Figure 1: evidence moves error in roughly the intended direction (mostly
  confirms — framed as emerging from the literature discussion, acknowledged as partly
  post-hoc, kept for the reader and the narrative).

### Fine-tuning

- Prediction: fine-tuning makes the synthetic coder more human-like — it adjusts weights so
  the model uses content the way a human coder does, aligning the reading with panelist
  behavior. [cite: A (HALC / examples-drive-performance), J]
- Prediction: FT does well on *both* criteria (magnitude and shape).
