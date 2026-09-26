# §4 Models and evaluation — citations

### Experimental design

Discussion could proceed like this: 

1. Detection methods sort by how much of the model you can see, i.e. corpus and internals, token probabilities, outputs only (Cheng). 
2. Corpus-level inspection is unavailable, since none of the three vendors disclose training data. 
3. The other two are available: we could run Min-K% on a source document (Shi), and completion-based probing (Golchin) fails only because a 0–4 rating has no continuation to score. 
4. But both answer membership, and section 02 has already established that membership is not the question. Exposure to the inputs is the expected condition, not a problem.
5. What matters is whether exposure inflated the score, so you test that directly, by comparison (Dekoninck).

**Cheng, Chang & Wu 2025.** "A Survey on Data Contamination for Large Language Models."
arXiv:2502.14425. Key `cheng2025`.
PDF: `_literature/Cheng et. al. 2025 - A Survey on Data Contamination for Large Language Models (arXiv).pdf`

> Surveys how the field defines contamination, avoids it, and detects it. The detection half organizes the methods by how much of the model the investigator can see: the training corpus and internal states, the probabilities the model assigns to individual words, or nothing but its output. Each level supports a different family of tests, and the strongest of them are available only to the organization that trained the model. The survey also marks out cases the field agrees are not contamination, placing among them those where the overlap between training and test material exists but does not improve performance.

**Golchin & Surdeanu 2024.** "Time Travel in LLMs: Tracing Data Contamination in Large Language
Models." *Proceedings of the Twelfth International Conference on Learning Representations (ICLR
2024)*. Key `golchin2024`.
PDF: `_literature/Golchin and Sardaneu 2024 - Time Travel in LLMs.pdf`

> Tests whether a model has seen a dataset by asking it to finish an item from that dataset. The model is shown the opening of a real example twice — once in a prompt that names the dataset and which split the example came from, once in a prompt that names neither — and the two completions are scored against the text that was withheld. If naming the dataset produces a markedly closer match, the model has seen it. The authors report agreement with human judgment between 92 and 100 percent, and find GPT-4 has seen three of the datasets they test. The method needs an item that is a passage with a continuation to compare against, which is what makes it inapplicable to a task whose answer is a single number.

**Shi, Ajith, Xia, Huang, Liu, Blevins, Chen & Zettlemoyer 2024.** "Detecting Pretraining Data from
Large Language Models." *Proceedings of the Twelfth International Conference on Learning
Representations (ICLR 2024)*. Key `shi2024`.
PDF: `_literature/Shi et. al. 2024 - Detecting Pretraining Data from Large Language Models.pdf`

> Asks whether a particular document was in a model's training data, given nothing but the document and the ability to run the model. The test rests on a simple observation: text the model has never seen usually contains a few words it finds very improbable, and text it has seen does not. Scoring only those least-probable words separates the two, without any knowledge of what the model was trained on and without training a second model for comparison. The authors supply a benchmark for checking such methods, built from material written before and after known training cutoffs, and apply the test to copyrighted books and to benchmark items. What it establishes is whether a document was present, which is a narrower question than whether a model's answer drew on it.

**Dekoninck, Müller & Vechev 2024.** "ConStat: Performance-Based Contamination Detection in Large
Language Models." *Advances in Neural Information Processing Systems 37 (NeurIPS 2024)*,
92420–92464. Key `dekoninck2024`.
PDF: `_literature/Dekoninck et. al. 2024 - ConStat - Performance-Based Contamination Detection in Large Language Models (NeurIPS).pdf`

> Argues that asking whether a test item appeared in the training data is the wrong question. Training sets are now large enough that some overlap is close to certain, and model developers reply that the overlap does not matter. The authors therefore define contamination by its consequence instead of its cause: a score is contaminated when it is inflated and does not carry over — to reworded versions of the same items, to fresh items drawn the same way, or to a different test of the same skill. Detecting it then becomes a comparison rather than a search. They measure how a model does on the test in question against how it does on a comparable test, judged relative to how other models handle the same pair, and report the gap as an estimate of how much of the score is not real. Applied across current open models, they find inflated scores in several widely used families.

- rephrasing axis is similar to our nameswap battery
- their "synthetic samples from the same distribution" is similar to our 2024 holdout
- comparison of model cutoffs and information available to different models is similar to ours, the release of vdem 14 would be inside of Gemma (Aug 2024) and Qwen (similar), but not Llama's (December 2023)...maybe then Gemma and Qwen should do better at predicting vdem 15 scores than Llama
- however we do not have their reference benchmark, and our interpretation of contamination is different in that we would expect the model to have information also available to a human coder making the same judgements
- More broadly the paper is making the argument that comparisons across models and conditions is the relevant testing strategy when you cannot have access to the original training corpus, so our codebook against evidence, 2023 versus 2024, base against fine-tuned are the recommended path under this testing paradigm

### Primary metrics

#### MAE

#### Difficulty slope

#### Signed deviation

### Primary readout

The readout discussion does two jobs: it says which number we read off the model's distribution and why, and it declares in advance how we will judge whether that distribution is any good. Three citations, plus one carried forward from §2. The order runs from what choosing a readout means, to what we expect the base models' distributions to look like, to the standard we hold them to.

1. **Gneiting establishes that the readout is a choice with a right answer, not a convention.** A model trained on coder labels holds a distribution over the five ratings, and reporting one number means picking a summary of it. Which summary is correct depends on how the report will be scored: squared error is minimized by the mean, absolute error by the median, a right-or-wrong score by the mode. So the mode and the mean are not two attempts at the same quantity — they answer different questions, which is why the paper reports both rather than treating one as the estimate and the other as a robustness check.
2. **Why the distribution is worth reading off at all** is already established in §2 by Peterson, who shows that training toward the single most common answer is the right target only if every other category truly has no chance. Refer back rather than citing again.
3. **What we expect the base models to look like, stated before the result.** Instruction tuning is known to collapse a model's calibration, and the base models went through it, so we expect their distributions to be close to single-valued. Putting this in §4 means §5 reports the entropy figures rather than defending them.
4. **The standard we will judge the distributions against.** Calibration normally compares a model's confidence to how often it turns out to be right, which requires a single right answer. Where the coders genuinely split there is none, so the reference has to be the panel's own spread. Baan is cited for that argument, not as a method — we do not compute their three item-level measures. The §4 language should present this as the standard we adopt, not as a registered test, since the comparison is exploratory.
5. **One consequence follows and can be predicted here.** If the base distributions are nearly single-valued, their mode and their mean are the same number and the readout choice cannot matter for them; if the fine-tuned distributions carry real spread, the two separate. §5 reports whether that holds.

**Gneiting 2011.** "Making and Evaluating Point Forecasts." *Journal of the American Statistical
Association* 106(494), 746–762. doi:10.1198/jasa.2011.r10138. Key `gneiting2011`.
PDF: `_literature/Gneiting 2011 - Making and Evaluating Point Forecasts (JASA, arXiv preprint).pdf`
*Note:* the PDF is the 2010 preprint; section and table numbers may differ from the published article. Its title page shows a 2024 date, which is an artifact of the archive recompiling the file, not a revision.

> Asks which single number a forecaster should report when what they actually hold is a whole distribution, and answers that it depends entirely on how the report will be scored. The target is a common practice — comparing forecasters by average error without having said beforehand which error measure would be used — which the paper shows can rank them in ways that reverse under a different measure. The remedy is to fix the measure in advance, or to say which summary of the distribution is wanted. A table then pairs the two: squared error is minimized by reporting the mean, absolute error by the median, and a right-or-wrong score by the mode. The mode carries a qualification, since on a continuous scale the exact answer is the midpoint of the most probable interval rather than the peak, and the author notes he does not know whether the mode is recoverable this way in general. That qualification falls away where the outcomes are a handful of ordered categories, in which case a right-or-wrong score is minimized by the most probable category exactly.

**OpenAI 2023.** "GPT-4 Technical Report." arXiv:2303.08774 [cs.CL]. Key `openai2023`.
PDF: `_literature/OpenAI 2023 - GPT-4 Technical Report (arXiv).pdf`

> A report on a model rather than a study, cited here for a single figure in it. The authors compare the model before and after the training that turns it into an assistant, asking how well its stated confidence in an answer predicts whether the answer is right. Before that training the two match almost exactly; after it they come apart, with the gap widening by roughly a factor of ten. The measurement is made on multiple-choice questions from a general knowledge benchmark, and the report discloses nothing about what in the training produced the change. What it establishes is narrow and sufficient: a model tuned to follow instructions is expected to be overconfident, so finding that ours are is a replication rather than a discovery.

**Baan, Aziz, Plank & Fernández 2022.** "Stop Measuring Calibration When Humans Disagree."
*Proceedings of the 2022 Conference on Empirical Methods in Natural Language Processing*,
1892–1915. doi:10.18653/v1/2022.emnlp-main.124. Key `baan2022`.
PDF: `_literature/Baan et. al. 2022 - Stop Measuring Calibration When Humans Disagree (EMNLP).pdf`

> Argues that the usual way of asking whether a model knows when it does not know breaks down when the people supplying the labels disagree. That measure compares how confident a model is against how often it turns out to be right, and what counts as right is whichever label the majority chose. Where an item genuinely divides competent annotators, the majority label is an idealization, so the measure scores the model against something that does not exist — and the authors show this is a flaw in the definition rather than a practical difficulty. Their replacement works item by item against the whole distribution of human judgments, asking whether the probability the model assigns to an answer matches the proportion of people who chose it, whether it ranks the options as they did, and whether it is as uncertain overall as they were. They demonstrate this on a dataset carrying about a hundred judgments per item. Their closing section names the two conditions the approach requires: enough judgments per item for the human distribution to be estimated reliably, and some way of separating genuine disagreement from careless annotation.

### LOO benchmark 

**Calderon, Reichart & Dror 2025.** "The Alternative Annotator Test for LLM-as-a-Judge: How to
Statistically Justify Replacing Human Annotators with LLMs." *Proc. ACL 2025 (Vol. 1: Long
Papers)*, 16051–16081. doi:10.18653/v1/2025.acl-long.782. Key `calderon2025`.
PDF: `_literature/Calderon et. al. 2025 - The Alternative Annotator Test for LLM-as-a-Judge (ACL).pdf`

> Excludes one annotator at a time and asks whether the LLM or that annotator better matches the remaining annotators — the same leave-one-out logic as our human benchmark, applied to the same replacement question. Two differences to note in the text: their statistic is a per-annotator winning rate with a cost penalty applied to humans, not an MAE, and they score both sides against the n−1 remainder where we score the AI against the full panel mean.

Also cite **`pemstein2025`** (see `03-citations.md`) where §4 explains that the evaluation
reference is the raw panel mean, not V-Dem's published IRT estimate.

No citation for the leave-one-out correction itself. It is an exact identity —
`x − (s−x)/(n−1) = n(x−m)/(n−1)`, so a coder's distance from their peers' mean is `n/(n−1)` times
their distance from the full panel mean. State it; it needs no authority. Candidates considered
and rejected are recorded in `notes/loo-benchmark-metric-decision.md`.

### Codebook-only condition

The Poliak et. al. and Gururangan studies are based on data where crowdworkers are given some context (a premise) and asked to write three hypotheses (statements) related to the context: a true, a false and a neutral statement. The models are tasked with predicting the true, false or neutral labels. The authors of both studies find that the models can still predict the labels when only given the statement and not the context. This is an anlogous setup to our codebook only model, where we take away the context and see whether the model can still predict the rating when only given the country name and year. The main difference is the source of the leakage--in these studies it comes from the training text itself and how the data was constructed (and can therefore be dealt with through better design principles). In our case, the leakage comes from factos about the country absorbed during pretraining--it reflects actual knowledge that may be useful to the model in the rating task. Codebook only is therefore a floor against which other models can be compared rather than evidence of contamination per se.

**Poliak, Naradowsky, Haldar, Rudinger & Van Durme 2018.** "Hypothesis Only Baselines in Natural
Language Inference." *Proceedings of the Seventh Joint Conference on Lexical and Computational
Semantics*, 180–191. doi:10.18653/v1/S18-2023. Key `poliak2018`.
PDF: `_literature/Poliak et. al. 2018 - Hypothesis Only Baselines in Natural Language Inferencepdf.pdf`

> Proposes deleting half the input as a diagnostic. In natural language inference the model is given two sentences and asked whether the first implies the second; the authors throw away the first and train on the second alone, which by the task's own definition should leave nothing to go on. Across ten datasets the stripped-down model beats the majority-class baseline on six, by wide margins — 69% against 34% on the best-known of them — and on one dataset it beats the best published result obtained with the full input. Their conclusion is not that the models are reading well but that the datasets contain regularities that make the second sentence alone predictive, so a score achieved with the full input cannot be read as evidence that the full input was used. They recommend reporting the stripped-input baseline alongside any headline number.

**Gururangan, Swayamdipta, Levy, Schwartz, Bowman & Smith 2018.** "Annotation Artifacts in Natural
Language Inference Data." *Proceedings of the 2018 Conference of the North American Chapter of the
Association for Computational Linguistics: Human Language Technologies, Volume 2 (Short Papers)*,
107–112. doi:10.18653/v1/N18-2017. Key `gururangan2018`.
PDF: `_literature/Gururangan et. al. 2018 - Annotation Artifacts in Natural Language Inference Data (NAACL).pdf`

> Reaches the same result independently and traces it to how the data were made. A classifier given only the second sentence assigns the correct label 67% of the time on one benchmark and 53% on another, against a chance rate of 33%. The authors then show why: crowd workers writing these sentences fell into habits, so negation words signal one label, added clauses explaining a purpose signal another, and short sentences signal a third. Splitting the test set by whether the stripped-down classifier succeeded, they find published models lose roughly fifteen to twenty points on the half it failed. The point for a study reporting agreement scores is that part of the reported performance belonged to the collection procedure rather than to the task.
