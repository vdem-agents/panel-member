# Framing Questions

*Working draft, 2026-07-28. Organizational map for how the B/F/R hypotheses in
`key-hypotheses.md` relate to the paper's central question — not new hypotheses, not a
figure spec (see `paper/figures-and-hypothesis-map.qmd` for that). This is the seed
content for whatever theory/framing section `paper/outline.qmd` eventually needs, once
that file gets resynced to the current design — write the actual paper prose from this,
don't duplicate it here in the meantime.*

Hypothesis labels below use the *current* numbering, i.e. after the R-series renumbering
in `paper/figures-and-hypothesis-map.qmd` (R10→R1, R1→R2, ..., R9→R10). Cross-check before
citing elsewhere — the renumbering hasn't been applied to `key-hypotheses.md` itself yet.

---

## Central thesis

Original: *"information use is governed by the interaction of named-entity priors,
information novelty, calibration strategies, and anonymization during training."*
(Flagged as needing to be clearer and less jargony.)

Proposed revision: **Whether an LLM uses the text in front of it, rather than what it
already "knows" about the subject, depends on four things — how strong the competing
prior is (identity anchoring), how stale that prior is relative to current conditions
(information novelty), how the model was taught to calibrate its answers (few-shot
examples vs. fine-tuned weights), and what kind of text — real names and institutional
detail, or abstracted descriptions — it was trained to read (training representation).**

This is the same four-factor structure as the original, just unpacked into plain
sentences instead of stacked noun phrases. Pick one, or iterate further.

---

## Mechanism framing (does the model use the text, and when?)

Five sub-questions, each a different angle on the same underlying question. These are
the buckets the B/F/R hypotheses decompose into — not new claims, just the organizing
scheme.

### 1. Baseline conditions
*Whether and to what extent text affects the model's fidelity relative to coders.*
**B1, B5**

### 2. Identity anchoring
*How much do LLMs rely on pretraining knowledge about countries and other named entities,
relative to textual evidence in prompts? Is apparent use of the text actually
identity-anchoring in disguise?*
**B2–B4; R5–R8** (re-identification and name-swap machinery — old R4–R7)

### 3. Conditions
*When does the model rely on text?* Text matters more when:
- coverage is good (**R9**, old R8)
- priors are stale — regime transitions (**R3**, old R2) or post-training-cutoff data
  (**R4**, old R3)
- priors are weak — non-salient, non-re-identified cases (**R7**, old R6)

### 4. Calibration channel
*Does model performance owe more to few-shot prompting or to fine-tuning? Does that
interact with how much identity information is available?*
**B6, F1, R10** (old R9)

### 5. Fine-tuning representation
*Does training on de-identified text make the model better at evaluating and using text?*
**F2 (resolved: model ranking on raw Evidence — FT-summ < FT-anon < FT-raw), F3
(codebook probe / anchoring bake-in), F5 (representation transfer to raw evidence)**. F4
(training-side analog of B4) belongs here too once operationalized — see
`figures-and-hypothesis-map.qmd`'s open items.

---

## Applied framing (is it good enough to use?)

A separate question from all five above — not "does the model read text," but "is the
result usable." This is the other half of the paper's contribution as already split in
`docs/overview.md`'s Contribution claim section (mechanism decomposition vs. deployment
guidance), and it's what the currently-empty "Applied performance" header in
`docs/experimental-design.md` has been waiting for.

- **R1** (old R10): does the carried-forward model's AI MAE clear the human LOO MAE bar —
  is it within the range of normal human disagreement?
- **F2 resolved**, read from the deployment angle rather than the mechanism angle: which
  model should actually be used, and does the answer change depending on whether "best"
  means lowest MAE or least anchoring-dependent?
- The selection-rule tension itself (deployment-optimal vs. mechanism-informative model
  may differ) is worth a sentence here too — it's an applied-framing point, not a
  mechanism one.

---

## Open items

- Thesis wording: pick a final version or keep iterating.
- Whether B7 (a 2019 counterpart to R1) gets registered — still undecided, see
  `figures-and-hypothesis-map.qmd`.
- This doc doesn't yet say anything about *how* these six buckets map onto paper
  section headers — that's the `paper/outline.qmd` resync's job, not this doc's.
