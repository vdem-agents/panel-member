
# Section Title

*Uniftying theme addressed by this section:* 

What would it take to make a language model behave like a member of an expert panel, rather than like a machine that agrees with the panel consensus? 

How is textual information relevant for synthetic coder behavior and what is the best way to utilize it to improve the quality of LLM ratings? 

*Related questions this section explores:*

- What biases do LLMs have and are they systematically harsher or more forgiving raters? (should most of this go in the introduction?) 
- Do LLMs read text and how does text affect their ratings? 
- How does altering the text, by summarizing it or deidentifying it affect LLM ratings? 
- How does fine-tuning on text affect LLM ratings? 
- How do providing text, altering text and finetuning models on text affect their ability to approximate the behavior of human expert panel members? 
- How do we evaluate the success of an LLM in this capacity (distinctive measurement problem)?
  - *panels versus cover scores:* one CYI, multiple raters; LLM has to be judged relative to panel aggregate, not accuracy on a single label
  - *consensus oracle versus debater distinction:* we could target either, but for deployment we would want the one that gets closer to the human leave one out mean than the panel mean
  - *shape of error:* we would want the synthetic coder to track case difficulty the same way that humans do and have similar directional bias

Overview/opening - Discuss the task of a synthetic panel member, what good looks like. There are two potential targets for the LLM. The common tendency is to focus on consensus and in this context that would be the panel mean or the IRT score. However, in a situation like V-Dem panels, where the truth is contested, and there is no right answer, each panel member will have unique perspective that should be reflected in our approach. Thus success entails reproducing human error rather than simply replicating consensus. Here you can use the citations on modeling disagreement as opposed to trying to boil everything down to a single gold label... 

**Note:** Include footnote on other strategies, such as prompting strategies or more complex agentic architectures, that we are not pursuing in this paper. Pick up discussion in conclusion foreshadowing future synthetic panel paper. 

1. The target: what good looks like: does not just map consensus but tracks human error (disagreement);
2. The obstacle: Why an off-the-shelf model is not good enough
  a. Bias - directional attitude, not knowable in advance --> Figure 5; 
  b. Prior reliance - parametric versus contextual knowledge, stale prior, prominence --> Figure 6,7 and movement appendices; 
3. The response: two informational-related interventions
  a. Evidence - Can push toward consensus or toward defensible disagreement -> Figures 3, 4, 5 
      1) Summarizing and de-identifying - the identity fork -> Figures 3, 8
  b. Fine-tuning - training on individual coder labels targets the coder distribution -> the fine-tuned rows in each figure

## Bias 



## Prior Reliance 

1. "NLP Evaluation in Trouble" - identifies three sources of contamination/leakage: text contamination (input); label contamination (ground-truth); and guideline contamination (instructions in the prompt) arXiv:2310.18018... Guideline 

### Ground-truth (label) leakage

2. Golchin & Surdeanu 2023
3. "A Survey on Data Contamination for LLMs" 2025 arXiv:2502.14425
4. Constat contamination detectionmethod arXiv:2405.16281

### Input (text) leakage

5. Magar and Schwartz 2022, Data Contamination: From Memorization to Exploitation. Separates model from having memorized data to using it downstream (there is a large gap);
6. Carlini et. al. 2023, Memorization grows with model capacity, duplication of sources in the corpus, and context length; 
7. Chang et. al. 2023. Name-cloze probe (whatever that is) on humanities corpus that shows how popularity of documents drives memorization; 
8. Shi et. al. 2024 - an instrument for testing whether a particular document is in pretraining

### Prior Reliance

1. Distinction between parametric and contextual knowledge (Xu et. al. 2024; Neeman et al. 2022);
2. Entity substitution test reveals that models rely too heavily on parametric knowledge, especially with high-frequency entities (Longpre et. al. 2022);
3. Models follow content when the "conflicting passage" is coherent, but revert to priors when it reads oddly (Xie et. al. 2024);
4. Parametric memory is good for popular facts but not reliable for less static information, retrieval helps when prior is stale (Mallen et. al. 2023)

## Expectations

### Evidence (content)

- Two directions evidence could push the rating: toward consensus, or toward defensible
  disagreement ("debate"). Which one depends on the content, on whether it matches what other
  panel members are reading, and — the key hinge — on *how* the AI reads it.
- The hinge: absorbing the content vs. using entity cues in the text to activate a prior.
  [cite: B, C, D]
- Prediction for Figure 1: evidence moves error in roughly the intended direction (mostly
  confirms — framed as emerging from the literature discussion, acknowledged as partly
  post-hoc, kept for the reader and the narrative).

### Fine-tuning

- Prediction: fine-tuning makes the synthetic coder more human-like — it adjusts weights so
  the model uses content the way a human coder does, aligning the reading with panelist
  behavior. [cite: A (HALC / examples-drive-performance), J]
- Prediction: FT does well on *both* criteria (magnitude and shape).