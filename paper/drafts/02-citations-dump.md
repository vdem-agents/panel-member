# Theory-section citations — candidate list

*Assembled 2026-09-06 from the `notes/` scan. Grouped by the point in `theory.md` each
supports. Status column: **have-ref** = full metadata in a repo note or a PDF in the shared
library, verified on the date shown; **verify** = identifier or venue needs confirming against
the published version; **find** = a claim we want to make but no citation located yet.*

PDF library is the shared **`v-dem-coding/_literature/`** (one level above this repo, shared
with the bridge-coder paper — not a repo-local folder). It already holds Benoit et al. and
Weidmann et al., plus `annotated-bibliography.md` / `benoit-comments.md`. BibTeX keys go in
`paper/references.bib` (path from the manuscript: `../../_literature/` for PDFs, but the `.bib`
itself lives in `paper/`). Nothing has been added to `references.bib` yet.

---

## A. LLMs as political / text coders — "it works", mechanism unaddressed

The gap this paper fills: correlation with expert labels is established; none decompose
reading vs. reciting. Sources: `notes/prior-work-experimental-contamination-tests.md`,
`_literature/` (Maerz pieces added 2026-09-06), `paper/drafts/seraphine-questions.md` (EJT's
own statement of the motivation, written to Seraphine Maerz — a drafting source for §1).

| Ref | Identifier | Note | Status |
|---|---|---|---|
| Weidmann, Faulborn & Garcia 2025, "Large Language Models Are Democracy Coders with Attitudes", *PS: Political Science & Politics* | PS 59(1):17--23, doi:10.1017/S1049096525101248 | **The anchor / foil.** Same V-Dem Type-C terrain. Reads countries from internal knowledge, finds directional "attitudes". Positioning: they characterize the prior, we test whether evidence displaces it. Also the rebuttal target for the readout point (some "attitudes" = single-point-readout artifact). | have-ref — published PDF `_literature/Weidmann et. al. 2026 - LLMs are Democracy Coders with Attitudes (PS published).pdf` (open access, CC BY 4.0). **Confirmed 2026-09-10:** no evidence text (bare codebook prompt, online appendix B); the "post-cutoff" claim is about the v14 *release date*, not the coded year — 2023 sits inside both models' training windows. Appendices are online supplementary material. |
| Maerz & Weidmann 2026, "Improving V-Dem Coding Transparency with Large Language Models (LLMs)" | — (V-Dem pilot / working paper) | **Concurrent companion work, same team + terrain.** Proposes LLMs that generate *verifiable, source-referenced* background information for human V-Dem coders (decision support, not a replacement coder). `qallmer` pipeline, web-enabled, URL HEAD-checks; pilot on v16 `v2csreprss`. Their step 2 defaults to "no change unless dated evidence supports one" — the persistence/carry-forward prior built into the design, directly relevant to our movement/staleness mechanism. Positioning: they keep the human in the loop and make the evidence auditable; we ask whether the model *itself* reads that evidence or recites a prior. Was to be EJT + Maerz co-authored; Maerz found the prereg confusing (a reason it's set aside). | have-ref — PDF `_literature/Maerz and Weidman 2026 - V-Dem pilot.pdf` |
| Maerz, Schafer & Schneider 2026, "Listening to Leaders: Illiberal Speech as a Symptom of Democratic Decline" | — | Fine-tune DeBERTa to score 28,237 leader speeches on an illiberal–liberal scale; validated against GPT-5.2 and human coders. Cite as (a) fine-tuned transformers for political-regime text measurement, (b) LLM-as-validator practice, (c) the "Maerz is central to this literature" anchor. Mine its bibliography for PSC players. | have-ref — PDF `_literature/Maerz et. al. 2026 Listening to Leaders.pdf` |
| Benoit, De Marchi, C. Laver, M. Laver & Ma 2026, "Using large language models to analyze political texts through natural language understanding", *AJPS* | doi:10.1111/ajps.70050 | **Closest methodological antecedent.** Two-stage pipeline: LLM writes a 300–400 word summary of a manifesto's position, then LLMs score the summary — i.e. our "summarized" condition done as the whole method. GPT-4o / Claude 3.5 / Gemini 1.5, replicated on the same open models we use (Llama-3.3-70B-Instruct, Gemma-3-27B, DeepSeek-V3). Strong correlations vs CHES / Laver–Hunt; leakage not ruled out (see `benoit-comments.md` — the identification gap our codebook/evidence/anonymized design fills). Also the anchor for group G (summarize-then-score as established practice). | have-ref — PDF in `_literature/`, annotated |
| Le Mens & Gallego 2025, "Positioning Political Texts with Large Language Models by Asking and Averaging", *Political Analysis* | arXiv:2311.16639 | r > .90 vs expert/roll-call, no memorization decomposition. "Asking and averaging" is also an expectation-readout cousin. | have-ref (2026-07-31) |
| Heseltine & Clemm von Hohenberg 2024, "Large Language Models as a Substitute for Human Experts in Annotating Political Text", *Research & Politics* | doi:10.1177/20531680241236239 | "It works" register, mechanism unaddressed. | have-ref (2026-07-31) |
| "Codebook LLMs: Evaluating LLMs as Measurement Tools for Political Science Concepts" 2024 | arXiv:2407.10747 | Closest by title; contribution is codebook-following via instruction tuning; no de-identification / holdout. | have-ref (2026-07-31) |
| Gilardi, Alizadeh & Kubli 2023, "ChatGPT outperforms crowd workers for text-annotation tasks", *PNAS* | — | Crowd-worker benchmark, not calibrated experts; the identification problem remains. Cited in the Maerz & Weidmann pilot. | verify |
| Little & Meng 2024 | — | Criticism of V-Dem's strong reliance on subjective human coding of political characteristics. Cited in the Maerz & Weidmann pilot as the critique motivating LLM-assisted coding. Relevant to §1 motivation. | find (full ref — in the pilot's bibliography) |
| Reich et al. 2025, HALC pipeline for automated social-science coding | arXiv:2507.21831 | For structured coding, labeled examples + prompt strategy drive performance, not role framing. Supports the fine-tuning lever and the persona-set-aside. | have-ref (2026, in persona archive) |

## B. Parametric vs. contextual knowledge / knowledge conflict (the "how it reads" hinge)

Source: `paper/annotated-bib.md`, `_literature/annotated-bibliography.md`,
`notes/proposed-mechanism-tests.md` §7.

| Ref | Identifier | Note | Status |
|---|---|---|---|
| Xu et al. 2024, "Knowledge Conflicts for LLMs: A Survey", *EMNLP 2024*, 8541–8565 | — | Establishes "parametric vs. contextual knowledge" as the standard vocabulary; context-memory conflict is exactly B1–B4 / R4. Preferred framing over "anchoring". | have-ref (annotated-bib) |
| Longpre et al. 2021, "Entity-Based Knowledge Conflicts in Question Answering", *EMNLP 2021*, 7052–7063 | aclanthology 2021.emnlp-main.565 | Originates entity-substitution; models over-rely on parametric knowledge, worse for high-frequency entities. Structural twin of the name-swap test; the frequency result is also the prominence-confound rationale (stronger priors for France/US than Eswatini/Bhutan → stratify by salience). | have-ref (both annotated bibs) |
| Xie, Zhang, Chen et al. 2024, "Adaptive Chameleon or Stubborn Sloth: Revealing the Behavior of Large Language Models in Knowledge Conflicts", *ICLR 2024* (Spotlight) | — | Models follow context when the conflicting passage is fluent and coherent, revert to priors when it reads as odd. Central caution for the "how it reads" hinge **and** the rewrite-artifact confound: anonymized/summarized text that reads as strange could suppress content-following for the wrong reason. | have-ref (`_literature/annotated-bibliography.md`) |
| Neeman et al. 2022, "DisentQA: Disentangling Parametric and Contextual Knowledge with Counterfactual Question Answering" | — | Counterfactual QA to separate the two knowledge sources. | verify |

## C. Entity as shortcut — masking and replacement (name-swap / R4 lineage)

Source: `notes/anonymization-summarization-concept-origins.md`, `notes/name-swap-design.md`.

| Ref | Identifier | Note | Status |
|---|---|---|---|
| Wang et al. 2022, "Should We Rely on Entity Mentions for Relation Extraction? Debiasing Relation Extraction with Counterfactual Analysis", *NAACL-HLT 2022* | aclanthology 2022.naacl-main.224 | Anchor for entity-bias / masking. Key nuance: *naive* full masking hurts (destroys entity semantics); the useful version strips the identifier, keeps the described conditions — which is what our anonymization does, and plausibly why FT-anon stayed strong. | have-ref (2026-08-30) |
| "How Fragile is Relation Extraction under Entity Replacements?" | arXiv:2305.13551 | RE-side twin of the name-swap: swap entities, check whether predictions follow text or name. | verify (authors/venue) |
| Manchanda & Shivaswamy 2025, "What is in a name? Mitigating Name Bias in Text Embeddings via Anonymization" | arXiv:2502.02903 | Closest recent analog: anonymize to kill an identity shortcut, adjacent task (embeddings). | have-ref (2026-08-30) |
| Vallejo Vera & Driggers 2025, "Bias in LLMs as Annotators: The Effect of Party Cues on Labelling Decisions", *Humanities and Social Sciences Communications* | arXiv:2408.15895 / nature.com/articles/s41599-025-05834-4 | Two authors (Sebastian Vallejo Vera, Hunter Driggers), not "et al." Name-swap estimand borrowed from here (cue-as-treatment, content held fixed via per-item effects). Party → country is the substitution. Nearest political-science cousin to R4. | have-ref (both annotated bibs) |
| Ennser-Jedenastik & Meyer 2018 | — | Human manifesto coders are biased by the party label attached to the same text; the study Vallejo Vera & Driggers replicate with LLMs. Cite as the origin of the party-cue design. | find (full ref) |

## D. Shortcut learning / annotation artifacts / input-ablation method (Codebook-only logic)

General ML/NLP grounding for "strip the input and see if performance holds". Source:
`notes/proposed-mechanism-tests.md` §7, `notes/anonymization-summarization-concept-origins.md`.

**Where these go (2026-09-20).** Only Geirhos (and now McCoy 2024) belongs in the theory
section; it is a claim about how models behave. The other five are *method* precedents that
attach to specific conditions in the design (Codebook-only, the de-identification ladder, the
name-swap) and read as clutter in theory, as justification in §4. Their BERT-era vintage does
not matter there, because we borrow the experimental logic, not the finding.

**The era answer for the framing half.** EJT flagged that this group is pre-LLM. Two modern
successors located and verified 2026-09-20. **McCoy et al. 2024 (PNAS) is the pick** — same
first author as the HANS paper below, so the pairing gives a through-line from "right for the
wrong reasons" in 2019 to the LLM-era version. Du et al. is the review if one sentence should
cover the whole modern literature instead.

| Ref | Identifier | Note | Status |
|---|---|---|---|
| Geirhos et al. 2020, "Shortcut Learning in Deep Neural Networks", *Nature Machine Intelligence* 2(11):665–673 | doi:10.1038/s42256-020-00257-z | Highest-level "why" for anonymization / the reading-vs-shortcut framing. Cross-domain (cows on grass, pneumonia classifiers keying on hospital markers); supplies the vocabulary — shortcut, Clever Hans behavior, i.i.d. vs o.o.d. testing — and the argument that in-distribution accuracy cannot tell you which rule was learned. Keep as the concept cite. | have-ref (2026-08-30) |
| **McCoy, Yao, Friedman, Hardy & Griffiths 2024, "Embers of autoregression show how large language models are shaped by the problem they are trained to solve", *PNAS* 121(41): e2322420121** | doi:10.1073/pnas.2322420121 / arXiv:2309.13638 | **The modern evidence cite, and the answer to "is this still true of current models".** Argues next-token prediction leaves traces in behavior even on deterministic tasks, so accuracy depends on output probability and task frequency rather than task structure alone. The demonstration is quotable: GPT-4 counting items in a list is 97% accurate when the answer is 30 and 17% accurate when the answer is 29, because 30 is the more probable string. Same first author as McCoy et al. 2019 (HANS) below. PNAS also reads better to a PSC reviewer than an ACL venue. **Scope caveat:** this is about output probability and task frequency, not entity shortcuts — it supports "the training objective shapes behavior in ways accuracy does not reveal" (our framing claim), *not* "the model uses country names as a shortcut". Titles differ between arXiv and PNAS; cite the PNAS wording. | have-ref — PDF `_literature/McCoy et. al. 2024 - Embers of Autoregression (arXiv preprint of PNAS).pdf`. **Note: this is the arXiv preprint, 84pp with appendices** — pnas.org is behind Cloudflare and would not fetch. Pull the published PDF through the GW library before final submission; cite the PNAS version regardless. |
| Du, He, Zou, Tao & Hu 2024, "Shortcut Learning of Large Language Models in Natural Language Understanding", *Communications of the ACM* 67(1): 110–120 | doi:10.1145/3596490 / arXiv:2208.11857 | The direct successor to Geirhos for the language case: LLMs rely on dataset bias and artifacts as shortcuts, with consequences for generalizability and adversarial robustness. It is a **review**, so it is the efficient cite if one sentence should cover the modern literature rather than a specific finding. Second choice behind McCoy; do not cite both unless the paragraph needs the survey. | have-ref — PDF `_literature/Du et. al. 2024 - Shortcut Learning of LLMs in NLU (CACM).pdf` (arXiv version, 10pp) |
| Poliak et al. 2018, "Hypothesis Only Baselines in Natural Language Inference" | — | Input-ablation precedent (evaluate with half the input removed). Codebook-only analog. | verify |
| Gururangan et al. 2018, "Annotation Artifacts in Natural Language Inference Data" | — | Models exploit artifacts, not the intended signal. | verify |
| McCoy, Pavlick & Linzen 2019, "Right for the Wrong Reasons: Diagnosing Syntactic Heuristics in Natural Language Inference", *ACL 2019* | — | Right answer, wrong mechanism — the whole motivation for the decomposition. Identifies three heuristics NLI models use (lexical overlap, subsequence, constituent) and builds an adversarial set where they fail; models fall to near or below chance. The most quotable line in the group, and the 2019 half of the McCoy pairing (see McCoy et al. 2024 above). Method cite, so §4 not theory. | verify |
| Kaushik, Hovy & Lipton 2020, "Learning the Difference that Makes a Difference with Counterfactually-Augmented Data" | — | Counterfactual data as diagnostic; supports the name-swap design. | verify |
| Gardner, Artzi, Basmov, Berant, Bogin, Chen, Dasigi, Dua, Elazar, Gottumukkala, Gupta, Hajishirzi, Ilharco et al. 2020, "Evaluating Models' **Local Decision Boundaries** via Contrast Sets", *Findings of EMNLP 2020*, 1307–1323 | aclanthology 2020.findings-emnlp.117 / arXiv:2004.02709 | Perturb the input minimally, watch the prediction. Dataset authors perturb their own test instances just enough to flip the gold label; model accuracy drops far more than human accuracy. Parent for the name-swap. Method cite, so §4. **Title corrected 2026-09-20** — this group previously recorded it as "Evaluating NLP Models via Contrast Sets", which is not the published title. ~30 authors, so `et al.` throughout. | have-ref — PDF `_literature/Gardner et. al. 2020 - Evaluating Models' Local Decision Boundaries via Contrast Sets (Findings EMNLP).pdf`, verified 2026-09-20 against ACL Anthology |

**Also checked, not taken (2026-09-20):** Yuan, Zhao, Zhang, Zheng & Liu 2024, "Do LLMs Overcome
Shortcut Learning? An Evaluation of Shortcut Challenges in Large Language Models"
(arXiv:2410.13343) is the most directly on-point empirical test — modern LLMs still rely on
shortcuts, and *larger* models are more susceptible under standard prompting, which rhymes with
Zhu et al.'s "stronger models degrade faster" in §K. Held in reserve only because it is an
unpublished preprint. There is also a 2024 survey on shortcut learning specifically in
in-context learning (arXiv:2411.02018), unexamined, which may matter for the few-shot condition.

## E. Data contamination / leakage 

Source: `notes/data-leakage-contamination.md`, `notes/prior-work-experimental-contamination-tests.md`.

| Ref | Identifier | Note | Status |
|---|---|---|---|
| Golchin & Surdeanu 2023, "Time Travel in LLMs: Tracing Data Contamination in Large Language Models" | — | Post-cutoff / temporal probing for contamination. Supports the 2024 holdout logic. | verify |
| "A Survey on Data Contamination for LLMs" 2025 | arXiv:2502.14425 | Generic benchmark-leakage taxonomy. | have-ref (link only) |
| "NLP Evaluation in Trouble: ... Measuring LLM Data Contamination" | arXiv:2310.18018 | Contamination taxonomy (guideline / text / annotation). | have-ref (link only) |
| LLMLagBench, "Identifying Temporal Training Boundaries" | arXiv:2511.12116 | Training-cutoff identification. | have-ref (link only) |
| ConStat | — | Named in the PS scan as a contamination-detection method; no ID recorded. | find |

## F. Anonymization / de-identification (method-side, cite only if we discuss tooling)

Source: `notes/anonymization-summarization-concept-origins.md`.

| Ref | Identifier | Note | Status |
|---|---|---|---|
| "Robust Utility-Preserving Text Anonymization Based on LLMs" | arXiv:2407.11770 | How-to for LLM anonymization; tooling citation. | have-ref (link only) |
| "Anonymization by Design of Language Modeling" | arXiv:2501.02407 | Anonymization-by-design LM; tooling citation. | have-ref (link only) |
| Clinical / privacy de-identification tradition | — | Long tradition of training on de-identified text; motivation is privacy, not generalization — weaker parent, cite for completeness. | find (representative ref) |

## G. Summarizing the evidence before scoring — established practice, and the leakage claim

Two distinct points. (1) **Summarize-then-score is established practice** in LLM text
measurement — Benoit et al. 2026 (group A) is the anchor: their whole method is an LLM summary
of the source followed by LLM scoring of the summary. EJT: "maybe not to prevent leakage, but
summarizing is common" — collect a few more examples. **Filled 2026-09-20**, with a caveat: in
political science the practice is thinner than "common" implies. Two instances (Benoit;
Maerz & Weidmann), one pre-LLM lineage (extract-then-score on the same country-report corpus),
and two NLP parents whose motivation is cost and retrieval noise rather than leakage. Claim it
is *established*, not that it is common. (2) **The leakage-prevention rationale**
is a narrower political-science claim (a fresh paraphrase cannot carry a memorized
country→label association) that `notes/anonymization-summarization-concept-origins.md` says to
attribute to a specific source. No standard ML precedent for LLM-summary-as-*training*-input.
Frame our summarized result as a test of claim (2), positioned within practice (1).

| Ref | Identifier | Note | Status |
|---|---|---|---|
| Benoit, De Marchi, C. Laver, M. Laver & Ma 2026 (group A) | doi:10.1111/ajps.70050 | Summarize-then-score as the method — practice anchor for (1). | have-ref — PDF in `_literature/` |
| Maerz & Weidmann 2026 (group A) | — (V-Dem pilot / working paper) | **The V-Dem-side instance, same terrain as ours.** A web-enabled LLM generates verifiable, source-referenced background information per country-year-indicator, and that generated text is what the coder works from. The scorer is human rather than a model, but the architecture is ours: compress the sources, then judge the compression. Best second cite for (1). | have-ref — PDF `_literature/Maerz and Weidman 2026 - V-Dem pilot.pdf` |
| Cordell, Clay, Fariss, Wood & Wright 2022 (*ISQ*); Park, Greene & Colaresi 2020 (*APSR*) | doi:10.1093/isq/sqac016; doi:10.1017/S0003055420000258 | **The pre-LLM lineage, already cited in `intro-citations.md` Move 1.** Both extract structured records (allegations; judged rights) from State Dept country reports and score or aggregate the extraction rather than the raw document. Extract-then-score is the older form of the same two-stage design, on the same source corpus we use. Worth one clause, because it shows the architecture predates the leakage worry entirely. | have-ref (via `intro-citations.md`) |
| Xu, Shi & Choi 2024, "RECOMP: Improving Retrieval-Augmented LMs with Compression and Selective Augmentation", *ICLR 2024* | — | Compresses retrieved documents into summaries (extractive and abstractive) before the LM uses them. The closest NLP statement of "summarize the evidence before the model reads it". Motivation is retrieval noise and context length, not leakage — which helps us: compression before scoring is a recognized move made for ordinary reasons, and our contribution is asking what it does to the identity signal. **Recalled from memory 2026-09-20 (cutoff May 2026), not looked up; verify authors/venue/identifier.** | verify |
| Jiang, Wu, Lin, Yang & Qiu 2023, "LLMLingua: Compressing Prompts for Accelerated Inference of Large Language Models", *EMNLP 2023* (+ LongLLMLingua follow-up) | — | Prompt compression before inference. Footnote-tier; include only if RECOMP needs company. Same caveat as RECOMP on motivation. **Recalled from memory 2026-09-20, not looked up; verify.** | verify |
| The specific PS source(s) making the "summarize to prevent leakage" argument | — | Needed before submission. **Still not found as of 2026-09-20** — recommendation is to stop looking and not attribute it: state the leakage rationale as ours and let the summarized condition test it. | find (likely does not exist) |
| Information bottleneck / feature-ablation (loose ML parents) | — | Only if we want an ML framing for compression-strips-nuisance-detail. | find |

## H. Persona prompting / silicon samples (why persona was the set-aside lever)

Source: `notes/persona-prompting-design-archive.md`.

| Ref | Identifier | Note | Status |
|---|---|---|---|
| Argyle et al. 2023, "Out of One, Many: ... Simulate Human Samples", *Political Analysis* | — | The optimistic anchor; has not replicated cleanly. | verify |
| Bisbee, Clinton, Dorff, Kenkel & Larson 2024, "Synthetic Replacements for Human Survey Data? The Perils of Large Language Models", *Political Analysis* 32(4):401–416 | — | Silicon-sampling personas: aggregate scores track ANES but variance is too low and inference breaks. Useful *contrast* — our task rates specific text against a codebook, not a demographic persona, so the low-variance failure may not transfer. Do not overweight. | have-ref (`_literature/annotated-bibliography.md`; PDF not in folder yet) |
| Morocho et al. 2026, ACM Web Conference 2026 | arXiv:2602.18462 | Most direct: persona prompting "does not yield a clear aggregate improvement ... in many cases significantly degrades performance". | have-ref (2026, persona archive) |
| "When Can Digital Personas Reliably Approximate Human Survey Findings?" 2026 | arXiv:2605.10659 | Original claims overstated; answer is conditional. | have-ref (link only) |

## I. Readout as estimand — mode vs. mean, CE recovers the conditional distribution

Source: `notes/decode-readout-and-coder-roles.md`, `notes/ft-calibration-overconfidence-finding.md`
§4. Readout-as-estimand is framed as this paper's own contribution; the underlying facts are
textbook.

| Ref | Identifier | Note | Status |
|---|---|---|---|
| Cross-entropy / proper scoring rules recover `p(y\|X)`; argmax = mode, `Σ y·p(y)` = mean | — | Textbook (e.g. Bishop, *PRML*). Cite a standard source for the one-prompt-many-labels → conditional-distribution fact. | find |
| Loss determines the statistic (MSE→mean, L1→median, CE→distribution/mode) | — | Standard; may not need a cite, or fold into the above. | find |

## J. Human disagreement as signal, and calibration to it

Source: `notes/ft-calibration-overconfidence-finding.md` §4. **All memory-sourced, cutoff Jan
2026 — every one needs verifying, and no PDF for any of them is in `_literature/` as of
2026-09-21.** Uma and Plank are the only two already in `references.bib`.

**Promoted 2026-09-21.** This group was filed under "calibration" and treated as optional
background. Under the two-estimands reframe (`notes/act1-reinterpretation-and-alternative-framing.md`)
it becomes load-bearing: it is what licenses the claim that a synthetic coder should reproduce the
*shape* of human disagreement rather than converge on a consensus label, and it carries the
fine-tuning prediction. Pull and verify these before drafting the theory section.

Three layers, and they do different jobs:

- **J1. There is no single gold label** — the framing layer, and the one the list was missing.
  These argue that annotator disagreement on a genuinely ambiguous item is a property of the item,
  not annotator error, so collapsing to a majority label discards information. This is the general
  form of the argument the V-Dem panel makes concrete.
- **J2. Train on the spread** — the method layer. Training on disaggregated or soft labels
  recovers the label distribution. Carries the fine-tuning prediction.
- **J3. Instruction tuning destroys calibration** — the background layer, cited so the
  fine-tuning result reads as restoring something known to be lost rather than as a discovery.

### J1. There is no single gold label (framing) — all recalled 2026-09-21, none verified

| Ref | Identifier | Note | Status |
|---|---|---|---|
| Aroyo & Welty 2015, "Truth Is a Lie: Crowd Truth and the Seven Myths of Human Annotation", *AI Magazine* 36(1) | — | The usual origin cite for "a single gold label misrepresents the task". Names the assumption — that each item has one correct annotation — as a myth rather than a simplification. **Recalled, not read. Confirm volume/pages/venue.** | verify |
| Pavlick & Kwiatkowski 2019, "Inherent Disagreements in Human Textual Inferences", *TACL* 7 | — | The linguistics-side demonstration: annotator disagreement on inference items is *reproducible* — collect more annotators and the same split reappears — so it is a property of the item, not noise. Closest in spirit to the V-Dem panel's persistent spread. **Recalled, not read.** | verify |
| Nie, Zhou & Bansal 2020, "What Can We Learn from Collective Human Opinions on Natural Language Inference Data?" (ChaosNLI), *EMNLP* | — | Collects ~100 labels per item and shows models matching the majority label still miss the label *distribution*. The direct analogue of "right MAE is not enough, the shape has to match". **Recalled, not read; label count especially needs checking.** | verify |
| Cabitza, Campagner & Basile 2023, "Toward a Perspectivist Turn in Ground Truthing for Predictive Computing", *AAAI* | — | The programmatic statement of the position (the "perspectivist" data manifesto). Optional — include only if the paragraph wants a named research programme rather than individual findings. **Recalled, not read.** | verify |

### J2–J3. Train on the spread, and what instruction tuning did to calibration

| Ref | Identifier | Note | Status |
|---|---|---|---|
| OpenAI 2023, GPT-4 Technical Report | — | Headline cite: base well-calibrated, RLHF destroys it. | verify |
| Guo et al. 2017, "On Calibration of Modern Neural Networks", *ICML* | — | Foundational NN miscalibration. | verify |
| Uma et al. 2021, "Learning from Disagreement: A Survey", *JAIR* | — | Training on soft / disaggregated labels recovers the label distribution. | verify |
| Peterson et al. 2019, CIFAR-10H | — | Human uncertainty as soft labels. | verify |
| Plank 2022, "The 'Problem' of Human Label Variation", *EMNLP* | — | Human label variation is signal, not noise. | verify |
| Baan et al. 2022, "Stop Measuring Calibration When Humans Disagree", *EMNLP* | — | Nearly our exact setup. | verify |
| Müller et al. 2019, "When Does Label Smoothing Help?", *NeurIPS* | — | Mechanism for soft-label calibration. | verify |

## K. Movement / staleness mechanism

Source: `notes/regime-movement-staleness-design.md`. **Guidance (2026-09-06):** the movement
mechanism does not need its own large literature. It is a corollary of two things already
being cited: (a) a model's parametric knowledge is frozen at pretraining and degrades for
anything that changed since — the **temporal-generalization** literature below; and (b) models
over-rely on parametric knowledge even when the context contradicts it — **group B**. The
movement figures (4, 6, 7) are then "the stale-prior prediction that follows from (a) + (b)":
where a country moved a lot since the training window, the prior is not just present but
wrong, and the model leans on it anyway. Cite 2–3 of the temporal-generalization papers, lean
on group B for the rest, and use Weidmann (group A) as the evidence that the country prior is
real in this exact V-Dem setting. Mallen et al. is the useful bridge: parametric memory fails
on the long tail / non-static facts, and that is exactly where supplied evidence should help.

**The era problem, and the fix (2026-09-20).** EJT flagged that this group is dated: Lazaridou
is Transformer-XL measured in perplexity, Luu and Dhingra are T5-scale, and our models are
Llama 3.3, Qwen 2.5 and Gemma 3. The distinction that resolves it is between *concept* cites
and *evidence* cites. Lazaridou states a structural fact (parametric knowledge is frozen at the
cutoff) that does not depend on architecture, so cite it for the concept and never as evidence
about our models. For the live claim, cite **Zhu et al. 2025** (below), which evaluates
contemporary LLMs post-cutoff. Note also that the direction of change in the field cuts our
way: instruction tuning, RAG and long contexts all predict that supplied evidence *should*
dominate the prior in 2025 models, and our results say it does not. That makes the finding more
surprising, not less, and it is a better framing than pretending the 2021 papers settle it.
**Recommended set: Lazaridou (origin) + Zhu (current) + Mallen (bridge). Cut Luu and Dhingra,
or footnote one.**

| Ref | Identifier | Note | Status |
|---|---|---|---|
| Lazaridou, Kuncoro, Gribovskaya, Agrawal, Liska, Terzi, Gimenez, de Masson d'Autume, Kocisky, Ruder, Yogatama, Cao, Young & Blunsom 2021, "Mind the Gap: Assessing Temporal Generalization in Neural Language Models", *Advances in Neural Information Processing Systems* 34 | arXiv:2102.01951 | **Concept cite.** LMs degrade on text from after their training period. Core "knowledge is frozen at cutoff" reference and the origin the rest of this group cites. Caveat: Transformer-XL, measured in perplexity on news and arXiv streams, so do **not** use it as evidence about Llama/Qwen/Gemma — pair with Zhu et al. for that. Fourteen authors, so `et al.` in text; "Mind the Gap" is a very common title, so carry the subtitle in the bib entry. NeurIPS proceedings are open access; the ACM DL record (10.5555/…) is metadata-only with no full text. | have-ref — PDF `_literature/Lazaridou et. al. 2021 - Mind the Gap.pdf`, verified 2026-09-20 against proceedings.neurips.cc |
| **Zhu, Chen, Gao, Zhang, Tiwari & Wang 2025, "Is Your LLM Outdated? A Deep Look at Temporal Generalization", *NAACL 2025* (long, oral)** | aclanthology 2025.naacl-long.381 / arXiv:2405.08460 | **Evidence cite, and the answer to the era objection.** FreshBench evaluates on text published after each model's cutoff, so it is leakage-free by construction. Reports significant temporal bias and declining performance over time, plus two findings that bear on us directly: stronger models degrade *faster* in future generalization, and open-weight models show better long-term adaptability than closed ones (our three are all open-weight). Scope caveat: the task is next-token prediction and event forecasting on fresh text, not rating against a codebook, so it supports "the prior goes stale" and not "the prior goes stale in a measurement task". **Abstract and metadata verified 2026-09-20; body not yet read** — a search snippet attributed a GPT-4 post-cutoff drop of 18.54% vs 4.23% before, with GPT-3.5 / Qwen-2-7B / Llama-3-8B declining less, and that attribution is *unconfirmed*. Check the PDF before using any number. | have-ref — PDF `_literature/Zhu et. al. 2025 - Is Your LLM Outdated (NAACL).pdf` |
| Mallen, Asai, Zhong, Das, Khashabi & Hajishirzi 2023, "When Not to Trust Language Models: Investigating the Effectiveness of Parametric and Non-Parametric Memories", *ACL 2023* | — | **The bridge.** Parametric memory reliable for popular facts, poor for long-tail / less-static; retrieval helps most exactly there. Bridges movement **and** prominence, and motivates "evidence helps where the prior is weak or stale". Keep. | have-ref — PDF `_literature/Mallen et. al. 2023 - When Not to Trust Language Models.pdf` (author list unverified) |
| Kasai, Sakaguchi, Takahashi, Le Bras, Asai, Yu, Radev, Smith, Choi & Inui 2023, "RealTime QA: What's the Answer Right Now?", *Advances in Neural Information Processing Systems* 36, Datasets and Benchmarks Track | arXiv:2207.13332 | LLMs falter on questions whose answers change over time. A benchmark-and-platform paper (weekly-updated questions about current events), so cite for the phenomenon, not for a mechanism. Optional once Zhu is in. | have-ref — PDF `_literature/Kasai et. al. 2023 - RealTime QA (NeurIPS).pdf`, verified 2026-09-20 |
| ~~Luu et al. 2022, "Time Waits for No One! Analysis and Challenges of Temporal Misalignment", *NAACL 2022*~~ | — | Performance drops when eval data post-dates training data ("temporal misalignment"). **Recommended cut 2026-09-20:** redundant with Lazaridou for our purposes and same era. Footnote-tier if kept. | have-ref — PDF in `_literature/` |
| ~~Dhingra et al. 2022, "Time-Aware Language Models as Temporal Knowledge Bases", *TACL*~~ | — | Facts change over time; a model trained on a snapshot gets time-sensitive facts wrong. **Recommended cut 2026-09-20:** redundant with Lazaridou, T5-scale. | verify (no PDF) |

**Checked and rejected 2026-09-20** (so nobody re-finds them): *Temporal Generalization: A
Reality Check* (Madaan, Chopra & Cho, arXiv:2509.23487) is about interpolating and extrapolating
model *parameters* under distribution shift, benchmarked on satellite imagery and yearbook
photos — unrelated to knowledge cutoffs. *Factual Knowledge in Language Models: Robustness and
Anomalies under Simple Temporal Context Variations* (Ammar Khodja et al., arXiv:2502.01220,
TimeStress; best of 18 LMs perfectly distinguishes only 11% of facts) is relevant but is an ACL
2025 **workshop** paper and is about associating facts with validity periods rather than stale
priors.

## L. V-Dem measurement model, IRT, panel attrition (methods background)

**The empirical case is in-repo:** `analysis/01-panel-degradation-pathologies.qmd` §7
(Analysis 4) is the load-bearing result — panel size strongly and robustly predicts V-Dem's
own posterior SD (−0.012 to −0.013 per coder, p < 0.001, survives country + indicator + year
FEs), and post-2013 attrition has raised mean posterior SD ~12% above the 2008–2010 minimum.
Two figures there are usable directly: the posterior-SD-by-panel-size bar chart
(`uncertainty-binned-plot`) and the "IRT uncertainty has risen with post-2013 attrition" time
series (`uncertainty-time-plot`). The paper leads on **uncertainty, not bias** (Analyses 1–3
are honest nulls). Still need the external V-Dem methodology cites below.

| Ref | Identifier | Note | Status |
|---|---|---|---|
| `analysis/01-panel-degradation-pathologies.qmd` §7 + its two uncertainty figures | in-repo | The attrition-raises-IRT-uncertainty result and figure for the motivation section. | have (in-repo) |
| `initial-exploration/notes/panel-size-analysis.md` + `explore-coder-level-data/02-panel-size-analysis.qmd` (rendered `.html`) | in-repo (one level up) | The fuller panel-size writeup: the 2005 cliff + post-2013 decline pyramid (§3), the year-by-year attrition flow table 2013–2024 (§4), the 2005-vs-2024 overlap — only 10 genuinely new coders in 2024 (§5), the three-gap structure (§6), and §9.4 on the "expanding temporal burden" / burnout. | have (in-repo) |
| Coppedge et al. 2026, V-Dem dataset / codebook (v15 used here) | — | Dataset, coder structure, the "advise against ≤3 coders" warning. The Maerz & Weidmann pilot cites this as "Coppedge et al. 2026" — get the matching entry from its bibliography. | find (in the pilot's refs; EJT also has from bridge-coder) |
| Pemstein et al. 2025, "The V-Dem Measurement Model" (V-Dem Working Paper 21, latest ed.) | — | IRT model, coder reliability (β) and thresholds (γ), panel-size sensitivity. `panel-size-analysis.md` quotes its fn.15 (p.7): "roughly five country experts, that generally rate the whole time period" and post-2013 recruits "only coded from 2005 onward" — the structural fact behind the pyramid. (Pilot cites an earlier ed. as "Pemstein et al. 2020"; reconcile the year.) | find (EJT has from bridge-coder) |
| Panel attrition figures (mean ~5 → ~13 at 2005 → ~5.6 by 2024) | — | Now sourced in-repo (`panel-size-analysis.md` §3–5). Exact *cause* of the post-2013 decline still not established; `seraphine-questions.md` records EJT wants help contextualizing it. | have (in-repo) / cause: find |

## M. Justification / chain-of-thought unfaithfulness (results-prose caveat)

Source: `notes/justification-mining-for-narrative.md` (points to `reasoning-models-and-overthinking.md`).

| Ref | Identifier | Note | Status |
|---|---|---|---|
| Turpin et al. 2023, "Language Models Don't Always Say What They Think: Unfaithful Explanations in Chain-of-Thought Prompting" | — | Model justifications are post-hoc rationalizations, not a faithful trace. | verify |

## N. Expert-coded measures, panels, and what it takes to maintain them (framing §1)

`scratch.md` Entry 2 + the 2026-09-06 exchange. Framing: expert-coded measures are costly to
produce, several have narrowed or shut down, and V-Dem's *model-based panel* has few
precedents. All `find` — EJT pulls refs; mine the "Listening to Leaders" bibliography too.

### N1. Other expert *panels* (the "who else does this" question)

| Ref | What it is | For the paper | Status |
|---|---|---|---|
| V-Party, Digital Society Project, Varieties of Indoctrination | V-Dem-family datasets, same many-coders + IRT model | The "model-based panel" tier — essentially only the V-Dem family. | find (V-Dem WPs) |
| Chapel Hill Expert Survey (CHES) — Bakker et al.; Polk et al. | Many experts per party, averaged; recurring waves | "Many raters, simple averaging" tier. | find |
| Benoit & Laver 2006, *Party Policy in Modern Democracies*; expert party-position surveys | Multiple experts per party per dimension | Same tier as CHES; the older anchor. | find |
| Perceptions of Electoral Integrity (PEI) — Norris et al. | ~20–40 experts per election, averaged | Many-raters tier; election-level not annual. | find |
| Quality of Government (QoG) Expert Survey — Dahlström et al. | Multiple experts per country, public administration | Many-raters tier. | find |
| World Justice Project Rule of Law Index | Expert questionnaires (several per country per factor) + population poll | Many-raters tier; two respondent panels. | find |
| Bertelsmann Transformation Index (BTI) / Sustainable Governance Indicators (SGI) | ~2 country experts + regional/board calibration | Panel-ish (small n per unit + calibration). | find |
| Political Terror Scale (PTS) — Gibney et al. | Multiple coders per country-year, reconciled | Weak case — multi-coder with reconciliation, not independent panel. | find |

### N2. Widely used but *not* panels (the contrast class)

| Ref | Identifier | Note | Status |
|---|---|---|---|
| Polity (Marshall, Gurr, Jaggers) | — | Small adjudicating team, not a panel; heavily used; continuity uncertain. Confirm. | find |
| Freedom House, Freedom in the World | — | Lead analyst per country + advisory review, not an independent panel. | find |
| Comparative Manifesto Project / MARPOR | — | Mostly one coder per manifesto, with reliability sub-studies. | find |
| CIRI Human Rights Data Project (Cingranelli & Richards) | — | Two coders, standards-based, reconciled; ended ~2014, resource constraints. Confirm end date + a citable account. | find |
| Kucera / Mosley / "Uno" labor-rights coding (EJT's phrasing) | — | Labor-rights indicators from source texts. Likely David Kucera (ILO labour-rights indicators) and/or Layna Mosley, *Labor Rights and Multinational Production*. Pin project + authors. | find |
| Conflict-event datasets (UCDP, ACLED, …) | — | Trained coders, event-level QA, not a panel per unit. One concrete example is enough. | find |

### N3. Coder burnout / workload / retention

| Ref | Identifier | Note | Status |
|---|---|---|---|
| V-Dem methodology / coder-management working papers (recruitment, retention, coder characteristics) | — | For the burnout point and the cause-of-decline context EJT flagged. Marquardt / Pemstein / Tannenberg V-Dem WPs are candidates; Pemstein et al. WP21 fn.15 (see L) is the anchor for the "~5 experts, whole time period" structure. | find |
| In-repo workload computations | `initial-exploration/explore-coder-level-data/` | Already coded, not headline-rendered: `01` §"Indicator Load per Coder" (~100 indicators/coder, the "254" is an overcount incl. conf/beta/post-survey cols); `04` §1 countries-per-coder + distribution plot + `n_rows` per coder; `05` §8 median/p25/p75 ratings per coder by coder type. `notes/panel-size-analysis.md` §9.4 has the qualitative burnout argument (expanding temporal scope 10→19 yrs, anchoring, non-random attrition). Quick re-run for a clean "typical coder fields N CYI ratings" number. | have (in-repo, needs a render for the number) |
| Expert-survey fatigue / respondent burden (general) | — | Optional general-methods backing for "panels are hard to sustain". | find |

## O. Serial position in the context window — primacy, recency, and the task-framing channel

Supports the framing-vs-text decomposition (§A8 successor). The coding template names the focal
country three times, all inside the **user** message: the opening task statement
(`prompts/panel-member-coding-prompt.md:21`), the evidence section header (`:37`), and the closing
output instruction (`:53`). Two of those are the highest-salience positions in the sequence; names
inside the evidence body are in the middle. **The caveat these citations exist to support:** a
larger task-framing effect than evidence-body effect is *predicted by serial position alone*, so
the decomposition cannot be read as showing that instruction slots are architecturally privileged.
The design does not separate privilege from position — testing that would require relocating the
framing line into the middle of the evidence. State the claim as "identity in the task framing,"
not "instruction slots are privileged."

| Ref | Identifier | Note | Status |
|---|---|---|---|
| Liu, Lin, Hewitt, Paranjape, Bevilacqua, Petroni & Liang 2024, "Lost in the Middle: How Language Models Use Long Contexts", *TACL* 12:157–173 | doi:10.1162/tacl_a_00638 / arXiv:2307.03172 | **Primary cite for the position confound.** U-shaped curve: relevant information at the beginning or end of the context is used; in the middle it is not, even in long-context models. Directly describes the asymmetry between the framing slots and the evidence body. | have-ref — verified 2026-09-16 (ACL Anthology, MIT Press TACL) |
| Xiao, Tian, Chen, Han & Lewis 2024, "Efficient Streaming Language Models with Attention Sinks", *ICLR 2024* | arXiv:2309.17453 | Attention-sink result: disproportionate attention to initial tokens irrespective of semantic content. Mechanistic backing for the **primacy** half only; the StreamingLLM engineering contribution is not relevant. Secondary cite. | have-ref — verified 2026-09-16 (ICLR proceedings, arXiv) |
| Zhao, Wallace, Feng, Klein & Singh 2021, "Calibrate Before Use: Improving Few-Shot Performance of Language Models", *ICML 2021* | PMLR 139 / arXiv:2102.09690 | **Recency** half: models over-weight the last example in a prompt. Backs the claim that the closing `Rate {COUNTRY} in {YEAR}` line (`:53`) is a strong conditioning signal. Also a standing caution on few-shot *ordering* effects in the calibration block. | have-ref — verified 2026-09-16 (PMLR, arXiv) |

*Untested alternative left on the table:* whether the framing effect survives moving the focal
country out of the opening/closing slots and into the evidence body. One additional run; not
currently planned.

## P. Text (document) leakage — source evidence pre-encoded in the weights

Added 2026-09-20. Group E turned out to be almost entirely *ground-truth* leakage (benchmark
instances and their labels in pretraining), despite its header. The one exception is
arXiv:2310.18018, whose taxonomy names **text contamination** as a separate category, which is
row 2 of the summary table in `notes/data-leakage-contamination.md`: the State Department and
Freedom House documents used as evidence packets are public and almost certainly in the
pretraining corpora, so a model given one may be conditioning on its prior encoding of that
document rather than reading it. Nothing else in either citation file covers this. Groups B, C
and K are all row 3 (entity and fact priors), and group D supplies the *method* for testing it
(hypothesis-only / input-ablation, which is what Codebook-only is) but not the phenomenon.

**How much of this the paper needs.** Two cites, one sentence each. Carlini et al. establishes
that documents in pretraining are memorized under exactly our conditions (heavy duplication
across mirrors), so row 2 is a live concern rather than a hypothetical. Magar & Schwartz
establishes that memorization and *exploitation* are separate questions, which is what licenses
us to bound the effect and stop rather than run a probe. The Codebook-only vs. Evidence
comparison bounds row 2 whatever its cause, and the Llama/2023 cells are structurally clean
(cutoff December 2023, source documents published April 2024; see
`notes/leakage-vs-prior-assessment.md` §3). Chang et al. and Shi et al. are the instruments if a
reviewer insists on a direct document-level test; neither is currently planned.

**All four are recalled, not verified.** Claude supplied them from memory (cutoff May 2026) on
2026-09-20; no PDFs in `_literature/`. Confirm authors, venue, year and identifier against the
published versions before any of them goes into `references.bib`.

| Ref | Identifier | Note | Status |
|---|---|---|---|
| Magar & Schwartz 2022, "Data Contamination: From Memorization to Exploitation", *ACL 2022* (short) | — | **First choice.** Separates a model having memorized contaminated data from that memorization actually buying downstream performance, and finds the gap is large. This is the Gemma result stated as a general finding: Gemma's cutoff (August 2024) puts V-Dem v14 and the 2023 source documents inside its window, and it is still the *worst* base model on 2023 Codebook. Supplies the vocabulary for "exposure was available and bought nothing." | verify |
| Carlini, Ippolito, Jagielski, Lee, Tramèr & Zhang 2023, "Quantifying Memorization Across Neural Language Models", *ICLR 2023* | arXiv:2202.07646 | **Second choice.** Memorization scales with model capacity, example duplication in the corpus, and context length. The duplication result is the one that matters here: State Dept country reports and Freedom in the World are mirrored across many sites, which is the condition under which verbatim memorization is strongest. Cite to make row 2 a real concern before bounding it. Carlini et al. 2021 (USENIX Security, "Extracting Training Data from Large Language Models") is the origin paper but 2023 is the better fit. | verify |
| Chang, Cramer, Soni & Bamman 2023, "Speak, Memory: An Archaeology of Books Known to ChatGPT/GPT-4", *EMNLP 2023* | — | Name-cloze probe to test whether *specific documents* were in pretraining, with popularity driving memorization. Closest published analog to a document-level probe on a humanities-style corpus, and the popularity result rhymes with our prominence stratification. Instrument, not argument. | verify |
| Shi, Ajith, Xia, Huang, Liu, Blevins, Chen & Zettlemoyer 2024, "Detecting Pretraining Data from Large Language Models", *ICLR 2024* (WikiMIA / Min-K% Prob) | arXiv:2310.16789 | The instrument if we ever want to test whether a given State Dept report was in a model's window. Transfers to our case better than Golchin & Surdeanu (§E), which assumes an instance is a text span with a remainder to compute ROUGE against and does not fit tabular coder ratings (see `notes/leakage-vs-prior-assessment.md` §6). Not planned. | verify |
