# Theory citations

1. The target: what good looks like: does not just map consensus but tracks human error (disagreement);
2. The obstacle: Why an off-the-shelf model is not good enough
  a. Bias - directional attitude, not knowable in advance --> Figure 5; 
  b. Prior reliance - parametric versus contextual knowledge, stale prior, prominence --> Figure 6,7 and movement appendices; 
3. The response: two informational-related interventions
  a. Evidence - Can push toward consensus or toward defensible disagreement -> Figures 3, 4, 5 
      1) Summarizing and de-identifying - the identity fork -> Figures 3, 8
  b. Fine-tuning - training on individual coder labels targets the coder distribution -> the fine-tuned rows in each figure

## The target (what good looks like)


## The obstacle

### Bias 

Motoki et. al. 2024 - More Human than Human

### Prior reliance


#### Shortcut learning

The model has a cue (country name) and a signal (text) and accuracy statistics cannot tell you which one it relied on to make its rating. Geirhos is the conceptual citation providing the requisite vocabulary and argument that the accuracy of the model tells us nothing about whether it is relying on text or shortcuts. Du provides the literature review on shortcut learning in language models. Yuan et. al. provide another study that shows how the tendency towards shortcut learning persists in modern models and the conditions under which it worsens (such as with model size) and conditions under which it improves (with chain of thought reasoning). We have not really decided exactly how the two McCoy et. al. fit yet but I think it could be used to frame the problem--the question of how LLMs derive their answers has been around for a long time, and LLMs were designed to predict the next word so they find the most expedient way to do that. 

**McCoy, Pavlick & Linzen 2019.** "Right for the Wrong Reasons: Diagnosing Syntactic Heuristics in
Natural Language Inference." *Proceedings of the 57th Annual Meeting of the Association for
Computational Linguistics*, 3428–3448. doi:10.18653/v1/P19-1334. Key `mccoy2019`.
PDF: `_literature/McCoy et. al. 2018 - Right for the Wrong Reasons.pdf`

> Asks whether a model that scores well on an inference benchmark is scoring well for the right reason. The authors name three shortcuts a model might be using — treating one sentence as following from another whenever it reuses the same words, whenever it is a contiguous run of words from it, or whenever it is a grammatical piece of it — and build an evaluation set out of cases where each shortcut gives the wrong answer. All four models tested, BERT among them, score far below chance on those cases while scoring near-perfectly on the cases where the shortcut happens to agree with the right answer. The authors then put people through the same set. Accuracy is lower than on the original benchmark, so the items are genuinely harder, but the human errors fall about evenly on both sides where the models' errors fall almost entirely on one. That contrast is what separates a model taking a shortcut from a person finding the item difficult. Retraining on examples that break the shortcut largely fixes the behavior.

**McCoy, Yao, Friedman, Hardy & Griffiths 2024.** "Embers of autoregression show how large
language models are shaped by the problem they are trained to solve." *Proceedings of the
National Academy of Sciences* 121(41): e2322420121. doi:10.1073/pnas.2322420121. Key `mccoy2024`.
PDF: `_literature/McCoy et. al. 2024 - Embers of Autoregression.pdf`

> Argues that a language model should be understood through the problem it was trained on — predicting the next word in ordinary text — and that this training leaves marks on its behavior even where the task at hand has nothing probabilistic about it. Three predictions follow: the model does better when the answer it has to produce is a common string, when the input it is handed is common, and when the task itself is one that shows up often in text. Tested across eleven tasks and five models. Asked to reverse a list of words, GPT-4 is right 97% of the time when the reversed list reads as an ordinary sentence and 53% when it does not, although reversing a list is mechanical and the wording should not matter. Decoding a simple letter-shift cipher, the same model scores 51% when the hidden message is a likely sentence and 13% when it is not, and does better on the common version of the cipher than on a rare version that is no harder. The lesson is that accuracy measured on ordinary cases does not tell you how a model behaves on unusual ones.

**Geirhos, Jacobsen, Michaelis, Zemel, Brendel, Bethge & Wichmann 2020.** "Shortcut learning in
deep neural networks." *Nature Machine Intelligence* 2(11): 665–673.
doi:10.1038/s42256-020-00257-z. Key `geirhos2020`.
PDF: `_literature/Geirhos et. al. 2020 - Shortcut Learning in Deep Neural Networks (arXiv).pdf`

> Argues that a range of well-known failures in deep learning share a single cause: the model finds a rule that works on the data it was tested on but is not the rule the task was meant to teach. Two of their examples: a classifier that recognizes cows only when the cows are standing on grass, and a pneumonia detector that had actually learned to tell which hospital took the X-ray, from a metal token in the corner of the scan. The argument they draw out is that a test set drawn from the same pool as the training data cannot separate the intended rule from the shortcut, because both do well on it. Only a test built to differ from the training data tells them apart. They also note that the behavior is not peculiar to machines — animal learning and education research describe the same thing — and close with recommendations for building tests that reveal which rule was learned.

**Du, He, Zou, Tao & Hu 2024.** "Shortcut Learning of Large Language Models in Natural Language
Understanding." *Communications of the ACM* 67(1): 110–120. doi:10.1145/3596490. Key `du2024`.
PDF: `_literature/Du et. al. 2024 - Shortcut Learning of LLMs in NLU (CACM).pdf`

> Reviews the evidence that language models take shortcuts on language tasks. Models pick up features that happen to correlate with the label in the training data — particular words, the amount of overlap between two sentences, where in a passage the answer tends to sit — and those features hold up on a test set drawn from the same source but fail once the test comes from elsewhere. The authors describe this as a long-tail problem: the model learns the head of the distribution, which is where the shortcuts live, and learns the tail poorly, even though the tail carries much of what the task actually requires. They survey how the behavior is detected and what has been tried to reduce it, on the data side and on the model side. One result runs against what the later work finds: among the models covered here, all of them small by current standards, the larger version of a model relies on shortcuts less than the smaller version rather than more.

**Yuan, Zhao, Zhang, Zheng & Liu 2024.** "Do LLMs Overcome Shortcut Learning? An Evaluation of
Shortcut Challenges in Large Language Models." *Proceedings of the 2024 Conference on Empirical
Methods in Natural Language Processing*, 12188–12200. doi:10.18653/v1/2024.emnlp-main.679.
Key `yuan2024`.
PDF: `_literature/Yuan et. al. 2024 - Do LLMs Overcome Shortcut Learning (EMNLP).pdf`

> Asks whether current models have outgrown the problem, and finds they have not. The authors assemble test sets around six kinds of shortcut — word overlap between two sentences, one sentence being a run of words from the other, sentence structure, the presence of negation words, where in the passage the relevant material sits, and writing style — and run nine models over them, including GPT-4, Gemini and the Llama 2 chat family. Accuracy falls sharply once a shortcut is available, by more than 40 percentage points in the worst cases. The result that matters most for the size question is that the larger models are more likely to fall back on the shortcut, not less. Two further findings: asking the model to reason step by step reduces the reliance, while supplying worked examples makes it worse than asking cold; and models report high confidence in exactly the cases where the shortcut has led them astray.

#### Knowledge conflicts

Models draw on their priors. They are more likely to do so when presented with insufficient, ambiguous or conflicting information with respect to the rating task. Furthermore, this is not just an artifact of machine coding; humans do it too and under the same conditions.

**Longpre, Perisetla, Chen, Ramesh, DuBois & Singh 2021.** "Entity-Based Knowledge Conflicts in
Question Answering." *Proceedings of the 2021 Conference on Empirical Methods in Natural Language
Processing*, 7052–7063. doi:10.18653/v1/2021.emnlp-main.565. Key `longpre2021`.
PDF: `_literature/Longpre et. al. 2021 - Entity-Based Knowledge Conflicts in Question Answering.pdf`

> Replaces the answer entity in a question-answering passage with a different entity of the same type, so that the passage now contradicts what the model learned in training, then measures how often the model answers with the memorized entity rather than the one in front of it. Models ignore the passage frequently, and the tendency grows sharply with size — from under 15% of cases for a 60-million-parameter model to over 50% for an 11-billion-parameter one. The prominence of the replacement entity also matters. Models follow the passage when the substituted entity is well known and revert to memory when it is obscure. [Note that the focus here is replacement entity not on the original one.]

**Xie, Zhang, Chen, Lou & Su 2024.** "Adaptive Chameleon or Stubborn Sloth: Revealing the Behavior
of Large Language Models in Knowledge Conflicts." *Proceedings of the 12th International Conference
on Learning Representations (ICLR)*. Spotlight. Key `xie2024`.
PDF: `_literature/Xie et. al. 2024 - Adaptive Chameleon or Stubborn Sloth.pdf`

> Argues that the substitution tests understate how much models read, because swapping a single name into a passage leaves the rest of the text pointing at the original entity, so the passage reads as broken and the model may be reacting to that rather than defending what it believes. Instead draws out what the model already holds to be true, then has a model write a fluent passage contradicting it. When that passage is the only evidence given, models follow it rather than their memory, reversing the earlier finding. When a supporting passage is supplied alongside the contradicting one, models revert to what they already believed, and do so most strongly for well-known entities — GPT-4 kept its prior answer on 80% of the most prominent questions. Which side a model takes also shifts with the order the passages appear in and with how many support each side.

*Note:* Longpre predicts the substitute label effect that we see in our name swap test (Fig. 7) while Xie raises an object to that kind of test. Our deidentification test in Fig. 8 answers this objection by showing that removing the country's name still moves the ratings when both versions of the text are coherent equal-length summaries (thus the the effect cannot be blamed on awkwardly edited text).

**Ennser-Jedenastik & Meyer 2018.** "The Impact of Party Cues on Manual Coding of Political Texts."
*Political Science Research and Methods* 6(3): 625–633. doi:10.1017/psrm.2017.29. Key `ennserjedenastik2018`.
PDF: `_literature/Jedenastik and Meyer 2018 - The Impact of Party Cues on the Political Coding of Text.pdf`

> Ten coders each rated the same 200 immigration statements drawn from Austrian election manifestos, with the party label attached to each statement randomly assigned and a no-label control. Coders rated a statement more positively when it carried the Green label and more negatively when it carried the Freedom Party label, with no effect for the two mainstream parties. The effect is concentrated in statements whose wording is ambiguous; where the text reads as clearly positive or clearly negative, the label does almost nothing. The authors read this as heuristic processing — coders fall back on what they know about the party when the text itself does not settle the question.

**Vallejo Vera & Driggers 2025.** "LLMs as Annotators: The Effect of Party Cues on Labelling Decisions
by Large Language Models." *Humanities and Social Sciences Communications* 12: 1530.
doi:10.1057/s41599-025-05834-4. Key `vallejovera2025`.
PDF: `_literature/Vera and Driggers 2025 - LLMs as Annotators.pdf`

> Runs the Ennser-Jedenastik and Meyer experiment on four models — two ChatGPT, two Llama — using the same statements and the same instructions the human coders received. The party label moves the ratings in the same direction it moved the humans: the Green cue raises the chance of a positive label by about 14 percentage points, the Freedom Party cue raises the chance of a negative label by about 17. Two differences from the humans stand out. The models also respond to the two mainstream party labels, which did nothing to the human coders, so they read the cue more widely than people do. And the effect survives an instruction telling the model to disregard the party mentioned in the prompt.

#### Stale prior


#### Prominence

## The response

### Evidence

*Note:* May want to refer back to Xie et. al's finding here about coherence, i.e. that models may drop the text and rely on a prior if the substitution is confusing or awkwardly worded. 

#### Consensus vs. disagreement


#### Summarizing and de-identifying 

Deidentification hurts when the named entity carries evidence relevant to the rating task, but helps when the entity is irrelevant to the task, i.e. when it is a nuisance. 

**Wang, Chen, Zhou, Cai, Liang, Liu, Yang, Liu & Hooi 2022.** "Should We Rely on Entity Mentions for
Relation Extraction? Debiasing Relation Extraction with Counterfactual Analysis." *Proceedings of the
2022 Conference of the North American Chapter of the Association for Computational Linguistics: Human
Language Technologies*, 3071–3081. doi:10.18653/v1/2022.naacl-main.224. Key `wang2022`.
PDF: `_literature/Wang et. al. 2022 - Should We Rely on Entity Mentions for Relation Extraction.pdf`

> Asks what a model loses when the names are taken out of the text. Working with relation extraction models of the period, the authors first show how heavily those models lean on names: delete the surrounding text entirely, leave only the two entity names, and the model returns its original answer on more than half the instances. The standard remedy has been to mask the names with placeholder tokens. The paper's point is that this remedy is costly, because a name carries meaning beyond identity and masking discards both. Scores fall on every dataset and every model they test once masking is applied. Their own method is built to separate the two — keep what the name tells you about the entity, discard the part that merely predicts the answer.

**Manchanda & Shivaswamy 2025.** "What is in a Name? Mitigating Name Bias in Text Embeddings via
Anonymization." arXiv:2502.02903 [cs.CL]. Key `manchanda2025`.
PDF: `_literature/Manchanda and Shivaswamy 2025 - Mitigating Name Bias in Text Embeddings via Anonymization.pdf`

> Shows that when an embedding model converts a passage into a vector, the names in the passage weigh more heavily than what the passage says. The test pairs a query with two passages: one that means the same thing but uses different names, and one that means something different but keeps the same names. Ranking by similarity, most models place the second above the first, scoring well below what random guessing would produce. Repeating the exercise with the same names throughout restores near-perfect performance, which shows the models read the content well enough once names stop distinguishing the passages. Having a model rewrite each passage to drop the names, keeping everything else, recovers the same near-perfect performance, and improves agreement with human relevance ratings on a second task. Note that the task is built so that names are irrelevant to the correct answer, which is why deleting them can only help — the opposite of what happens where the entity carries information about the answer.

### Fine-tuning

**Maerz, Schafer & Schneider 2026.** "Listening to Leaders: Illiberal Speech as a Symptom of
Democratic Decline." Working paper (Melbourne / CEU Democracy Institute / CEU). Data:
doi:10.7910/DVN/OHGRC3. Key `maerz2026b`.
PDF: `_literature/Maerz et. al. 2026 Listening to Leaders.pdf`

> Illustrates how fine-tuning a smaller model on human-coded regime text yields a rater that is competitive with a frontier model. The contrast with our project is that the fine-tuning occurs on a single gold label whereas fine-tuning on individual coder labels enables it to learn a ratings distribution whereby the same weights support a modal panel-member rating or a consensus estimate. 

