
# Introduction

Conceptual measurement in political science frequently features expert-coded data produced by trained coders who, relying on their knowledge and primary source documents, score events or country cases against a detailed codebook. Because they rely on the contributions of a relatively scarce set of busy country experts, such datasets are expensive to build and difficult to maintain. Consequently, many such projects, despite their obvious value to the discipline, have encountered challenges in maintaining funding and a steady pool of coders.^[defunct-examples] 

[^defunct-examples]:  The CIRI Human Rights Data Project, START's Global Terrorism Database, and long-standing efforts to code labor standards from country reports [cite: N] illustrate how even prominent, widely used projects can lapse, scale back, or be discontinued once the coding effort outgrows the resources available to sustain it.

It is therefore not surprising that scholars have begun research how to augment the efforts of human coders with artificial intelligence (AI). Research into synthetic coding has developed along two branches. The first asks how closely a large language model (LLM) reproduces annotations that human coders have already produced. In these studies, researchers take a corpus for which human "gold" labels exist, give a model the codebook that the human annotators worked from, and compare the model's output against those labels. Across a range of tasks, these studies report that general-purpose models match or exceed the accuracy of crowd workers and supervised classifiers at a small fraction of the cost, and often with higher intercoder reliability than human annotators achieve [@gilardi2023; @heseltine2024; @ornstein2023; @tornberg2025]. 

The gains from this approach are not a given and may be limited in their application to specific types of projects. LLM performance varies enough across datasets and task types to require validation case by case, and open-weight models follow real political science codebooks poorly without additional training [@pangakis2023; @halterman2025b]. When accurate, a gold-label centered approach may augment expert annotation projects for which a single authoritative coding exists, so that reproducing the label reproduces the measure. Polity, Freedom House's Freedom in the World, and many conflict datasets work this way, as does the sentence-by-sentence coding behind the Comparative Manifesto Project. However, many projects gather judgments from multiple experts and average them across country cases in a panel framework, such as the Chapel Hill Expert Survey, the Perceptions of Electoral Integrity project, Varieties of Democracy (V-Dem) and the World Justice Project's Rule of Law Index. For these, no individual rating is the target, and the quantity the model must match is an aggregate. 




In this paper, we... 

The Varieties of Democracy project (V-Dem) and related efforts modeled on it represent a unique framework in which many independent experts rate each case and a measurement model estimates each coder's reliability and scale use before the ratings are aggregated [cite: L]. 

LLMs are an obvious candidate for augmenting thinning expert panels, but only if their ratings reflect genuine evaluation of the evidence in front of them (contextual knowledge) rather than information encoded during pretraining (parametric knowledge). A model that has memorized a country's general reputation can appear well-calibrated without having the capacity to process new information due to the tendency of LLMs to heavily rely on their pretrained weights. This distinction determines whether AI ratings are safe to rely on for cases featured less prominently in public discourse or those undergoing rapid transformations like regime change. This study addresses four interrelated questions:

1. When a large language model rates a country's political conditions on a V-Dem indicator, is it drawing on the textual evidence it has been given in the prompt, or on prior beliefs about the country activated by its name or other identifying details in the text?
2. Does embedding calibration in the model's weights through fine-tuning outperform supplying few-shot calibration examples in the prompt, and does training on de-identified (anonymized or summarized) text change what the model learns to rely on?
3. Do the answers to these two questions, established on a single validation year, hold up when the best-performing model is carried forward to later years, including a year entirely outside the model's training data, and under what conditions, such as a country undergoing a regime transition, does the model rely more or less heavily on the text in front of it?
4. Is the resulting model's agreement with the human expert panel good enough that adding its ratings to a thinning panel would not measurably shift the panel's consensus?

