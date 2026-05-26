# panel-member

AI personas as panel members: augmenting thin V-Dem expert panels with LLM coders.

## The problem

59% of pre-1990 V-Dem country-years have ≤3 expert coders; at that level the IRT posterior
is prior-dominated. ~35 contemporary countries have chronically thin panels. Annual attrition
is returning even recent country-years toward the historical 5-coder baseline. AI personas —
LLM instances given empirically-grounded coder profiles — can move these estimates from
prior-dominated to data-informed.

## Repo structure

```
docs/
  overview.md       — project background, panel pathologies, contribution claim
  strategy.md       — Stage 1 factorial design, Stage 2 replacement test, Stage 3 deployment
prompts/
  panel-member-prompt-v1.md  — extended prompt draft with persona specification
pipeline/           — code (to be populated)
data/
  raw/              — State Dept reports, Freedom House (not committed; see .gitignore)
  processed/        — extracted text, retrieval indices
```

## Status

Early development. Stage 1 design finalized conceptually; pre-registration and fractional
factorial matrix generation are next steps.

## Related repo

[bridge-coder](https://github.com/vdem-agents/bridge-coder) — the companion paper on
AI as bridge coders for cross-national calibration.
