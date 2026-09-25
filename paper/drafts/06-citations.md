
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