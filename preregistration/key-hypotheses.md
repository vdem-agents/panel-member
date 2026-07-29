# Hypotheses

The central question at inference time: when the base model codes, is it drawing on
source evidence, or on country-identity priors activated by named entities in the text? We look at this question by testing the performance of a base model (Llama 3.3 70B Instruct) and three fine-tuned variants across four conditions: codebook only; raw evidence packets; anonymized evidence packets; and summarized evidence packets. Then we test the mechanism through which the information is working through a series of robustness checks, and finally ask whether the resulting model performs well enough to deploy. 

Our central metric throughout the analysis is AI MAE relative to the human panel mean. In the first part of the analysis, we test how well a single base model reproduces human panel ratings under four progressively de-identified prompt conditions — codebook only, raw evidence, anonymized evidence, and summarized evidence — to identify whether the model is drawing on source text or on country-identity priors. In the second part, we test three fine-tuned variants of the same base model, each trained on one of the three evidence types, to ask whether embedding calibration in the model's weights outperforms in-context few-shot examples, and whether training on de-identified text changes what the model learns to attend to. In the third part, we carry the best-performing model from parts one and two forward to 2023 and 2024 data and run a series of mechanism tests including a name-swap test, re-identification tests, and a temporal holdout. These tests are designed to isolate how textual information is actually influencing the model's ratings, independent of whether it improves fidelity to the panel mean. In the fourth part, we ask whether the carried-forward model's ratings are good enough to deploy: whether its AI MAE falls within the range of normal human panel disagreement.

## Note: equivalence band for interpreting small deltas

Because AI MAE is bootstrapped across roughly 32,800 CYI cells, even a trivially small MAE
difference can produce a confidence interval that excludes zero. Statistical significance
at this sample size is not the same as a substantively meaningful effect. We therefore
treat any MAE difference whose 95% CI falls entirely within 50% of that year's rounding
floor (see `preregistration/evaluation-metrics.md`; roughly 0.115 in 2019, and similarly
stable in 2023 and 2024) as not representing a substantively meaningful effect, regardless
of whether the CI technically excludes zero. This is an interpretive standard, not an
exclusion rule: point estimates and CIs are reported in full either way, and the band
changes how a result is described, not whether it is reported. Wherever a hypothesis's
null reading below (the "n" hypotheses) refers to "no difference" or similar language,
this band is the operational definition. On the delta coefficient plots, this can be drawn
as a shaded band around the zero reference line, so readers can see both whether a delta's
CI clears zero and whether it clears the band.

## Part 1 — Base-model identification tests (2019 data)

The first set of experiments look at how well the Llama base model performs when provided different types of evidence. The performance metric is mean average error of the AI rating relative to the human panel mean. 

### Model comparsion

Our primary base models combine evidence packets, which combine relevant sections of State Department Human Rights Reports and Freedom House Freedom in the World Reports, with few-shot country case calibration examples. 

- **B1** Evidence beats codebook-only: MAE(Evidence) < MAE(Codebook). If the model is taking into account the evidence packets, then the introduction of evidence packets and calibration examples should improve their ability to reproduce the ratings of human expert panels. 
  - **B1a** The country anchor activates weights from training that become distorted by the narrowly focused information in the provided text, resulting in *worse* performance. A second interpretation is that the model may be using the evidence but weighting or interpreting it differently than the human panel, producing genuine information-driven divergence rather than non-use. The two interpretations can be disambiguated by the name-swap test (R4) and signed-deviation diagnostics (Part 3).
  - **B1n** A null result would indicate that the model's performance is neither enhanced nor degraded by the provided text. 
- **B2** The information gain survives anonymization: MAE(Anonymized) < MAE(Codebook). If the model can extract real calibration signal from text alone, with zero country-identity information anywhere in the prompt, then anonymized evidence and calibration examples should beat a codebook-only baseline that has the country name but no text at all. This is the primary identification result because it rules out country name recall as the sole driver of improvement. 
  - **B2a** The country name and related information from training are doing most of the work, while de-identified text can't make up for losing it, such that anonymized performs *worse* than codebook-only.
  - **B2n** A null result would mean that the de-identified text and few-shot examples carry no detectable calibration value over a bare country-name prompt.
- **B3** Anonymization beats raw evidence: MAE(Anonymized) < MAE(Evidence). If country names act as an anchor pulling ratings toward the country's general reputation rather than what the specific text describes, then removing them should improve the model's ability to reproduce human panel ratings.
  - **B3a** The country anchor is *net beneficial* and supplements thin or ambiguous text rather than distorting it. A second interpretation is that the anonymization pass itself damaged evaluative content, since an LLM rewrite is not a surgical redaction and may discard genuinely evaluative detail independent of whether the identity itself carried any calibration value.
  - **B3n** A null result would indicate the model is not using country identity as a scale anchor either way.
- **B4** Summarization reduces residual identity leakage and improves on anonymized: MAE(Summarized) < MAE(Anonymized). Preliminary re-identification testing shows anonymized text remains substantially reidentifiable (~51–61% top-1, vs. a <30% target for summarized), which motivated adding summarization to the design. If that residual identifiability is functioning as a partial anchor, then summarization's sharper de-identification should further reduce anchoring-driven bias and improve calibration over anonymized.
  - **B4a** The abstraction cost of summarization outweighs the leakage-reduction benefit and summarized performs *worse* than anonymized because the generic rewrite discards genuinely evaluative content faster than it removes usable identity leakage. A second interpretation is that the summarized text still carries adequate signal, but the model weights or interprets that residual signal differently than the human panel does, producing divergence that reflects genuine information use rather than net content loss. The two are disambiguated the same way as B1a via the name-swap test (R4) and signed-deviation diagnostics (A8). 
  - **B4n** A null result would mean the residual identity in anonymized text was not functionally consequential for the model's ratings.

## Part 2 — Fine-tuning analysis (2019 data)

What happens when finetune the model rather than using few-shot examples, and which
mode of training produces the best raw-text coder? We explore three fine-tuned conditions--a model trained on *raw* unexpurgated evidence packets, a second trained on anonymized evidence packets, and a third trained on summarized packets. 

- **F1** Fine-tuning beats few-shot prompting under matched conditions, MAE(FT-Raw) < MAE(Base-Raw), MAE(FT-Anonymized) < MAE(Base-Anonymized), and MAE(FT-Summarized) < MAE(Base-Summarized). The rationale is that the larger number (up to 100K training examples) embed more calibration signal than five prompt exemplars can. The comparison deliberately excludes few-shot weights in favor of fine-tuned weights to enable the comparison of prompt-based calibration versus weight-based calibration.
  - **F1a** Fine-tuning introduces overfitting, thereby reducing performance relative to the base model on the held-out sample.
  - **F1n** Fine-tuning confers no benefit over base model weights.  
- **F2** Model performance on reproducing human ratings is conditioned by the extent to which they reduce re-identification bias, e.g. MAE(FT-summ:Evidence) < MAE(FT-anon:Evidence) < MAE(FT-raw:Evidence). If the text is providing useful information, then identity leakage resulting from named entities in the prompt or text will hurt model performance by inducing it to rely on pretrained knowledge rather than the textual evidence presented in the evidence packets. Anonymized evidence and further abstraction through summarization should therefore improve the ability of models to reproduce expert scores by focusing the model's attention on important textual details. We choose the raw evidence condition as the basis for the test, since it is the harder test relative to evaluating each model on the condition it was trained on. Only FT-raw trained on this exact distribution, so FT-anon and FT-summ face a distribution mismatch the ranking has to overcome.
  - **F2a** The abstraction cost of summarization outweighs the leakage-reduction benefit such that abstraction away from the raw text induces progressively *worse* performance, e.g. the anonymized and summarized text discard genuinely evaluative content more than they remove identity leakage. A second training-side reading is that fine-tuning on progressively de-identified text may teach the model to attend to different features of the input than fine-tuning on raw text does. These competing interpretations can be distinguished from the abstraction-cost reading by A8, which stratifies identity-reliance across FT-raw, FT-anon, and FT-summ specifically. Here a training-side divergent-weighting effect should show up as a residual salience gap not explained by content loss alone.
  - **F2n** The performance of the three conditions is roughly equal, suggesting either that re-identification bias and information loss balance out in training or that re-identification bias is not a substantial threat to model inference.  

## Part 3 — Robustness and mechanism tests (best model on 2023/2024 data)

It is important to note that AI MAE cleanly demonstrates information usage only when MAE shrinks under conditions of richer evidence. When MAE instead grows (e.g., MAE(Evidence) > MAE(Codebook), or MAE(Summarized) > MAE(Anonymized)), the pattern is ambiguous between two readings: (1) the model is not using the added information as intended, or uses it in a way that actively distorts calibration (e.g., anchoring on country identity); or (2) the model is using the information, but weights or interprets it differently than the human panel does, producing ratings that diverge from the human consensus. These readings are observationally identical in the MAE metric alone. This is the motivation for the tests in this section: the name-swap test asks directly whether ratings track described conditions or the named country, and the re-identification tests ask whether apparent MAE gains survive once residual identity leakage is accounted for — both independent of whether MAE against the panel improves or worsens. Where a 2019 result in Part 1 or 2 shows MAE growing under richer evidence, we treat it as an open question pending these checks, not a concluded null.

In this stage of the analysis, we test the generalization of the best carried-forward model beyond the 2019 validation set and to test a series of mechanism tests designed to isolate how textual information is influencing the performance of the models using data from 2023 and 2024. The model carried forward to stage 3 is whichever of the four models has the lowest 2019 AI MAE on the raw evidence condition. Our tie rule is that if bootstrap CIs overlap, prefer base as the simpler model. Where compute permits, we additionally run the full 2023/2024 battery on all four models rather than the carried-forward model alone. The confirmatory hypotheses below (R1–R5, D1) are registered against the carried-forward model only, per the selection rule above; however results from the non-carried models may be reported as exploratory cross-model comparisons.

- **R1** *Main results replication.* Replication of primary results will hold with 2023 data: MAE(Evidence) < MAE(Codebook), MAE(Anonymized) < MAE(Codebook), MAE(Anonymized) < MAE(Evidence), and MAE(Summarized) < MAE(Anonymized). The main results for the best model are recomputed for 2023 and compared to the 2019 estimates. If the identification results replicate in direction and magnitude, the decomposition tests generalize beyond the validation year.
- **R2** *Regime transitions test.* The evidence gain is larger for countries undergoing a regime transition. The gap between the evidence condition and the codebook condition MAE(Evidence) − MAE(Codebook), and the same for Anonymized and Summarized will be more negative for ERT-tagged transition-adjacent country-years than for stable ones. The carried model's frozen prior (whatever it learned during pretraining or fine-tuning) describes the country as it was at some point at or before 2019. In transition-adjacent years, that snapshot has fallen out of date with 2023 reality, so the evidence text that describes 2023 conditions directly should carry more marginal information than in stable years, where the frozen snapshot and the current text roughly agree. 
    - **R2n** The evidence gain across the three conditions does not differ from the baseline codebook condition. This would suggest that the evidence packets do not convey any useful information beyond what the model learned about regime transition years during pretraining (as the model's pretraining data for Llama 3.3 goes through 2023).   
- **R3** *2024 holdout test.* The evidence gain over codebook-only persists, or grows, in 2024 (the year after Llama 3.3's training cutoff). In 2024, input leakage (e.g. leakage of the textual evidence) is impossible given that the model was not trained on 2024 data. Thus, any difference between codebook only and the other conditions must be due to the presentation of new textual evidence. Since State Department reports change in format and substance in 2024, we run this test using Freedom House data only. The test includes the carried model across all four conditions with 2024 FH-only compared with a 2023 FH-only companion.
    - **R3n** The evidence gain vanishes in 2024, suggesting that the model is relying on stale information rather than the new textual evidence.  
- **R4** *Name-swap test.* Name-swap ratings track described conditions, not the named country. We take within-region country pairs and swap the names attached to the evidence packets, then ask the model to rate the country on the specified indicator. If the textual information matters, the model will base its ratings on the textual information and not the country name alone. We therefore expect the ratings of the swapped pairs to track more towards the panel mean of the actual source country described by the documents rather than the named country, e.g. MAE(Source) < MAE(Named), tested with a paired comparison, differencing within-case before resampling. 
  - **R4a** MAE(Named) < MAE(Source). Ratings anchor to the named country's identity rather than the described conditions, i.e., country-identity priors override the text even when they directly conflict with it.
  - **R4n** MAE(Source) ≈ MAE(Named). No systematic tracking either way, e.g., ratings land roughly between the two, or vary unpredictably when name and text conflict.
- **R5** *Re-identification test.* We use re-identification success on anonymized and summarized text as a salience filter. We expect the gap between MAE(Codebook) and MAE(Evidence) to be smaller for re-identified (salient) cases than for non-identified (non-salient) cases, because a strong competing prior lets the model discount the text for salient cases, while non-salient cases leave it more reliant on what the text actually says. (This is a tougher test for the non-salient group, since these cases likely also carry thinner source documentation, so results should be read alongside coverage tier (A10).)
  - **R5n** The gap between MAE(Codebook) and MAE(Evidence) does not differ between salient and non-salient cases, suggesting that salience does not affect how much the model relies on the text.
  - **R5a** The gap between MAE(Codebook) and MAE(Evidence) is larger for salient cases than for non-salient cases — evidence helps salient cases more, not less. This could happen if salient countries also have richer source documentation, and that richness outweighs the competing prior.

## Part 4 -- Deployment

- **D1** *Agreement test.* The carried-forward model's AI MAE, in its best evidence condition, is at or below the human LOO MAE (2019 diagnostic via the Figure 1 reference line; confirmatory test on 2023 data per the design doc's Agreement test). If AI MAE ≤ human LOO MAE, the model deviates from panel consensus by no more than a typical human coder.
  - **D1n** AI MAE exceeds human LOO MAE: the model's typical deviation from consensus is larger than normal human disagreement, meaning augmentation would measurably degrade panel quality even if the identification hypotheses (B1–B4) hold.
- **D2** *Thin-panel augmentation test.* Adding one AI rating to a thin panel (≤8 coders, 2023) does not shift the panel mean beyond normal human-coder replacement variance: the augmentation divergence stays below the empirically-derived 90th-percentile threshold computed from human-only coder swaps in the same pool.
  - **D2n** The divergence exceeds the threshold: adding an AI rating moves the panel mean more than a typical single-coder swap would, meaning augmentation is not safe even where the identification hypotheses (B1–B4) hold.

## Secondary tests and hypotheses

Hypotheses in Parts 1–4 above are confirmatory. The following hypotheses below are exploratory,
reported with the same bootstrap CIs but not treated as pass/fail tests of the paper's
central claims.

### Few-shot ablation

To tease out the effects of calibration examples relative to textual evidence, we run inference on each of the textual evidence conditions without the few shot calibration examples. 

- **A1** Zero-shot text alone, without calibration examples, still improves on codebook-only: MAE(Evidence-zeroshot) < MAE(Codebook), MAE(Anonymized-zeroshot) < MAE(Codebook), and MAE(Summarized-zeroshot) < MAE(Codebook). This is the test of genuine text-reading disentangled from the calibration-block confound.
  - **A1a** Zero-shot text performs worse than codebook in one or more conditions, suggesting that without calibration examples to anchor interpretation, added text actively confuses the model relative to having no text at all.
  - **A1n** A null across all three conditions would mean the model isn't using prompt content at all absent calibration anchors. This would be a stronger, more concerning finding than a per-condition null.
- **A2** We expect that the marginal value of the few-shot calibration examples will be conditioned by how much identity-based anchoring is available. The few-shot calibration gap for each condition — MAE(condition, few-shot) − MAE(condition, zero-shot) — should be close to zero for Evidence, and increasingly negative for Anonymized and Summarized. If country identity already provides the model with a scale anchor based on its pre-training, few-shot examples should contribute little to performance, but as anonymization and summarization progressively strip those anchors, the model should lean more on the calibration block to map described conditions onto the rating scales.
  - **A2a** The gradient reverses such the calibration gap is largest for evidence and shrinks through anonymized and summarized, implying identity and content cues make the model *more* reliant on calibration examples.
  - **A2n** The gap is roughly the same size across all three conditions, either uniformly large or uniformly near-zero, meaning calibration's marginal value doesn't interact with identity-anchor availability at all.

### Additional fine-tuning robustness

- **A3** Raw fine-tuning bakes in identity anchoring (the codebook probe): MAE(FT-raw:Codebook) < MAE(FT-anon:Codebook) < MAE(FT-summ:Codebook). We run inference using the fine-tuned models on the codebook-only condition (no textual evidence provided in prompts). If FT-Raw's number is much better than the FT-Anonymized or FT-Summarized models then it must be something FT-raw's weights learned during training, e.g. an association between the real country name and its typical rating, baked in because FT-raw's training data always paired real names with true ratings. We further anticipate that anonymized training text leaks identity more often than summarized, giving the model more incidental chances to learn a country-conditioned shortcut anyway.
  - **A3a** The gradient collapses to a flat step, FT-anon:Codebook ≈ FT-summ:Codebook, both well behind FT-raw:Codebook, meaning incidental re-identification during FT-anon training wasn't frequent enough to teach a shortcut — only explicit name-rating pairing (FT-raw) does.
  - **A3n** MAE(FT-raw:Codebook) ≈ MAE(FT-anon:Codebook) ≈ MAE(FT-summ:Codebook), net of the Base:Codebook floor, meaning training-time exposure to real names confers no detectable weight-level shortcut at all.
- **A4** Training-side analog of B4, operationalized as a difference-in-differences: `DiD = [MAE(FT-summ:Summarized) − MAE(FT-anon:Anonymized)] − [MAE(Base:Summarized) − MAE(Base:Anonymized)]` (the second bracketed term is B4's own delta). Bootstrapped at the CYI level. The training-time tradeoff replicates the inference-time tradeoff from B4 if DiD's CI falls within the equivalence band defined above (50% of that year's rounding floor on either side of zero, roughly 0.115 in 2019).
  - **A4a** DiD's CI falls entirely outside the equivalence band: training and inference diverge. Fine-tuning on summarized text either erases much more of the tradeoff than reading it at inference did, or makes it much worse, meaning the training process itself changes how much the de-identification/specificity tradeoff matters, rather than just inheriting it from the text.
  - **A4n** DiD's CI straddles the equivalence band boundary: inconclusive, insufficient precision to distinguish replication from divergence.
- **A5** Training-representation transfer to raw text. FT-anon and FT-summ, despite never training on raw evidence, still beat the base model when reading raw evidence at deployment: MAE(FT-anon:Evidence) < MAE(Base:Evidence) and MAE(FT-summ:Evidence) < MAE(Base:Evidence). This is because the calibration and text-reading ability learned from de-identified text carries over to raw text, which represents a superset of what they trained on.
  - **A5a** The representation mismatch dominates instead: FT-anon and/or FT-summ perform worse than Base on raw evidence, because real names and other identity cues at test time are inputs the model never learned to handle, and the mismatch outweighs whatever generic calibration fine-tuning provided.
  - **A5n** FT-anon/FT-summ ≈ Base on raw evidence: fine-tuning on de-identified text transfers neither positively nor negatively when the input distribution shifts this much.

### Additional re-identification robustness

- **A6** *Re-identification diagnostic.* We ask the model to try to re-identify the countries in anonymized and summarized text. We expect that summarization achieves materially lower re-identification rate than anonymization because summarization abstracts further from the original text than anonymization. 
  - **A6n** Summarization does not achieve a lower re-identification rate than anonymization, suggesting that summarization does not meaningfully improve de-identification over anonymization.
  - **A6a** Summarization achieves a higher re-identification rate than anonymization, suggesting that distilling text down to only the most distinctive traits can make a country easier to guess, not harder.
- **A7** *Re-identification predicts directional bias.* In the anonymized and summarized conditions, cases where the model correctly re-identifies the country show larger directional (signed) deviation from the panel mean than non-identified cases — too high for autocracies, too low for democracies — consistent with anchoring on a recovered country prior. Reported by regime type and by region.
  - **A7n** Signed deviation does not differ by re-identification status, in either regime type or region, suggesting re-identification does not trigger directional anchoring even when it occurs.
- **A8** *Re-identification: salience gap by model.* By the same logic, de-identified training should blunt this salience effect. FT-raw should replicate the base model's salience gap, since its weights learned to pair real country names with ratings. FT-anon and FT-summ, whose training data never paired a real name with a rating, should show a smaller gap between salient and non-salient cases.
  - **A8n** The salience gap is about the same for FT-raw, FT-anon and FT-summ, suggesting that the training regime does not change how much the model leans on identity for salient cases.

### Coverage

- **A9** *Source coverage test (2023).* Calibration degrades with weaker source coverage: AI MAE is higher for weak-coverage indicators than for strong-coverage indicators, across all conditions, for the carried-forward model. Other models are covered only where the exploratory multi-model extension (Part 3 intro) actually runs them. 

## Terminology note: "re-identification bias"

"Re-identification" is standard vocabulary from the privacy/de-identification literature
(re-identification risk, re-identification attack on de-identified records). "Re-
identification bias" as a compound is not an established term of art, but is a coherent
coinage for what A8 measures most directly, and R5/A9 measure as a related magnitude-based
signature: directional rating error induced when the model covertly
recovers a de-identified country's true identity and anchors on its prior. Recommend
defining the term at first use and connecting it explicitly to its established neighbors —
anchoring bias, training-data memorization — rather than presenting it as borrowed
vocabulary.

## Notes

- We are finetuning on the text response from the JSON, but do we want to consider a prediction head as a fallback? This has nothing to do with hypotheses or preregistration, just wanted to get it down for consideration next week. 
- 98-CYI re-identification pilot (2019, exec-summary ablation) is excluded from the confirmatory 2019 evaluation pool -- decided. Still need to: (1) extract the 98 (iso, year, indicator) keys, identifiable from `logs/reidentify_2019_73420878.json` (98 unique CYIs, reused across the summarized/no-exec/anon-no-exec follow-up runs), into a checked-in exclusion list, e.g. `config/pilot_reid_98cyi_exclusions.csv`; (2) wire that filter into whichever pipeline step materializes the confirmatory 2019 pool; (3) write the exclusion into `experimental-design.md`'s Pilot work disclosure, resolving its open checkbox.

