# §4 Models and evaluation — citations


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

