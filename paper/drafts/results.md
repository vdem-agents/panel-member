# Results section — working skeleton

*Scaffold only, 2026-09-06. Split out of `theory.md` (its old §§5–7 + the justification
caveat). Bullets are claim-stubs and structural notes, not draft prose — EJT writes the prose.
`[cite: X]` tags point at groups in `theory-citations.md`. Figure numbers follow
`paper/figures-and-tables.qmd` as it stands now. Theory-section decisions stay in `theory.md`.*

## Open structural decisions (results)

- Deployment section placement: keep at the back (after the mechanism tests) or move ahead of
  them, since deployment reinforces the "fine-tune, don't just feed" headline directly.
- Promote A8 (identity's direct effect) into the main text as part of the synthesis, or leave
  in the appendix. EJT's lean: results are decent but not conclusive.

## 1. The surprise (Figures 2 and 3)

- Evidence has the intended effect on overall error (Figure 1) but goes the *opposite* way on
  the error distribution — flatter difficulty tracking, stronger directional bias (Figures 2
  and 3). This is the one big surprise the arc is built around.
- FT models do not show the reversal: they track the difficulty slope and hold signed
  deviation near zero.
- Interpretation: base models read the evidence differently — reading entity cues to activate
  stale priors — while FT models attend to the content because training taught them to.
  [cite: B, C, D]
- Headline: fine-tune on the content; do not merely feed the content, if you want the model
  to behave like a human coder.

## 2. Why base models get hung up (exploratory mechanism section)

- Light theoretical motivation only. Three candidate explanations for the base-model pattern:
  - Prominence — the country is identifiable even from de-identified text, so an identity
    prior is available to lean on. → Figure 5, Figure 6/7 Panel B. [cite: C, E]
  - Movement — the country has drifted since the training window, so the prior is stale. →
    Figure 4, Figure 6/7 Panel A. [cite: E, K]
  - Information compression — summarization strips hedging / nuance the panel calibrates
    against, independent of identity. → A8, synthesis. [cite: F, G]
- Synthesis result: staleness and prominence do not explain the MAE-level de-identification
  pattern; direct identity removal (A8) partly does — real but not conclusive. [cite: C, F]

## 3. Deployment

- The literal question under the motivation: does adding a synthetic coder move a thinning
  panel's mean, and which way? → Figure 8 (augmentation), A9 (degradation).
- Reinforces the "use FT models" headline: FT augmentation looks like ordinary coder churn;
  an unfiltered mix of base models and conditions does not.
- Placement decision pending (see top).

## Caveat carried into the results prose

- Model justifications are illustration, not evidence — post-hoc rationalizations, used to
  show *what the model says it read*, not to prove *why* it rated as it did. [cite: M]
