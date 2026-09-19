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

## 2b. It is not memorization — make this explicit (added 2026-09-16)

- **The point to make:** the model is not reciting stored V-Dem scores. It carries a
  country-level prior roughly as good as an average human coder and updates it against the
  evidence; de-identification hobbles that, the way it would hobble a human coder asked to rate
  a country without being told which one. `[cite: B, E]`
- **Two supports, both computable from runs already on disk — neither is in the paper yet:**
  - *Level.* Codebook-only MAE is 0.51–0.70 across families against a human LOO floor of
    0.708 (2019) / 0.725 (2023) — ratios 0.72–0.97. Memorized scores would floor out near 0.25
    (integer output against continuous panel means) and in practice near zero. It sits at
    human-disagreement levels, not recall levels.
  - *Year.* V-Dem's 2019 scores were published March 2020 and re-published in every release
    since; the 2023 scores first appeared in v14, March 2024 — at or after these models'
    training cutoffs. Memorization predicts a visible 2019 advantage in Codebook-only accuracy.
    There is none: Llama 0.840 → 0.834, Qwen 0.721 → 0.728, Gemma 0.941 → 0.967
    (Codebook MAE ÷ human LOO, 2019 → 2023). Gemma, the family most likely to have a post-v14
    cutoff, is slightly *worse* on 2023.
- **Needs before this goes in prose:** (a) verify the three models' training cutoffs against
  published model cards rather than recollection; (b) bootstrap CIs on both quantities;
  (c) reconcile with Weidmann et al.'s "post-cutoff" claim, which is about the v14 *release
  date* rather than the coded year (see `theory-citations.md` §A, confirmed 2026-09-10).
- **Why it matters for the arc:** this is the claim Figure 5 and Figures 6–7 gesture at and do
  not establish. Re-identification shows the model can *name* a country, which is not evidence
  it has memorized that country's scores. The Codebook year-comparison is the direct test.
- **Terminology decision (2026-09-16):** use **task framing** vs. **evidence body** throughout.
  Not "prompt vs. text" — the evidence is in the prompt too, so that phrasing is actively
  misleading. `[cite: O]`

## 3. Deployment

- The literal question under the motivation: does adding a synthetic coder move a thinning
  panel's mean, and which way? → Figure 8 (augmentation), A9 (degradation).
- Reinforces the "use FT models" headline: FT augmentation looks like ordinary coder churn;
  an unfiltered mix of base models and conditions does not.
- Placement decision pending (see top).

## Caveat carried into the results prose

- Model justifications are illustration, not evidence — post-hoc rationalizations, used to
  show *what the model says it read*, not to prove *why* it rated as it did. [cite: M]
