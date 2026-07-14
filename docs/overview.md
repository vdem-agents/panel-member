# Panel Member: Project Overview

## The case for AI-assisted annotation

Large-scale annotation projects face significant challenges in maintaining a high standard of measurement for their widely used cross-national political social indicators.
Projects such as the Polity political regime series, the Chapel Hill Expert Survey of
party positions, the Comparative Manifesto Project, Freedom House's Freedom in the World
ratings, and Varieties of Democracy rely on expert judgment sustained across many
countries, years, and indicators. Panels thin over time as coders age out, and
replacement recruitment rarely keeps pace with attrition.

The Varieties of Democracy (V-Dem) project is illustrative of these difficulties. The project estimates country-year democracy
scores via a Bayesian IRT model that pools ordinal ratings from country-specific panels
of expert coders. Post-2013 cohorts are aging out without replacement, resulting in a drop in the median panel size from roughly 11 coders in the 2010s to 5.8 by 2024, with the quality of measurement suffering as a result. At small panel sizes, the IRT posterior is poorly identified and increasingly sensitive to individual coder threshold idiosyncrasies.

Large language models represent an obvious candidate for augmenting thinning panels. If
AI ratings can substitute for departed coders without shifting the panel mean detectably,
the measurement infrastructure can potentially be sustained without expanding personnel. A small literature has begun exploring the capacity of AI coders to replace human experts (e.g. Benoit 2025), but there are challenges to establishing whether AI outputs are
driven by the AI's ability to evaluate new evidence or by knowledge encoded during pretraining.

## Two sources of bias

The reliability of AI annotation depends directly on whether model outputs reflect the provided evidence or knowledge encoded during pretraining (data leakage). In practice, both contribute to any observed correlation with human expert ratings and an evaluation strategy that simply reports on correlations between AI and human ratings cannot separate them.

The first source of bias is input leakage at the document level or what is commonly referred to as *data contamination* in the NLP literature. Source documents commonly used as annotation evidence, including State Department human rights reports, Freedom House
country narratives, and party manifestos, are publicly available and almost certainly
present in LLM pretraining corpora. An AI presented with these documents may have produce ratings correlated with that of a human expert either because it is reasoning from the text (the desired outcome) or because of its prior encoding of the same document. A simple correlation between human and AI ratings cannot disentangle the two explanations.

The second source of bias, *named entity anchoring*, operates at a different level. Even when the model is reading the provided text, it may use syntactic cues, such as country names, named institutions, and recognizable events, to activate prior beliefs about the subject rather than processing what the text reports. Where those priors are strong, the evidence is effectively discounted and ratings reflect pretraining knowledge of the subject rather than the new information provided by document content.

A third concern, *benchmark contamination* bears on evaluation validity rather than bias in AI ratings directly. When the benchmark used for evaluation has itself been reproduced in running text that entered the model's training corpus, a high correlation may reflect memorization of labels rather than genuine annotation. This threat is acute for widely-cited aggregate measures such as Polity scores, Freedom House country ratings, and CHES party placements, which appear throughout the political science literature.

This paper utilizes V-Dem coder-level data and a three-condition identification design to isolate and rule out each source of potential bias in AI ratings of V-Dem indicators. The codebook-only condition provides no source text, measuring the baseline calibration available from pretraining alone. The evidence condition adds raw section text, isolating what structured primary source evidence contributes over pretrained knowledge. The anonymized condition strips country-identifying information from that text, isolating how much country identity, rather than described conditions, drives the ratings. Benchmark contamination is ruled out because the evaluation target (coder-level ratings) have no presence in textual sources that the model may have been trained on, making memorization of the labels implausible in principle.

## The identification strategy

The three prompt conditions are not robustness checks — they are an identification
design:

| Comparison | What it isolates |
|---|---|
| Codebook-only → Evidence | What structured primary source text adds over pretrained knowledge alone |
| Evidence → Anonymized | How much country identity (not text) drives ratings — regime-type anchoring |
| Anonymized (base 70B) → Fine-tuned 70B | What embedding calibration in weights adds over in-context few-shot examples |
| Models (same condition) | Scale effects on each information source |

The codebook-only condition is especially important: if frontier and large open-weights
models already produce well-calibrated ratings from codebook text alone, the evidence
pipeline is unnecessary and the source of calibration is entirely pretrained knowledge.
If evidence adds substantially, the model is reading the text. If anonymization helps
further, country-identity shortcuts were inflating apparent calibration.

## Metrics

The primary metric is LOO MAE against the human panel baseline — the typical error of
a held-out human coder against the rest of their panel. This answers the question "is
the AI performing within the range of normal human disagreement?" Correlation with
expert ratings, the most common metric in the existing literature, cannot detect
systematic scale compression, directional bias, or whether AI accuracy varies across
the democracy distribution. Signed deviation by democracy quintile is the complementary
diagnostic: if AI ratings anchor on country identity, the signature is positive deviation
in low-quintile autocracies (rated too high) and negative deviation in high-quintile
democracies (rated too low).

## Design summary

**Conditions (3)**: codebook-only; evidence (raw section text + few-shot calibration
examples); anonymized (country identity stripped + anonymized few-shot examples).

**Models (4)**: Llama 405B, 70B, 9B (open weights, GW Pegasus); Llama 70B fine-tuned
on V-Dem v15 coder ratings 2016–2018 (all 206 mapped Type C indicators;
~1–2M training examples).

**Evaluation**: 2019 (primary); 2023 (robustness check, best model only). LOO MAE with
bootstrap CIs; signed deviation by quintile; exact match and adjacent-category agreement.
Coverage tier (strong / partial / weak) as a moderating variable in the results.

**Replacement check (supplemental)**: for all 2019 CYIs with ≥8 coders, `k=1` —
does adding one AI rating shift the raw panel mean detectably?

## Contribution claim

**Primary (NLP / AI annotation)**: a decomposition of what LLMs draw on when coding
political texts, using a three-condition identification design. Applicable beyond V-Dem
to any structured expert annotation task with multi-annotator panels.

**Primary (political science)**: which prompt strategy and model scale produces AI
ratings that fall within the range of human expert disagreement for V-Dem democracy
indicators, and does calibration degrade across the strong → weak source-coverage
gradient?

**Applied**: evidence-based guidance on whether AI augmentation of contemporary thin
panels is safe — whether the raw panel mean shifts detectably under `k=1` substitution.