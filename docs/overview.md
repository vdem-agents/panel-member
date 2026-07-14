# Project Overview

## The case for AI-assisted annotation

Large-scale annotation projects face significant challenges in maintaining a high standard of measurement for their widely used cross-national political social indicators. Such projects rely on expert judgment sustained across many
countries, years, and indicators. The panels can be expensive to maintain while recruitment of new coders rarely keeps pace with attrition.

The Varieties of Democracy (V-Dem) project is illustrative of these difficulties. The project estimates country-year democracy
scores via a Bayesian IRT model that pools ordinal ratings from country-specific panels
of expert coders. Post-2013 cohorts are not being replaced at the rate that they are aging out, resulting in a halving in the median panel size from roughly 11 coders in the 2010s to 5.8 by 2024, with the quality of measurement suffering as a result. At small panel sizes, the IRT posterior is poorly identified and increasingly sensitive to individual coder threshold idiosyncrasies.

Large language models represent an obvious candidate for augmenting thinning panels. If
AI ratings can substitute for departed coders without shifting the panel mean detectably,
the measurement infrastructure can potentially be sustained without expanding personnel. A small literature has begun exploring the capacity of AI coders to replace human experts (e.g. Benoit 2025), but there are challenges to establishing whether AI outputs are
driven by the AI's ability to evaluate new evidence or by knowledge encoded during pretraining. If AI's are relying primarily on pretraining knowledge, this could present problems for rating new country cases or information about rapidly changing circumstances in existing ones.

## Three sources of bias

The reliability of AI annotation depends directly on whether model outputs reflect the provided evidence or knowledge encoded during pretraining (data leakage). In practice, both contribute to any observed correlation with human expert ratings and an evaluation strategy that simply reports on correlations between AI and human ratings cannot separate them.

The first source of bias is input leakage at the document level or what is commonly referred to as *data contamination* in the NLP literature. Source documents commonly used as annotation evidence, including State Department human rights reports, Freedom House
country narratives, and party manifestos, are publicly available and almost certainly
present in LLM pretraining corpora. An AI presented with these documents may have produce ratings correlated with that of a human expert either because it is reasoning from the text (the desired outcome) or because of its prior encoding of the same document. A simple correlation between human and AI ratings cannot disentangle the two explanations.

The second source of bias, which we refer to as *named entity anchoring*, operates at a different level. Even when the model is reading the provided text, it may use syntactic cues, such as country names, named institutions, and recognizable events, to activate prior "beliefs" about the subject rather than processing what the text reports. Where those priors are strong, the evidence is effectively discounted and ratings reflect pretraining knowledge of the subject rather than the new information provided by document content.

A third concern, *benchmark contamination* bears on evaluation validity rather than bias in AI ratings directly. When the benchmark used for evaluation has itself been reproduced in running text that entered the model's training corpus, a high correlation may reflect memorization of labels rather than genuine annotation. This threat is acute for widely-cited aggregate measures such as Polity scores, Freedom House country ratings, and Chapel Hill Expert Survey party placements, which appear throughout the political science literature.

## The identification strategy

This study utilizes V-Dem coder-level data and a three primary experimental conditions to isolate and rule out each source of potential bias in AI ratings of V-Dem indicators. The codebook-only condition provides no source text, measuring the baseline calibration available from pretraining alone. The evidence condition adds raw section text, isolating what structured primary source evidence contributes over pretrained knowledge. The anonymized condition strips country-identifying information from that text, isolating how much country identity, rather than described conditions, drives the ratings. Benchmark contamination is ruled out because the evaluation target (coder-level ratings) have no presence in textual sources that the model may have been trained on, making memorization of the labels implausible in principle.

The study design features thre primary conditions:

| Comparison | What it isolates |
|---|---|
| Codebook-only → Evidence | What structured primary source text adds over pretrained knowledge alone |
| Evidence → Anonymized | How much country identity (not text) drives ratings — regime-type anchoring |
| Anonymized (base 70B) → Fine-tuned 70B | What embedding calibration in weights adds over in-context few-shot examples |
| Models (same condition) | Scale effects on each information source |

The codebook-only condition serves as the key baseline for the study against which the other conditions are measured. If textual evidence adds substantially to model performance, we can infer that the model is reading the text. If anonymization helps
further, we can infer that country-identity shortcuts were inflating apparent calibration.

## Scope and source data

### Training and inference

Model training for the fine-tuned variants of the Llama 70B Instruct model will be performed on V-Dem v15 coder-level ratings from 2016–2018 (~898K training examples across all 206 indicators). The training window was selected because source documents are reliably available from 2016 onward while panels had not yet been severely thinned by post-2013 attrition.  a clean temporal holdout, with no overlap with the 2019 primary evaluation year or the 2023 robustness check.

Inference is performed on two holdout years — 2019 and 2023. We use 2019 to select the best performing model and then run a series of robustness checks using the best model with 2023 data. 2019 is chosen as the primary evaluation year because it is a clean one-year temporal holdout after the training window, with full panels and no exogenous anomalies. 2020 is avoided because COVID-19 emergency measures systematically distort civil society, media, and judicial indicators, making the human panel mean a noisier target. 2023 is the last year of intact State Department and Freedom House reporting before a 2024 format restructuring, and panel sizes by that year are smaller on average due to continued post-2013 attrition, making it a harder test of the replacement scenario.

### Indicator scope

We analyze the universe of 206 v2 Type C V-Dem integer-based indicators that were still being coded by V-Dem in 2025 and with ≥ an average of 6 coders in the panel during the period of analysis. In total, 34 indicators of a total of 239 were filtered out using these criteria. The bulk of them (29) were excluded due to non-availability — three full modules (education content, media curriculum, and regime characteristics) and one additional indicator (v2temonitor) that V-Dem discontinued prior to the study period. A smaller number (4) were excluded because they are measured on a continuous rather than ordinal scale (v2svstterr, v2clsnlpct, v2mefemjrn) or are a recoded variant of an indicator already included in the analysis (v2exdfcbhs_rec). One indicator (v2smprivcon) was excluded for falling below the six-coder panel threshold — it has had a median of 4–5 coders per country throughout its entire coding history. 

### Source Data

For evidence packets we pull relevant sections from the State Department's Country Reports on Human Rights (CRHR), International Religious Freedom Reports (IRFR) and Freedom House Freedom in the World (FiW) Reports. Each report is highly structured in a way that makes mapping the sections to specific V-Dem indicators relatively straightforward. The sections were manually mapped to 206 Type C V-Dem indicators and the data pipeline assembles the relevent sections for the evidence packet and injects it into the prompt. In the handful of instances where no relevant sections map to a specific indicator, the model sees the executive summary of the State Department's CRHR and the FiW report. The executive summary of the IRFR is used where section 2c of the State Department CRHR is relevant because, during the period that we are anlayzing, section 2c always links to the IRFR.

## Metrics

The primary metric is AI mean absolute error (MAE), the absolute difference between the AI rating and the raw panel mean for each country-year-indicator, averaged across the evaluation pool. While the panel mean is not V-Dem's final output (which is produced by a Bayesian IRT model), but it is the natural target for evaluating how closely any single rater tracks the panel consensus. 

The identification claims are reported as three delta metrics, Δ(Evidence − Codebook), Δ(Anonymized − Codebook), and Δ(Anonymized − Evidence), each of which is the difference in AI MAE between two prompt conditions, bootstrapped at the country-year-indicator level. A negative delta means the added or modified prompt element reduced AI deviation from the panel mean, that is, improved calibration. Δ(Anonymized − Codebook) is the primary identification result. If it is negative, the calibration gain from source evidence holds even when country identity has been stripped, ruling out named-entity anchoring as the main driver of apparent calibration. Δ(Anonymized − Evidence) shows the additional gain from stripping country identity from text that already contains source evidence.

Five robustness analyses all run on 2023 data using the best-performing model from the primary 2019 analysis. Four retest the identification claims: a test-year replication reruns the winning model under all three primary conditions and compares the delta estimates to their 2019 counterparts; a few-shot calibration ablation reruns the evidence and anonymized conditions without calibration examples, isolating the marginal contribution of the few-shot block; an information shift test compares transition-adjacent country-years against stable ones to test whether Δ(Evidence − Codebook) is more negative where source evidence carries more novel information than stored knowledge of the country; and a re-identification test asks the model, after each anonymized coding call, to name its top three country guesses, comparing correctly re-identified cases against non-identified cases on signed deviation to test whether residual identity leakage drives the remaining compression signature. The fifth analysis — the agreement test — compares AI MAE against the average deviation of individual human coders from the same panel mean, testing whether AI deviation from the consensus falls within the range of normal expert disagreement. Thin-panel augmentation (adding one AI rating to 2023 country-years with ≤8 coders and measuring panel mean shift) is reported as an exploratory illustration in the appendix.

## Design summary

**Conditions (3)**: codebook-only; evidence (raw section text + few-shot calibration
examples); anonymized (country identity stripped + anonymized few-shot examples).

**Models (5)**: Llama 405B, 70B, 9B (open weights, GW Pegasus); Llama 70B FT-raw and
Llama 70B FT-anon (fine-tuned on raw and anonymized evidence respectively, V-Dem v15
coder ratings 2016–2018, all 206 mapped Type C indicators, ~898K training examples each).

**Evaluation**: 2019 (primary); 2023 (five robustness analyses, best model only). AI MAE
against panel mean with bootstrap CIs; signed deviation by quintile.

**Thin-panel augmentation (exploratory / appendix)**: for all 2023 CYIs with ≤8 coders,
`k=1` — does adding one AI rating to a thin panel shift the raw panel mean detectably?

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