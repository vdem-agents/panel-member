# Remaining To-Do Items (updated 2026-07-28, post-triage session)

Pulled from `key-hypotheses.md`'s "To do" and "Notes" sections; delete items here as you
resolve them in `key-hypotheses.md` itself — this file is scratch, not a new source of
truth.

**Status check**: the full Tier 1 list from the previous version of this file is resolved.
`key-hypotheses.md` was substantially restructured this session — hypotheses reorganized
into Parts 1–4 (confirmatory: B1–B4, F1–F2, R1–R5, D1–D2) plus a Secondary section
(exploratory: A-series), with an explicit confirmatory/exploratory framing sentence and a
general equivalence-band note (50% of the year's rounding floor) replacing the old
undefined "no difference" language in every null reading. `experimental-design.md` also
got two small fixes (the "locked before any LLM calls" wording, and the k=1 replacement
pool's year/coder-count). Everything below is what's left.

**In progress, not by Claude**: the user is manually renumbering the A-series in
`key-hypotheses.md` — A3 was deleted earlier in the session (a near-duplicate of A2) and
A4 onward were never shifted down to fill the gap, and a new hypothesis (re-identification
predicts directional bias, by region and regime type) was inserted into the sequence
mid-session, compounding the gap. Don't assume any particular A-number is stable right now
— re-check `key-hypotheses.md` directly before citing a specific letter.

**Important desync surfaced this session**: `paper/figures-and-hypothesis-map.qmd`'s
proposed R-series renumbering (R10→R1, R1→R2, ... R9→R10) was never applied. Instead, the
Part 3 restructuring this session produced its own fresh R-numbering (R1 = main
replication, R2 = regime transitions, R3 = 2024 holdout, R4 = name-swap, R5 =
re-identification salience filter) that doesn't match either the original numbering or
`figures-and-hypothesis-map.qmd`'s proposal. That document, its figure-to-hypothesis
mapping table, and `hypothesis-cell-map-and-featuring-plan.md` are all now stale relative
to `key-hypotheses.md` and will need a harmonization pass (Tier 3 — see below).

---

## Still open

**Tier 2 (interpretation/presentation, not blockers):**
- B3's and B2's bundled-manipulation acknowledgments: B3 conflates two manipulations
  (anonymization strips names from *both* the focal evidence and the few-shot calibration
  examples), and the zero-shot ablation partially unconfounds this but the prereg doesn't
  say so explicitly; same likely applies to B4/summarization. B2's bundled contrast
  (codebook-only has the country name but no text; anonymized has text but no name — two
  things change at once, and B2 is the primary identification result) is still
  unacknowledged anywhere in the document.
- Alternative/null coverage policy: still an open discussion, not a fix. Not every
  hypothesis necessarily needs an alternative reading — worth deciding which ones
  genuinely need one (the coverage-tier test's alternative, weak-coverage indicators doing
  fine because the model falls back on priors, was flagged as a case where the alternative
  is itself substantively interesting) versus which are fine as directional-only. Never
  actually discussed after the initial flag.
- B4a's potential third reading (mirroring B3a's "net-beneficial anchor" idea, applied to
  residual identity leakage in anonymized text): explicitly **not pursuing further** —
  user's call this session. Leave as-is; if a reviewer flags it as a gap, address then.

**Tier 3 (deferrable to paper-writing / the later harmonization pass):**
- Everything in `docs/overview.md` — untouched all session. Known issues: "rule out each
  source of potential bias" overreaches (input leakage isn't ruled out by any 2019
  condition, only structurally by the 2024 holdout); the text-adds-value inference chain
  should route through the zero-shot ablation (A-series), not just B1, since B1 bundles
  text with the calibration block; missing selection-rule statement for "we use 2019 to
  pick the best model" (needs the argmin + CI-overlap tiebreak, both already precise in
  `key-hypotheses.md`); "three further analyses" undercounts what's actually there;
  contribution claim still says "three-condition" (now four) and could incorporate the
  sub-question reframing from `framing-questions.md`; terminology drift across "named
  entity anchoring" / "regime-type anchoring" / "re-identification bias" with no canonical
  definition (overview.md is the natural place for one); typos ("have produce,"
  "relevent," "anlayzing," the "While…but" sentence).
- `docs/experimental-design.md`'s own numbered "Hypotheses" section (1–9): stale
  duplication of `key-hypotheses.md`. Plan is to replace it with a pointer back rather than
  independently harmonize it — not done yet. Also still has Δ-notation throughout instead
  of MAE inequalities, and the "### Applied performance" header is empty, sitting directly
  above "### Agreement test (2023)" (never merged or removed).
- `docs/architecture.md`: Stage 5's pseudocode still describes the old remove-a-coder
  replacement design instead of the current add-to-intact-thin-panel design (same root
  issue as the k=1-pool fix already applied elsewhere); "MAD" vs. "MAE" terminology drift
  in Stage 4 / `substitution_eval.py`'s description; the output-schema note's rationale for
  `raw_mean` being null under the codebook condition is wrong on its face (the panel mean
  exists regardless of condition).
- Inference-mapping table (from `fidelity-vs-tracking-channels.md`): pre-register which
  conclusion follows from which pattern of results across the outcome space (e.g., text
  helps + name-swap tracks source → genuine evidence-reading; text helps but
  de-identification kills the gain + name-swap tracks the named country →
  identity-recall-masquerading-as-competence; etc.) — protects against an incoherent
  "muddled middle" result. Never built.
- Contribution-claim rewording: from "a decomposition" (a findings claim) to "a reusable
  identification strategy for any expert-annotation task where the model may know the
  subject" (a methodological contribution that survives regardless of what the
  decomposition shows). Same location as the overview.md sub-question reframing above —
  worth doing together.
- Eval loss floor for fine-tuning models, and expected precision for CIs — both still just
  open questions in `key-hypotheses.md`'s Notes section, never addressed.
- Prediction-head fallback for fine-tuning — explicitly flagged as unrelated to
  hypotheses/preregistration, parked for later consideration. Still unexplored.
- Mechanical: "mean average error" → "mean absolute error" (`key-hypotheses.md`'s Part 1
  intro still has the wrong term); typos ("comparsion," "when finetune the model");
  notation standardization pass across the document; whether the full model×condition grid
  should live in `key-hypotheses.md` itself or stay pointer-only to the cell-map/figures
  docs.
- `fidelity-vs-tracking-channels.md` itself: three concrete recommendations were extracted
  into this file already (inference-mapping table, equivalence criterion — now resolved,
  contribution-claim rewording), but the rest of the document hasn't been cross-checked as
  carefully as the old `docs-todo.md` was. Not yet safe to delete.
- `paper/figures-and-hypothesis-map.qmd`, `hypothesis-cell-map-and-featuring-plan.md`: both
  now stale relative to `key-hypotheses.md`'s actual R-numbering and A-series content (see
  "Important desync," above) — need a resync pass once the A-series renumbering settles.
