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

| Ref | Identifier | Note | Status |
|---|---|---|---|
| Geirhos et al. 2020, "Shortcut Learning in Deep Neural Networks", *Nature Machine Intelligence* 2(11):665–673 | doi:10.1038/s42256-020-00257-z | Highest-level "why" for anonymization / the reading-vs-shortcut framing. | have-ref (2026-08-30) |
| Poliak et al. 2018, "Hypothesis Only Baselines in Natural Language Inference" | — | Input-ablation precedent (evaluate with half the input removed). Codebook-only analog. | verify |
| Gururangan et al. 2018, "Annotation Artifacts in Natural Language Inference Data" | — | Models exploit artifacts, not the intended signal. | verify |
| McCoy, Pavlick & Linzen 2019, "Right for the Wrong Reasons" (HANS) | — | Right answer, wrong mechanism — the whole motivation for the decomposition. | verify |
| Kaushik, Hovy & Lipton 2020, "Learning the Difference that Makes a Difference with Counterfactually-Augmented Data" | — | Counterfactual data as diagnostic; supports the name-swap design. | verify |
| Gardner et al. 2020, "Evaluating NLP Models via Contrast Sets" | — | Perturb the input minimally, watch the prediction. | verify |

## E. Data contamination / leakage / temporal holdout (input leakage)

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

## G. Summarizing the evidence before scoring — common practice, and the leakage claim

Two distinct points. (1) **Summarize-then-score is established practice** in LLM text
measurement — Benoit et al. 2026 (group A) is the anchor: their whole method is an LLM summary
of the source followed by LLM scoring of the summary. EJT: "maybe not to prevent leakage, but
summarizing is common" — collect a few more examples. (2) **The leakage-prevention rationale**
is a narrower political-science claim (a fresh paraphrase cannot carry a memorized
country→label association) that `notes/anonymization-summarization-concept-origins.md` says to
attribute to a specific source. No standard ML precedent for LLM-summary-as-*training*-input.
Frame our summarized result as a test of claim (2), positioned within practice (1).

| Ref | Identifier | Note | Status |
|---|---|---|---|
| Benoit, De Marchi, C. Laver, M. Laver & Ma 2026 (group A) | doi:10.1111/ajps.70050 | Summarize-then-score as the method — practice anchor for (1). | have-ref — PDF in `_literature/` |
| More examples of LLM-summarization / paraphrase of evidence text before coding | — | 2–3 additional cites for "this is common". | find |
| The specific PS source(s) making the "summarize to prevent leakage" argument | — | Needed before submission. | find |
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

## J. Calibration — RLHF overconfidence, learning from disagreement / soft labels

Source: `notes/ft-calibration-overconfidence-finding.md` §4. **All memory-sourced, cutoff Jan
2026 — every one needs verifying.** Heavier than the current arc may need; include only the
subset the theory section actually leans on (criterion 2: "match the human error distribution").

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

| Ref | Identifier | Note | Status |
|---|---|---|---|
| Lazaridou et al. 2021, "Mind the Gap: Assessing Temporal Generalization in Neural Language Models", *NeurIPS 2021* | — | LMs degrade on text from after their training period. Core "knowledge is frozen at cutoff" cite. | verify |
| Luu et al. 2022, "Time Waits for No One! Analysis and Challenges of Temporal Misalignment", *NAACL 2022* | — | Performance drops when eval data post-dates training data — "temporal misalignment". | verify |
| Dhingra et al. 2022, "Time-Aware Language Models as Temporal Knowledge Bases", *TACL* | — | Facts change over time; a model trained on a snapshot gets time-sensitive facts wrong. | verify |
| Kasai et al. 2023, "RealTime QA: What's the Answer Right Now?", *NeurIPS 2023* | — | LLMs falter on questions whose answers change over time. | verify |
| Mallen et al. 2023, "When Not to Trust Language Models: Investigating the Effectiveness of Parametric and Non-Parametric Memories", *ACL 2023* | — | Parametric memory reliable for popular facts, poor for long-tail / less-static; retrieval helps most exactly there. Bridges movement **and** prominence, and motivates "evidence helps where the prior is weak or stale". | verify |

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
