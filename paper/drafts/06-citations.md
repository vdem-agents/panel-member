
## Reidentification

*Note:* Yang et. al. cited in section 04 as well. 

**Yang, Zhu & Gurevych 2025.** "Robust Utility-Preserving Text Anonymization Based on Large
Language Models." *Proceedings of the 63rd Annual Meeting of the Association for Computational
Linguistics (Volume 1: Long Papers)*, 28922–28941. doi:10.18653/v1/2025.acl-long.1404.
Key `yang2025`.
PDF: `_literature/Yang et. al. 2025 - Robust Utility-Preserving Text Anonymization Based on Large Language Models (ACL).pdf`

> Rewrites text so that the person described cannot be identified from it while keeping it usable for a classification task, treating those two goals as competing objectives to be balanced rather than one as a side effect of the other. Two components do the judging: a language model asked to name the person the passage describes, scored by how often it succeeds and how confident it is, and a check on whether a classifier can still recover the passage's label. A third rewrites the text in response to both, repeatedly. The numbers show what is at stake. A classifier reads the original passages correctly 99.58% of the time. The previous best method cuts the identification rate from 100% to 52.91%, but the classifier falls to 92.02%. Theirs holds identification at the same level while the classifier stays at 96.02%. Two results carry over to any study that strips identifying detail before scoring. How much accuracy is lost depends on how the stripping is done, so a drop after de-identification is not by itself evidence that the name was doing the work. And roughly half of passages remain identifiable after careful rewriting, which is where these methods bottom out against a capable reader.

**Jiang, Wu, Lin, Yang & Qiu 2023.** "LLMLingua: Compressing Prompts for Accelerated Inference of
Large Language Models." *Proceedings of the 2023 Conference on Empirical Methods in Natural
Language Processing*, 13358–13376. doi:10.18653/v1/2023.emnlp-main.825. Key `jiang2023`.
PDF: `_literature/Jiang et. al. 2023 - LLMLingua - Compressing Prompts for Accelerated Inference of Large Language Models (EMNLP).pdf`

> Shortens a prompt by deleting the words a small model finds easiest to predict and keeping the ones that carry information, cutting length by as much as twenty times with little loss on math problems, reasoning tasks, conversation logs and papers. The result reads badly — whole words are clipped to fragments, and the text is, in the authors' words, challenging for humans — but the model scores on it about as well as on the original. The finding worth carrying over comes from a check they run afterward. They hand the shortened text to a stronger model and ask it to restore what was removed, and it largely can: at seventeen times compression one example comes back as the full nine-step chain of reasoning it started as, with how much returns depending on the compression rate and on which small model did the cutting. Text that looks destroyed can still be legible to the model reading it, which is the possibility raised whenever identifying detail is stripped from a document and the model is then asked whether it can still tell what the document describes.

## Name-swap analysis

**Kaushik, Hovy & Lipton 2020.** "Learning the Difference that Makes a Difference with
Counterfactually-Augmented Data." *Proceedings of the 8th International Conference on Learning
Representations (ICLR)*. arXiv:1909.12434. Key `kaushik2020`.
PDF: `_literature/Kaushik et. al. 2020 - Learning the Difference that Makes a Difference with Counterfactually-Augmented Data.pdf`

> Pays people to rewrite documents so that the label flips. An editor is handed a document and its label and asked for a version that carries the opposite label, while keeping the writing coherent and changing nothing that does not have to change. 713 workers did this for movie reviews and for sentence pairs from an inference benchmark. The rewrites break classifiers in both directions: a model trained on the original reviews scores 79% on originals and 56% on the rewrites, and the same model trained on the rewrites scores 89% on rewrites and 63% on originals. Training on both together restores performance on both, and features the model had been leaning on — the film's genre, which says nothing about whether a review is favorable — stop predicting the label. The edits are also informative in themselves, since whatever the editor had to change is what was carrying the label.

**Gardner et al. 2020.** "Evaluating Models' Local Decision Boundaries via Contrast Sets."
*Findings of the Association for Computational Linguistics: EMNLP 2020*, 1307–1323.
doi:10.18653/v1/2020.findings-emnlp.117. Key `gardner2020`.
PDF: `_literature/Gardner et. al. 2020 - Evaluating Models' Local Decision Boundaries via Contrast Sets (Findings EMNLP).pdf`

> Proposes that whoever builds a test set should also build a perturbed companion to it. The dataset's own authors take each test item and change it as little as they can in a way that moves the correct answer — swap a number, negate a clause, substitute one entity for another — so every item acquires a near-identical twin with a different answer. Done for ten datasets. Models that look strong on the originals lose up to 25 points on the twins, and more than that on the authors' stricter measure, which credits a model only when it gets every member of a cluster right. They also run people through the perturbed items and find human accuracy essentially unchanged. That contrast carries the argument: the edits are small enough that a person hardly notices them, so a model that falls apart on them was not reading the way the benchmark assumed.