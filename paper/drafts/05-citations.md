## Synthetic Coder Performance

### MAE


### Difficulty slope


### Signed deviation


## Robstness checks

The citations here do defensive work rather than theoretical work. A study that scores models against human ratings from particular years invites two questions, and they are separate questions with separate anchor dates: whether the results depend on when the models stopped learning, and whether they depend on how far a country had moved since our own training data ends. The first is a claim about the models, answered by replication across years. The second is a claim about our fine-tuning window, answered by the movement checks.

1. **Lazaridou et al.** state the first concern in its general form. A model's knowledge is fixed at its training cutoff, performance degrades on material from after it, the degradation compounds with distance, and making the model larger does not change the slope. Cited for the concept only — the models are Transformer-XL and the measure is perplexity, so nothing here speaks to Llama, Qwen or Gemma directly.
2. **Zhu et al.** make the concern current, which is what stops a reader from setting point 1 aside as a finding about 2021 architectures. They evaluate contemporary open-weight models, including the Llama and Qwen families, only on material published after each model's own release date, so the test cannot be contaminated. The pattern holds. Together the two establish that the question deserves an answer; the answer is our design rather than our theory — the 2019 findings reproduce on the 2023 holdout and again on the 2024 FH-only holdout, which falls past Llama's December 2023 cutoff. The claim should name Llama specifically, since Gemma's cutoff is August 2024 and Qwen's is unpublished.
3. **Luu et al.** carry the movement checks, which test something different. The 2018 anchor in those models is the end of our fine-tuning window, not any model's pretraining cutoff, so what is at stake is whether a prior installed by 2016–2018 coder ratings goes stale as a country moves away from it. Luu supplies two things that matter for reading those results: misalignment appears within a few years rather than decades and runs in both directions, and the effective remedy is labelled data from the target period rather than further adjustment of the underlying model — which is why fine-tuning on a window ending in 2018 would not be expected to fix it.

### Replication on holdout years (A3-A6)

**Lazaridou, Kuncoro, Gribovskaya, Agrawal, Liška, Terzi, Gimenez, de Masson d'Autume, Kocisky, Ruder, Yogatama, Cao, Young & Blunsom 2021.** "Mind the Gap: Assessing Temporal Generalization in Neural Language Models." *Advances in Neural Information Processing Systems 34*, 29348–29363. Key `lazaridou2021`.
PDF: `_literature/Lazaridou et. al. 2021 - Mind the Gap.pdf`

> Trains language models on text up to a fixed date and then tests them on text from after it, which was not the standard practice at the time. The models do worse on the later text and keep doing worse the further past the cutoff it sits — up to 16% worse on news and scientific articles than an otherwise identical model that had seen the test period. Size does not change the trend: a model 60% larger degrades at the same rate, and a smaller model trained on more recent text beats a larger one that is two years out of date. The damage concentrates where it matters for a country-rating task. Proper nouns and named entities degrade fastest, and words that entered the language after the cutoff — their examples are "Brexiteers" and "MeToo" — are roughly five times harder for the model than ordinary text. On closed-book questions of the form "who is the [office holder] of [country] in [year]," accuracy falls steadily as the end of the training data is moved away from the year asked about. One control runs the other way: on a reading-comprehension task where the answer is present in the supplied passage, the out-of-date model and the current one score identically, so supplying the text removes the penalty when the text contains the answer.

*Note:* Concept cite only. Transformer-XL, measured in perplexity — Zhu carries any claim about current models.

**Zhu, Chen, Gao, Zhang, Tiwari & Wang 2025.** "Is Your LLM Outdated? A Deep Look at Temporal Generalization." *Proceedings of the 2025 Conference of the Nations of the Americas Chapter of the Association for Computational Linguistics: Human Language Technologies (Volume 1: Long Papers)*, 7433–7457. doi:10.18653/v1/2025.naacl-long.381. Key `zhu2025`.
PDF: `_literature/Zhu et. al. 2025 - Is Your LLM Outdated (NAACL).pdf`

> Builds an evaluation that is leakage-free by construction: every model is tested only on material published after its own release date, so no test item can have been in its training data. Two tasks are used — modeling fresh text drawn from Wikipedia, BBC news, arXiv and other sources, and predicting the outcomes of events that had not yet resolved — across a large set of models including the Llama, Qwen, Yi, Baichuan and Mistral families alongside proprietary ones. Models favor older material: accuracy on questions that closed before a model's release exceeds accuracy on questions closing around it, which the authors call a nostalgia bias, and they note that what a model knows is skewed toward the past rather than toward the period just before release, where a user would expect it to be strongest. After release every model declines substantially; the paper treats a drop under 31% as relatively stable and one over 39% as severe. Two patterns cut against the assumption that newer and larger is safer: larger models degrade faster on the stable Wikipedia material, and within a family each newer version is both stronger at the outset and quicker to fall off. Open-weight models start slightly behind the proprietary ones and hold up better over time.

*Note:* The tasks are next-token prediction on fresh text and event forecasting, not rating against a codebook. Supports "the prior goes stale in current open-weight models," not "the prior goes stale in a measurement task."

### Design Sensitivity

A7 - Untrimmed FT raw evidence grid
A8 - Full Llama x input grid
A9 - Temperature ladder (sampled versus greedy mode)

### Mechanisms

#### Regime movement (A14)

**Luu, Khashabi, Gururangan, Mandyam & Smith 2022.** "Time Waits for No One! Analysis and Challenges of Temporal Misalignment." *Proceedings of the 2022 Conference of the North American Chapter of the Association for Computational Linguistics: Human Language Technologies*, 5944–5958. doi:10.18653/v1/2022.naacl-main.435. Key `luu2022`.
PDF: `_literature/Luu et. al. 2022 - Time Waits for No One.pdf`

> Measures how fast performance decays as the gap widens between the period a model was trained on and the period it is applied to, across eight tasks in four domains — social media, scientific papers, news and reviews — each with data spanning at least five years. The decay is larger than earlier work had reported, and it varies more between tasks than between domains: two Twitter tasks decay at very different rates, and a classifier for political affiliation loses as much as 40 points of F1 over five years, the steepest fall in the set. Two findings go beyond establishing the phenomenon. The loss runs in both directions — a model trained on recent text is also misaligned when applied to text from a few years earlier, and the authors note this happens within years rather than the decades assumed in work on historical documents. And on remedies, continuing to pretrain the model on text from the target period helps very little and sometimes hurts, while fine-tuning on labelled examples from the target period is what recovers the performance. Their reading is that the labelled data carries the fix, not the language model.

#### Prominence (A15)

### Few shot ablation (supposed to be 2019 but we have 2023 it seems?)

- Give the text but not the guiding few-shot examples

### Alternative metrics 

- Krippendorf's alpha, exact match, adjacent category, RMSE, MAE
