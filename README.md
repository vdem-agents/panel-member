# panel-member

AI as panel members: how many human coders can AI replace before V-Dem panel quality degrades?

## The problem

59% of pre-1990 V-Dem country-years have ≤3 expert coders; ~35 contemporary countries
have chronically thin panels; and annual attrition is pushing the 2020s back toward a
5-coder baseline. Adding AI-generated ratings to thin panels can move IRT posteriors from
prior-dominated to data-informed — but only if the AI ratings are sufficiently similar to
human ratings that substituting them does not distort the estimated democracy scores.

## Core question

How many human coders can be replaced by AI before θ_aug diverges meaningfully from
θ_full? The answer determines the operational envelope for AI panel augmentation.

## Repo structure

```
docs/
  overview.md           — panel pathologies, contribution claim, paper framing
  strategy.md           — staged design: replacement experiment + fine-tuning
  experimental-design.md — conditions, metrics, pre-registration checklist
  architecture.md       — pipeline: section extraction (no ChromaDB), IRT runner
notes/
  persona-prompting-design-archive.md — original fractional factorial design (archived July 2026)
prompts/                — shared prompt template (few-shot, same as bridge-coder)
pipeline/               — code (to be populated; shares source docs with bridge-coder)
data/
  raw/              — State Dept reports, Freedom House (gitignored)
  processed/        — extracted text, CWM data
```

## Status

Design phase. Stage 0 (2020 pilot) complete in bridge-coder repo; results inform the
few-shot baseline here. Stage 1 (replacement experiment design) in preparation.

## Related repo

[bridge-coder](https://github.com/vdem-agents/bridge-coder) — the companion paper on
AI as bridge coders for cross-national calibration. Both papers share source documents
and the section extraction pipeline.
