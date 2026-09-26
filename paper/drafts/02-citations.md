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

The target of this paper is the panel rather than a single correct score, and the five sources below make that a position with a literature behind it rather than a convenience of our design. Three argue the case and two test it. The sequence runs from the assumption, to the distinction the assumption conceals, to the evidence that the spread is real, to what follows for evaluation, and finally to the two things a researcher can do about it.

1. **Aroyo & Welty** name the assumption. V-Dem collects several ratings per country-year-indicator and aggregates them, and the natural reading is that the aggregate is the truth and the spread is error. Aroyo and Welty identify that reading as a habit of annotation practice rather than a fact about the task, and their expert-versus-lay finding lands on the V-Dem panel directly: their domain experts marked relations they knew to be true in the world even where the text did not state them.
2. **Plank** draws the line the assumption conceals. Some of the spread is error and some is plausible variation among competent readers of an ambiguous case. Only the second is worth reproducing, and the section should say so before a reader asks.
3. **Pavlick & Kwiatkowski** and **Nie, Zhou & Bansal** establish that the variation is real rather than thin sampling — the objection a small panel invites first. Pavlick shows a second population of readers that survives when the fit is tested on held-out ratings; Nie shows that at a hundred annotations the original label was often not the majority view.
4. **Nie** again, with **Plank** on evaluation, gives the consequence. Models are near-perfect where people agree and near chance where they do not, and barely beat an even-odds baseline on the distribution itself; meanwhile methods built to learn from disagreement are still scored against single labels. This is criterion 2 arriving as a conclusion rather than a stipulation.
5. **Cabitza, Campagner & Basile** name the two available responses. Collect many labels and reduce them to one, or keep them through training and evaluation. Our two readouts are one of each, and the fine-tuning design is the second.

**Aroyo & Welty 2015.** "Truth Is a Lie: Crowd Truth and the Seven Myths of Human Annotation."
*AI Magazine* 36(1), 15–24. doi:10.1609/aimag.v36i1.2564. Key `aroyo2015`.
PDF: `_literature/Aroyo and Welty 2015 - Truth Is a Lie (AI Magazine).pdf`

> Sets out seven assumptions behind the practice of collecting human annotations and argues each is a habit rather than a requirement: that every item has one correct label, that disagreement signals poor quality, that more detailed instructions help, that one annotator is enough, that experts do better than lay people, that every item is equally hard, and that a labeled dataset stays valid. The evidence comes from their own work on medical text. Running the same sentences past ten, twenty and thirty annotators, the shape of the disagreement stops changing past about fifteen, which makes the spread a stable property of the sentence rather than an artifact of who happened to see it. Where a sentence states its relationship plainly the annotators converge; where it does not they split, and the split is what identifies the ambiguity. The comparison with experts carries furthest here. Their medical experts marked relations they knew to be true in the world even where the sentence did not express them, while lay annotators read literally — on one relation the experts scored .31 against the crowd's .87, though across all relations the two were close. They propose scoring each annotator by distance from the rest and keeping the whole distribution rather than a single label.

**Plank 2022.** "The 'Problem' of Human Label Variation: On Ground Truth in Data, Modeling and
Evaluation." *Proceedings of the 2022 Conference on Empirical Methods in Natural Language
Processing*, 10671–10682. doi:10.18653/v1/2022.emnlp-main.731. Key `plank2022`.
PDF: `_literature/Plank 2022 - The Problem of Human Label Variation (EMNLP).pdf`

> Gives the phenomenon a name and follows it through every stage of building a model. Prefers "variation" to "disagreement" on the grounds that disagreement implies only one of the competing views can hold, whereas the cases at issue are ones where several readings are plausible at once. The distinction the paper insists on is between annotator error, which comes from slips and inattention, and variation that is genuine; only the second carries information. The argument then runs through data collection, training and evaluation, and the evaluation part is the sharpest. Most papers proposing methods that learn from disagreement still score those methods against a single aggregated label, which leaves the evaluation unable to see whether the method did anything. Since accuracy can be high while the spread is wrong, a number computed from a single prediction says little about whether a model is behaving sensibly. The paper catalogs the alternatives already in use: comparing the model's distribution to the human one, correlating the two uncertainties, and splitting the test set by how much the annotators agreed.

**Pavlick & Kwiatkowski 2019.** "Inherent Disagreements in Human Textual Inferences."
*Transactions of the Association for Computational Linguistics* 7, 677–694.
doi:10.1162/tacl_a_00293. Key `pavlick2019`.
PDF: `_literature/Pavlick and Kwiatkowski 2019 - Inherent Disagreements in Human Textual Inferences (TACL).pdf`

> Asks whether disagreement goes away when you collect more of it. Fifty people rate each sentence pair on a sliding scale rather than choosing among labels, and the test is built to be decisive: for each pair, fit both a single bell curve and a mixture of several to most of the ratings, then see which better predicts ten ratings held back. For about a fifth of pairs the mixture wins with a substantial second component, meaning the item has two populations of readers rather than one population rating noisily — and an average cannot stand in for that. A second experiment varies how much context the raters see, a word, a sentence, or a full paragraph. Disagreement rose as context increased, with the variance going from .34 to .41 to .56, which is the opposite of what more information is expected to do. They also compare the uncertainty models express with the uncertainty people display and find the two are not the same quantity. Their recommendation is that the evaluation target should be the distribution of plausible human judgments rather than a single label drawn from it.

**Nie, Zhou & Bansal 2020.** "What Can We Learn from Collective Human Opinions on Natural Language
Inference Data?" *Proceedings of the 2020 Conference on Empirical Methods in Natural Language
Processing (EMNLP)*, 9131–9143. doi:10.18653/v1/2020.emnlp-main.734. Key `nie2020`.
PDF: `_literature/Nie et. al. 2020 - What Can We Learn from Collective Human Opinions (ChaosNLI, EMNLP).pdf`

> Collects a hundred annotations for each of 4,645 items already in use as benchmarks, 464,500 labels in all, and asks what the extra annotators reveal. Three things. The original label, set by a handful of people, was not the majority choice of a hundred for 10, 20 and 31 percent of items across the three sets, so a portion of what these benchmarks score as correct is an artifact of how few people were asked. Disagreement is concentrated rather than spread evenly — some items divide people sharply and others not at all. And the models behave very differently on the two kinds: strong systems are nearly perfect where people agree and close to guessing where they do not, with the errors the models share falling almost entirely on the divided items. Scored on how closely their output distribution matches the human one, the best models barely beat a baseline that spreads probability evenly across the labels, and on one measure lose to it, while a fresh set of a hundred annotators lands far closer. Accuracy on the majority label and fidelity to the distribution are separate abilities, and gains on the first have not produced gains on the second.

**Cabitza, Campagner & Basile 2023.** "Toward a Perspectivist Turn in Ground Truthing for
Predictive Computing." *Proceedings of the AAAI Conference on Artificial Intelligence* 37(6),
6860–6868. doi:10.1609/aaai.v37i6.25840. Key `cabitza2023`.
PDF: `_literature/Cabitza et. al. 2023 - Toward a Perspectivist Turn in Ground Truthing for Predictive Computing (AAAI).pdf`

> Names the position and, more usefully, sorts the responses to it into two kinds. In the weaker version, labels are collected from several raters and then reduced to one, by majority vote or some weighted variant; the spread informs which single label is chosen but does not survive into training or evaluation. In the stronger version the individual labels are carried through both. The authors argue the stronger version is the one that changes what a model can do, because it lets the model represent how the raters divided, lets the analyst group raters who see cases alike, and makes it possible to ask whose judgment a given prediction reflects. They also argue the case is not confined to tasks that are obviously matters of opinion, drawing their examples partly from medical diagnosis, where variation between readers of the same image is long documented. Their recommendations concern panel design: involve enough raters for a stable distribution to emerge, involve raters who differ from one another, collect their confidence and their sense of how difficult each case was, and report how the panel was assembled and how its labels were combined.

## The obstacle

#### Directional bias 

Motoki et. al. 2024 - More Human than Human



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

#### Data contamination (or domain knowledge?)

**Sainz, Campos, García-Ferrero, Etxaniz, Lopez de Lacalle & Agirre 2023.** "NLP Evaluation in
Trouble: On the Need to Measure LLM Data Contamination for each Benchmark." *Findings of the
Association for Computational Linguistics: EMNLP 2023*, 10776–10787.
doi:10.18653/v1/2023.findings-emnlp.722. Key `sainz2023`.
PDF: `_literature/Sainz et. al. 2023 - NLP Evaluation in Trouble (EMNLP Findings).pdf`

> Argues that a score on a public benchmark cannot be interpreted without knowing what the model saw in pretraining, and proposes that the field track this benchmark by benchmark. The part that applies directly here is their division of the problem into three kinds of exposure. The model may have seen the instructions written for the human annotators, which the authors single out as the concern for tasks given to a model with no training examples. It may have seen the source texts the annotators worked from. Or it may have seen the annotators' own labels. Each is a different exposure with a different remedy, and a study can be subject to one and not the others.

**Carlini, Ippolito, Jagielski, Lee, Tramèr & Zhang 2023.** "Quantifying Memorization Across Neural
Language Models." *Proceedings of the Eleventh International Conference on Learning
Representations (ICLR 2023)*. Key `carlini2023`.
PDF: `_literature/Carlini et. al. 2023 - Quantifying Memorization Across Neural Language Models (ICLR).pdf`

> Measures how often a language model will reproduce a passage from its training data word for word when prompted with the opening of that passage. Three things make it more likely, each following a steady curve: a bigger model, a longer prompt, and — the one that matters here — more copies of the passage in the training corpus. A document that appeared once is rarely recoverable; a document that appeared many times often is. The evidence packets in this study are built from State Department country reports and Freedom in the World, both of which are republished across many sites, which is the condition under which memorization is strongest.

**Magar & Schwartz 2022.** "Data Contamination: From Memorization to Exploitation." *Proceedings of
the 60th Annual Meeting of the Association for Computational Linguistics (Volume 2: Short
Papers)*, 157–165. doi:10.18653/v1/2022.acl-short.18. Key `magar2022`.
PDF: `_literature/Magar and Schwartz 2022 - Data Contamination - From Memorization to Exploitation (ACL).pdf`

Magar and Schwartz argue that memorization does not necessarily entail exploitation of memorized knowledge, whereas Chang et. al. (below) say it does for memorized books; but again we are not necessarily arguing that memorized information is bad (as humans would use it too).

> Separates having seen the answers from actually using them. The authors deliberately contaminate their own experiment: they pretrain a model on Wikipedia combined with both the training and test sets of a task, fine-tune it on the training set, then compare how it does on test items it saw during pretraining against items it did not. The gap between the two is what the contamination bought. Across two models and three tasks the gap is sometimes large and sometimes absent — the models had memorized the contaminated examples but did not convert that into better answers. How much they exploited depended on how many times the data was duplicated and on model size. The distinction is the useful part: exposure to data is not the same as advantage from it, and the two have to be measured separately.

**Chang, Cramer, Soni & Bamman 2023.** "Speak, Memory: An Archaeology of Books Known to
ChatGPT/GPT-4." *Proceedings of the 2023 Conference on Empirical Methods in Natural Language
Processing*, 7312–7327. doi:10.18653/v1/2023.emnlp-main.453. Key `chang2023`.
PDF: `_literature/Chang et. al. 2023 - Speak, Memory - An Archaeology of Books Known to ChatGPT-GPT-4 (EMNLP).pdf`

> Works out which books a model has absorbed by blanking a character's name in a passage and asking it to supply the name, then asks whether that matters. It does. How well the model knows a book tracks how often the book turns up on the open web, and the books it knows are the widely taught and widely reviewed ones. When the authors then set the model a research task — estimate a book's publication year from a 250-word passage — it is off by less than a year on the books it has absorbed and by roughly fourteen on the ones it has not. The authors are careful about what produces the gap: the model may be drawing on the book itself, or it may be recognizing the passage and then recalling a known fact about the work, and the experiment cannot separate the two. Both the disparity and the ambiguity about its source are the ones a study using these models on documents of uneven prominence has to confront.

**Palavalli, Bertsch & Gormley 2024.** "A Taxonomy for Data Contamination in Large Language
Models." *Proceedings of the 1st Workshop on Data Contamination (CONDA)*, 22–40.
doi:10.18653/v1/2024.conda-1.3. Key `palavalli2024`.
PDF: `_literature/Palavalli et. al. 2024 - A Taxonomy for Data Contamination in Large Language Models (CONDA).pdf`

> Sorts the ways a model can have encountered a test set before being evaluated on it, and marks which of them should count against the score. Seeing the answers counts. **Seeing only the material the questions were drawn from does not — the authors treat that as the model having adapted to the subject matter, and note it will raise performance even though it is not cheating.** Their experiments then make the boundary harder to police than the definition suggests: training on ordinary material from the same domain helped about as much as training on the test set itself. Two limits worth carrying. The experiments use a small model by current standards, and the authors expect larger ones to memorize more. And their concern is benchmarks, where a score is supposed to measure skill on unseen items, rather than a rating task where knowing the subject is part of the job.

## The response

### Evidence

*Note:* May want to refer back to Xie et. al's finding here about coherence, i.e. that models may drop the text and rely on a prior if the substitution is confusing or awkwardly worded. 

#### Why supply source text

In the bib as `mallen2023` — 61 entries, sorted, braces balanced, backup at `scratchpad/references.bib.bak14`. Author list, venue and pages verified against the PDF's own footer and the ACL Anthology record; arXiv id confirmed on the abs page.

For **The response → Evidence**:

**Mallen, Asai, Zhong, Das, Khashabi & Hajishirzi 2023.** "When Not to Trust Language Models: Investigating Effectiveness of Parametric and Non-Parametric Memories." *Proceedings of the 61st Annual Meeting of the Association for Computational Linguistics (Volume 1: Long Papers)*, 9802–9822. doi:10.18653/v1/2023.acl-long.546. Key `mallen2023`.
PDF: `_literature/Mallen et. al. 2023 - When Not to Trust Language Models.pdf`

> Asks when a model can work from what it already knows and when it needs to be handed documents. The authors build a set of 14,000 questions about people, places and works spanning a wide range of how much each subject is written about, using Wikipedia page views as the measure, and run ten models from three families over them. Accuracy tracks coverage: for almost every question type, the better known the subject the more often the model is right, and the relationship is strongest for the largest models. Size does not fix it — on the 4,000 least written-about subjects a six-billion-parameter model scores 16% and the largest GPT-3 scores 19%. Supplying retrieved passages closes much of that gap, and closes it where memory is weakest: a small model given documents beats the largest model working from memory alone on those same 4,000 questions. The result that cuts the other way is that supplying documents made the large models worse on well-known subjects. The authors trace this to the documents rather than to the models — on the 10% of questions where a passage broke an answer the model had right unassisted, the answer was usually not in the passage, while on the 17% where a passage rescued a wrong answer it nearly always was. They conclude by retrieving only when the subject is obscure.

#### Consensus vs. disagreement

Second citation of Pavlick and Kwiatkowsi (also in "What good looks like")

**Pavlick & Kwiatkowski 2019.** "Inherent Disagreements in Human Textual Inferences."
*Transactions of the Association for Computational Linguistics* 7, 677–694.
doi:10.1162/tacl_a_00293. Key `pavlick2019`.
PDF: `_literature/Pavlick and Kwiatkowski 2019 - Inherent Disagreements in Human Textual Inferences (TACL).pdf`

> Tests whether giving raters more to read brings them closer together. The authors build 300 pairs of words standing in known relationships to each other — one a kind of the other, opposites, or two kinds of the same thing — and place each pair in three settings: the two words alone, the two words each in a sentence, and one of them in a full paragraph with the other in a sentence. The same question is then asked at each level, and the spread of the answers is measured two ways: how far the ratings scatter, and how much better a two-population model fits the ratings than a single one. Both measures move the wrong way. The scatter grows steadily with context, from .34 for bare words to .41 for sentences to .56 for paragraphs, with all three levels significantly different. The second measure rises from words to sentences and then stops, showing no further gain from the paragraph. Their example is a case where people broadly agree that boating may or may not involve a picnic; told the boating happens on a particular canal used for particular things, they divide into two camps. The authors read this as preliminary evidence that disagreement is not something more context can be relied on to resolve, and that it may deepen it.

#### Summarizing and de-identifying 

##### Deidentification

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

**Yang, Zhu & Gurevych 2025.** "Robust Utility-Preserving Text Anonymization Based on Large
Language Models." *Proceedings of the 63rd Annual Meeting of the Association for Computational
Linguistics (Volume 1: Long Papers)*, 28922–28941. doi:10.18653/v1/2025.acl-long.1404.
Key `yang2025`.
PDF: `_literature/Yang et. al. 2025 - Robust Utility-Preserving Text Anonymization Based on Large Language Models (ACL).pdf`

> Rewrites text so that the person described cannot be identified from it while keeping it usable for a classification task, treating those two goals as competing objectives to be balanced rather than one as a side effect of the other. Two components do the judging: a language model asked to name the person the passage describes, scored by how often it succeeds and how confident it is, and a check on whether a classifier can still recover the passage's label. A third rewrites the text in response to both, repeatedly. The numbers show what is at stake. A classifier reads the original passages correctly 99.58% of the time. The previous best method cuts the identification rate from 100% to 52.91%, but the classifier falls to 92.02%. Theirs holds identification at the same level while the classifier stays at 96.02%. Two results carry over to any study that strips identifying detail before scoring. How much accuracy is lost depends on how the stripping is done, so a drop after de-identification is not by itself evidence that the name was doing the work. And roughly half of passages remain identifiable after careful rewriting, which is where these methods bottom out against a capable reader.

##### Summarization

**Benoit, De Marchi, C. Laver, M. Laver & Ma 2026.** "Using Large Language Models to Analyze
Political Texts through Natural Language Understanding." *American Journal of Political Science*,
1–17. doi:10.1111/ajps.70050. Key `benoit2026`.
PDF: `_literature/Benoit et. al. 2026 - Using large language models to analyze political texts through natural language.pdf`

> Scores party manifestos on six policy dimensions in two stages rather than one. A manifesto can run past 150 pages while saying anything about a given issue in a sentence or two, so instead of handing over the whole document the authors ask the model for a 300–400 word summary of what it says about one issue, then score that summary on a seven-point scale. They give three reasons. Long documents invite the model's attention to drift; skipping the summary in prototyping produced substantially worse results; and a summary can be read by a person, which lets a researcher see what a score was based on even when the original is in a language they do not know. The authors also treat the summary as a defense against memorization, on the reasoning that summaries written for the study cannot have appeared in any training corpus. They test this by deleting party names from the summaries and rescoring: the new scores correlate at .99 with the originals, which they read as showing that names had no meaningful influence. Two features of that test are worth noting. Just under half the summaries contained a party name in the first place, and what is measured is whether the scores moved, not whether the party remained identifiable from the text that was left.

**Xu, Shi & Choi 2024.** "RECOMP: Improving Retrieval-Augmented LMs with Compression and
Selective Augmentation." *Proceedings of the Twelfth International Conference on Learning
Representations (ICLR 2024)*. arXiv:2310.04408. Key `xuf2024`.
PDF: `_literature/Xu et. al. 2024 - RECOMP - Improving Retrieval-Augmented LMs with Compression and Selective Augmentation (ICLR).pdf`

> Puts a compression step between retrieved documents and the model that reads them, and trains a small model to do the compressing. Two versions are built: one selects sentences out of the retrieved documents, the other writes a fresh summary drawing on several of them at once. Both compress with respect to the question being asked rather than in general, so what survives is what bears on that question — and if the documents turn out not to help, the compressor is allowed to return nothing at all. On question answering the documents come down to five to ten percent of their original length while answer quality falls by less than a tenth; on a language modeling task a quarter of the original length costs almost nothing. The reasons given are the expense of feeding long documents to a large model and the noise that retrieval brings with it. Neither is a concern about memorization, which is worth noting: compressing evidence before a model scores it is a standard move made for ordinary reasons.

### Fine-tuning

The second intervention trains the model on the coders rather than on what the panel settled at, and three sources place it. Maerz and colleagues, cited below, establish that the move is available in this domain. Uma and colleagues establish what changes when the training target becomes the coders' spread instead of a single label. Peterson and colleagues supply the demonstration, along with two predictions the later sections test. The sequence runs from the move being available, to what training on the spread buys, to what it should look like when it works, to the condition under which it works at all.

1. **Maerz, Schafer & Schneider** show that fine-tuning a smaller model on human-coded regime text produces a rater competitive with a frontier model, which establishes the approach in our setting. What that model trains on is one label per item, which is the point of departure.
2. **Uma et al.** establish what the training target determines. Their comparison across six datasets returns a result that is simple to state: models trained on a single agreed label do best when scored against a single agreed label, and models trained on the annotators' spread do best when scored against that spread, without exception. Since the target section has already argued the panel distribution is what we are trying to hit, this is the training method that aims at it.
3. **Peterson et al.** show the gain is not merely a closer fit to the training data, and give us two specific things to look for. The improvement grows the further the test data sits from what the model was trained on, and the trained model becomes markedly less confident when wrong while staying confident when right. The first is criterion 2's error shape; the second is the calibration result in §5, arriving as an expectation rather than a discovery.
4. **The condition, stated here rather than left to a referee.** Uma et al. find that training on the spread helps only where there are enough judgments per item for the proportions to mean something and enough genuine disagreement for them to differ from the single label. Peterson's images carried about fifty-one judgments each; V-Dem panels run closer to eleven. Note also that the requirement falls on the training data, where panels are thickest, rather than on the thin panels the method is meant to serve.

**Maerz, Schafer & Schneider 2026.** "Listening to Leaders: Illiberal Speech as a Symptom of
Democratic Decline." Working paper (Melbourne / CEU Democracy Institute / CEU). Data:
doi:10.7910/DVN/OHGRC3. Key `maerz2026b`.
PDF: `_literature/Maerz et. al. 2026 Listening to Leaders.pdf`

> Illustrates how fine-tuning a smaller model on human-coded regime text yields a rater that is competitive with a frontier model. The contrast with our project is that the fine-tuning occurs on a single gold label whereas fine-tuning on individual coder labels enables it to learn a ratings distribution whereby the same weights support a modal panel-member rating or a consensus estimate. 

**Uma, Fornaciari, Hovy, Paun, Plank & Poesio 2021.** "Learning from Disagreement: A Survey."
*Journal of Artificial Intelligence Research* 72, 1385–1470. doi:10.1613/jair.1.12752.
Key `uma2021`.
PDF: `_literature/Uma et. al. 2021 - Learning from Disagreement - A Survey (JAIR).pdf`

> Surveys the methods available for training a model when the annotators disagree, then tests them against each other on six datasets. The methods divide four ways: combine the annotations into one label, discard or down-weight the items annotators could not settle, train directly on the annotations themselves, or keep a single label and add the spread as supplementary information. The comparison yields a result that is easy to state and easy to overlook — a model does well at whatever it was trained for. Models trained on one agreed label score best when scored against one agreed label; models trained on the spread score best when scored against the spread, on every dataset they tried and with no exception. Training on the spread also beat training on a combined label across their datasets and measures. The authors then ask when the spread is worth using and identify two requirements: enough annotations per item for the proportions to carry information, and enough real disagreement that the spread differs from the single label. Where annotators nearly always agree, it adds nothing. On one dataset, the one with the most annotations per item, training on the annotations alone beat training on the agreed label even by the conventional measure. Their recommendation is to report both kinds of score unless disagreement on the task is rare.

**Peterson, Battleday, Griffiths & Russakovsky 2019.** "Human Uncertainty Makes Classification
More Robust." *Proceedings of the 2019 IEEE/CVF International Conference on Computer Vision
(ICCV)*, 9617–9626. doi:10.1109/ICCV.2019.00971. Key `peterson2019`.
PDF: `_literature/Peterson et. al. 2019 - Human Uncertainty Makes Classification More Robust (ICCV).pdf`

> Builds the data the argument needs and then trains on it. The authors collect 511,400 classification judgments from 2,571 people across the 10,000 images of a standard image test set, about fifty-one per image, which makes the spread on each item something measured rather than assumed. They observe that training toward the single most common answer is only the right target if every other category truly has no chance, which is not what the human judgments show. They then retrain eight networks on the human proportions instead. Accuracy rises on every test set, and by more the further the test set sits from the training data — roughly a point on the nearest, two on the farthest — with the corresponding improvement on the distributional measure running from about a quarter to nearly two-fifths. The change in behavior is specific: the networks become substantially less confident when they are wrong and only slightly less confident when they are right. They also hold up better against deliberately corrupted images, roughly halving the damage, with no training directed at that. The argument is that the mistakes people make carry information about which categories resemble each other, and a model given that information generalizes better than one told only the winner.

## Expectations

#### Prominence

Longpre's models revert to memory when the entity is obscure and follow the text when it's well known; Xie's GPT-4 held its prior on 80% of the most prominent questions.

Data contamination — Carlini ties recoverability to how many times a document appeared; Chang's model is off by under a year on books it has absorbed and fourteen on the rest, and which books it absorbed tracks web frequency.

Mallen shows that parametric memory is reliable on popular facts, poor on the long tail 