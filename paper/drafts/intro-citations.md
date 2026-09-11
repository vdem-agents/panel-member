# Introduction citations: the synthetic coding literature

*Assembled 2026-09-07 for the Introduction's literature paragraphs. Organized as the narrative
arc rather than by topic, so each entry sits where it is meant to be used. Sources inventoried
from `satp/code-satp/literature/` and `papers/*/nlp-coding.bib`, `v-dem-coding/_literature/`,
and the `2010 Measuring Labor Rights` manuscript folder.*

*Companion file: `theory-citations.md` in this directory covers the theory section, organized as
groups A through N. This one covers the Introduction.*

*Mini-abstracts below are taken from the papers themselves (PDF text), not from memory, except
where an entry is explicitly marked as unverified. Where a paper's own framing matters to how we
should cite it, that is called out under **Use**.*

---

## The arc in one paragraph

Machine coding of expert source documents is not new, and work in the human rights literature
has argued that what a classifier extracts from a report can tell us something about how humans
were reading it. Large language models generalized the approach and raised agreement with
expert labels enough that substitution has become a live option. That work has now reached
several of the flagship expert-coded measures. Validation in this literature, however, remains
largely correlational, and agreement with expert coders does not by itself distinguish a model
that reads the documents from one that draws on what it already knows about the country.

---

## Move 1. Machine coding of expert sources predates LLMs

The point of this move is that the question predates LLMs, and that much of the relevant work
was done in the human rights literature on the same State Department country reports we use to
build evidence packets. Two research teams carry it.

### Greene, Park & Colaresi. 2019. *Political Analysis* 27(2): 223–230

doi:10.1017/pan.2018.11. **Note the author order: Greene is first on this one, Park is first on
the 2020 APSR paper.** All three at Pitt at the time.

The debate they enter is whether human rights standards have drifted over 30 years, which would
mean that measures like the Political Terror Scale and CIRI record changes in coder behavior
rather than changes in state practice (Clark & Sikkink 2013; Fariss 2014). Their move is to
translate that question into a supervised learning problem. If coders applied a constant
standard, the mapping from textual features to coded score is time-constant, so a classifier
trained on old reports should predict scores for new reports about as well as one trained on new
reports. If standards drifted, the same textual features carry different scores at different
times and accuracy degrades across the time gap. They train a range of algorithms on older
versus newer report windows and find that training on old reports lowers accuracy on recent
ones, which is consistent with standards having changed.

**Use.** *Probably the most useful single cite in this note, though on narrower grounds than a
first reading suggests.* The design parallel is real but loose: they treat the structure of
classifier error as more informative than its rate, which is the general intuition behind our
criterion 2. The inference runs the other way, however. They use machine error to learn about
humans, asking whether the human labeling function drifted over time, whereas we use machine
error to learn about the machine, asking whether it errs where a human coder would. Their
diagnostic is accuracy decay across training windows, not error shape across cases. Do not
describe it as the same design as ours.

The stronger connection is to our core contribution rather than to criterion 2. Their account of
the mechanism states a version of the reading-versus-reciting question about human coders:

> "Coding information effects could occur when human coders read texts differently across years.
> For example, it is likely that coders have access to more information about countries in
> recent times, and so might inadvertently **augment their scores in recent years with
> information that is not in the text**, while they rely more closely on the text in earlier
> years." (p. 223)

This is close to the reading-versus-reciting distinction, raised about human coders, seven years
before we ask it about a model. It suggests we can position the paper as taking up a standing
question in measurement rather than importing a machine learning preoccupation into political
science. Worth quoting or paraphrasing in the Introduction.

There is also a secondary tie to criterion 2, but only to its signed-deviation half. A coder who
imports information not in the text should deviate directionally rather than symmetrically,
which is what our signed-deviation test is built to detect and what Weidmann et al. report for
LLMs. The difficulty-slope half of criterion 2 has no counterpart in their design.

### Park, Greene & Colaresi. 2020. *APSR* 114(3): 888–910

doi:10.1017/S0003055420000258. Park at East Carolina by this point, Greene and Colaresi at Pitt.

They reconceptualize human rights as a taxonomy of nested rights that get judged in textual
reports, and argue that denser available information should produce deeper taxonomies over time.
Using a supervised-learning system, they extract the implicit taxonomies of rights judged in US
State Department, Amnesty International, and Human Rights Watch texts, 1977–2016 (HRW from
1997). They find the taxonomies became deeper and more hierarchically complex, with more
attention to specific rights and sharper distinctions between them.

**Use.** Secondary to the 2019 paper. Cite it for two facts: these are the same source documents
our evidence packets are built from, and they are tractable to machines at scale. The taxonomy
argument itself is not our concern. One sentence, or fold into the 2019 cite.

### Park, Greene & Colaresi. 2020. *Journal of Human Rights* 19(1)

doi:10.1080/14754835.2019.1671174. The PULSAR system, which takes syntax and word order into
account so that both the judgment and the right being judged can be extracted.

**Use.** Third-tier. Include only if the paragraph needs a methods-level citation. Probably cut.

### Cordell, Clay, Fariss, Wood & Wright. 2022. *ISQ* 66(2): sqac016

doi:10.1093/isq/sqac016. Research note. Cordell was at UT Dallas then and is now at Pitt, so
describing this as Pitt work is anachronistic for the published paper though correct for her
current projects.

Their framing closely parallels ours: most cross-national human rights datasets rely on human
coding for yearly country-level indicators, hand-coding those documents is "tedious and
time-consuming, but has been viewed as necessary given the complexity and detail of the
information contained in the text," and automated text analysis may streamline it "without
sacrificing accuracy." They apply supervised machine learning to extract specific physical
integrity rights allegations from the original text of country human rights reports, producing
**163,512 unique abuse allegations across 196 countries, 1999–2016**, at a level of granularity
(allegation-level rather than country-year) that had not existed before.

**Use.** Pair with Greene/Park/Colaresi to carry this move. It supplies the cost-and-tedium
motivation in someone else's words, on a different dataset, which is more persuasive than
asserting it ourselves about V-Dem. Also the published precedent for Cordell's in-progress work
in Move 3.

### Lineage cites (footnote at most, pick one)

- **Schrodt & Gerner. 1994.** "Validity Assessment of a Machine-Coded Event Data Set for the
  Middle East, 1982–92." *AJPS* 38(3): 825–854. An early reference for machine coding in
  political science and for validating machine codings against human ones.
- **Nardulli, Althaus & Hayes. 2015.** "A Progressive Supervised-Learning Approach to Generating
  Rich Civil Strife Data." *Sociological Methodology* 45(1): 148–183. Argues for a hybrid of
  machine and human coding on comparative-advantage grounds, illustrated with the SPEED project.
  Finds that machine-based event generation misses within-category variance while human
  categorization of civil war periods misspecifies periods of calm and unrest, so each may
  correct the other. Of the lineage cites, the closest to our "augment rather than replace"
  framing.
- **Hu et al. 2022.** "ConfliBERT: A Pre-trained Language Model for Political Conflict and
  Violence." NAACL-HLT 2022: 5469–5482. Domain-specific pretraining beats general BERT across 18
  tasks on 12 conflict datasets, with the largest gains under limited training data. Use for the
  one-line point that the pre-LLM answer was to pretrain a domain model.

**Drafting note.** Two cites carry this move. Everything after Cordell belongs in a footnote or
gets cut. Resist the urge to survey.

---

## Move 2. LLMs generalized it, and agreement with experts is now high

### What "outperform" actually rests on

This is worth getting right, because the claim appears to be narrower than the titles suggest.
Across these papers, human expert labels typically serve as the **standard against which accuracy
is computed**, which means the LLM cannot outperform them on accuracy by construction. What it
outperforms is generally one of three other things.

1. **Crowd workers.** Gilardi et al. is a comparison to MTurk, with trained annotators supplying
   the ground truth.
2. **Supervised classifiers.** Ornstein et al. and part of Törnberg's comparison.
3. **Human coders on a task with externally verifiable ground truth.** Törnberg is the clearest
   case among the papers reviewed here, since the correct answer comes from the world rather
   than from the coders.

A second recurring result is that LLMs exceed humans on **intercoder agreement**, meaning
consistency, which is a distinct property from accuracy and is sometimes conflated with it in
summary.

The Törnberg case seems worth dwelling on. The task is to infer a politician's party affiliation
from a single tweet, and he reports that GPT-4 succeeds on cases "that require interpretation of
implicit or unspoken references, or reasoning on the basis of contextual knowledge." Read one
way that is a capability finding. Read another way, the model may already know who these
politicians are. If so, one of the literature's stronger claims that LLMs beat expert coders
rests on a task where memorization and comprehension are difficult to distinguish. This is
useful to us, though it should be stated carefully: Törnberg's design is careful, and the
ambiguity looks structural rather than a lapse on his part.

### Gilardi, Alizadeh & Kubli. 2023. *PNAS* 120(30)

Brief report. Four samples of tweets and news articles, n = 6,183, previously labeled by trained
research assistants for five tasks: relevance, stance, topics, and two kinds of frame detection.
The same codebooks used to instruct the research assistants were given to ChatGPT as zero-shot
prompts and to MTurk crowd workers. Zero-shot ChatGPT accuracy exceeds crowd workers by about 25
percentage points on average, ChatGPT's intercoder agreement exceeds that of both crowd workers
and trained annotators on all tasks, and per-annotation cost is under $0.003, roughly thirty
times cheaper than MTurk.

**Use.** Widely treated as the paper that opened this line of work, and a clear illustration of
the comparison-class point, since the headline is "outperforms crowd workers" while the trained
annotators supply the target rather than the competition. Cite it as the point of departure and
let the comparison class do quiet work.

### Törnberg. 2025. *Social Science Computer Review* 43(6): 1181–1195

doi:10.1177/08944393241286471. Task is to identify a politician's political affiliation from a
single X/Twitter message, across 11 countries. Compares GPT-4 against conventional supervised
classifiers, expert coders, and crowd workers. GPT-4 achieves higher accuracy than both
supervised models and human coders in every language and country context, with accuracy of 0.934
and intercoder reliability of 0.982 in the US. Examining failures, he finds the LLM correctly
annotates messages requiring interpretation of implicit or unspoken references and reasoning
from contextual knowledge, capacities previously understood as distinctly human.

**Use.** The most expansive version of the substitution claim among the papers here, and a
plausible pivot into our question. See the discussion above.

### Heseltine & Clemm von Hohenberg. 2024. *Research & Politics* 11(1)

doi:10.1177/20531680241236239. GPT-4 against human expert coding of tweets and news articles on
four variables (whether the text is political, its negativity, its sentiment, its ideology)
across four countries (US, Chile, Germany, Italy). Accuracy up to 95% on short texts, dropping
for longer news articles and slightly for non-English text. They introduce a hybrid design where
disagreements between multiple GPT-4 runs are adjudicated by a human expert, which raises
accuracy while requiring human attention on under 10% of cases. Downstream, transformer models
trained on hand-coded versus GPT-4-coded data give almost identical results.

**Use.** A reasonable third cite. Two things in it are useful beyond the headline. The accuracy
drop on longer documents may matter to us, since our evidence packets are long. And the hybrid
design is a fairly close analog to augmentation rather than replacement.

### Ornstein, Blasingame & Truscott. 2023, working paper

Pre-registered analyses applying GPT-3 to sentiment analysis, ideological scaling, and topic
modeling. Reports that the approach outperforms conventional supervised learning without
extensive preprocessing or large labeled training sets, and that performance is **comparable
to** expert and crowd coding at a fraction of the cost. Proposes best practices and an
open-source package.

**Use.** Note the careful wording: comparable to experts, better than supervised methods. Useful
if we want a political-science practitioner cite, or as a substitute for Heseltine. Check
whether it has since been published before citing as a working paper.

### Weber & Reichardt. 2023. "Evaluation Is All You Need"

Prompting open generative models for social science annotation tasks, framed as a primer.

**Use.** Belongs in the methods section as support for the open-model choice, not here. Parked.

---

## Move 3. The frontier is the flagship expert-coded measures themselves

### Benoit, De Marchi, C. Laver, M. Laver & Ma. 2026. *AJPS*

doi:10.1111/ajps.70050. Received Feb 2025, accepted Nov 2025.

They argue that qualitative natural language understanding by human experts is limited by cost
and scalability, while statistical text-as-data methods scale but rest on strong and often
unrealistic assumptions, and propose using LLMs to interpret texts for meaning rather than treat
them as data. Ensemble means of LLM-generated estimates of party positions on six issue
dimensions correlate highly with mean ratings by country specialists. Applied to coalition
policy declarations, LLM estimates align more closely with standard models of government
formation than hand-coded estimates do. Their motivating observation is worth having on hand:
the Manifesto Project spent decades and millions of dollars labeling over 3 million sentences
and 5,000 manifestos with hundreds of trained annotators, and "we have no sense of their
reproducibility" because the datasets are too expensive to replicate.

**Use.** The manifestos case, and helpful for our framing. Their cost-and-irreproducibility
argument closely parallels the sustainability problem we raise about V-Dem panels, advanced by
other authors about a different dataset. Do not spring our leakage critique here; the parties
and manifestos being in pretraining is a Move 4 point.

### Weidmann, Faulborn & García. 2026. *PS: Political Science & Politics* 59(1): 17–23

doi:10.1017/S1049096525101248. Konstanz. Open access, CC BY 4.0. Replication data: 10.7910/DVN/I34X6P.

Motivated by the *PS* 57(2) symposium on whether observed democratic backsliding reflects
psychological biases in expert coding (Little & Meng 2024; Treisman 2024). They use two
frontier LLMs to code V-Dem democracy indicators. LLM-generated codings largely align with
expert coders for many countries, but where they deviate, they deviate in consistent directions:
some models are systematically too pessimistic, others consistently overestimate democratic
quality. Combining the two codings alleviates this, but they conclude it is difficult to replace
human coders with LLMs because the extent and direction of the attitudes is not knowable a
priori.

**Use.** The V-Dem case and our closest foil, usable in both Moves 3 and 4. It offers evidence
that a country-level prior operates in our setting. Our contribution relative to theirs: they
characterize the prior, while we test whether supplied evidence displaces it. Their "not
knowable a priori" conclusion is the kind of question an experimental design is better placed to
address than a correlational one.

### Maerz & Weidmann. 2026. V-Dem pilot / working paper

V-Dem measures rest on expert coders who assign ordinal scores without recording the factual
basis for their judgments. They propose using web-enabled LLMs to generate verifiable,
referenced background information per country-year and indicator, which coders then verify and
rank-order, improving transparency without inflating coder workload. Pilot on V-Dem v16, one
event-driven indicator (repression of civil society organizations), via a reproducible `quallmer`
pipeline, validated against V-Dem expert scores plus manual checks, preparing an experiment
embedded in the v17 coding process.

**Use.** Shows the V-Dem project itself is moving on this, which raises the stakes of our
question. Their design keeps the human in the loop and makes evidence auditable; ours asks
whether the model reads that evidence at all. Note their observation that coders "are not
required to explain upon which factual information they base their coding," which is the human
mirror of our problem and pairs with the Greene/Park/Colaresi quote in Move 1.

### Halterman & Keith. 2025. *Political Analysis*

doi:10.1017/pan.2025.10017. They curate three real-world political science codebooks (protest
events, political violence, manifestos) with their unstructured texts and human-coded labels,
and propose a five-stage framework for codebook-LLM measurement: preparing a codebook for both
humans and LLMs, testing basic capabilities, evaluating zero-shot accuracy, analyzing errors,
and parameter-efficient supervised training. Using open-weight 7–12B models, they find current
open-weight LLMs have real limitations in following codebooks zero-shot, but that supervised
instruction-tuning substantially improves performance.

**Use.** Supports our fine-tuning lever with open models, and serves as a counterweight to the
Move 2 optimism, since their open-weight zero-shot results are considerably weaker than the
GPT-4 numbers. Among the work reviewed here, it is also the most directly concerned with
codebook-following.

### Le Mens & Gallego. 2025. *Political Analysis*

arXiv:2311.16639. "Asking and averaging" for positioning political texts, reported correlations
above .90 against expert and roll-call benchmarks.

**Use.** Optional fourth cite. Also an expectation-readout cousin, which may make it more useful
in the readout section than here. **Unverified: no PDF in either folder, summary from the
citation note rather than the paper. Pull it before citing.**

### Cordell and coauthors, in-progress LLM projects

From `rebeccacordell.com/research-projects.html`. Titles are public, drafts are not.

- **"Measuring Sub-national Levels of Repression: A Latent Variable Model"** with Clay, Fariss,
  Wood & Wright. Latent variable models aggregating a corpus of 100,000+ allegations produced by
  an LLM coding process. **The nearest neighbor to our design that we have identified**, and the
  reason to soften the novelty claim on our second contribution. See the framing note in Move 4.
- **"Repressive Actions Dataset (RAD-SNARP)"** with the same coauthors. The continuation of the
  2022 ISQ note, classifying allegation categories with machine learning.
- **"Assessing Refugee Rights: New Data and Analysis"** with Abdelaaty & Salehyan. LLM automated
  coding of US Committee for Refugees reports. Evidence the country-report coding tradition is
  converting to LLMs across subfields.
- **"Measuring Child Recruitment in Civil Wars Using Large Language Models"** with İdrisoğlu &
  Keskin. Fine-tuning, NER, and RAG over UN documents. The fine-tuning parallel is relevant
  though the task is extraction rather than ordinal scoring.
- **"Autocracy, Terrorism Threat, and Security Cooperation"** (solo, draft available). Uses a
  fine-tuned LLM to identify violations framed in counterterrorism terms.

**Use.** Cite the first as in-progress work in the same space. Get the drafts before submission.

---

## Move 4. The turn, and our contribution

Validation across Moves 2 and 3 rests on agreement with human labels, and an agreement statistic
cannot separate a model that reads the supplied documents from one that recalls the country.
Weidmann et al. suggests what the second case may look like when it surfaces. The validation
literature below asks careful questions about error, but largely about downstream statistical
consequences rather than about mechanism.

### Pangakis, Wolken & Fasching. 2023

arXiv:2306.00176. Penn. They argue that because LLM performance varies with prompt quality, text
idiosyncrasies, and conceptual difficulty, and because those challenges persist as models
improve, any automated annotation process must validate against human-generated labels. Using
GPT-4 they replicate 27 annotation tasks across 11 datasets drawn from recent social science
articles in high-impact journals, and find performance promising but highly contingent on both
dataset and task type. They ship software implementing the workflow. Their literature framing is
useful: they explicitly note that Gilardi et al. claim ChatGPT outperforms MTurkers while Reiss
(2023) finds LLMs perform poorly and counsels caution.

**Use.** A standard reference for "validate against human labels," to be positioned as necessary
but not sufficient, since it certifies agreement rather than mechanism. Their finding that
performance is task-contingent is useful to us: if we do not know why a model works, we are less
able to anticipate where it will stop working.

### Egami, Hinck, Stewart & Wei. 2024

Columbia and Princeton. R package `dsl`. They show that treating predicted text-based variables
as if observed without error produces substantial bias and invalid confidence intervals in
downstream analyses **even when annotation accuracy exceeds 90%**. They propose design-based
supervised learning, a doubly robust procedure combining many predicted labels with a smaller
set of expert annotations, which yields valid estimates under non-random prediction error.

**Use.** Among the more developed responses to the error problem, and useful for showing we are
not duplicating it. They correct for measurement error in downstream estimates, whereas we ask
where the error comes from. Their "even above 90% accuracy" result also supports the argument
that high agreement is not self-certifying, which bears on our turn.

### Steinert & Kazenwadel. 2025. *Journal of Peace Research* 62(4): 1128–1143

doi:10.1177/00223433241279381. They query GPT-3.5 about casualties in specific airstrikes in the
Israeli–Palestinian and Turkish–Kurdish conflicts, in Hebrew versus Arabic and Turkish versus
Kurdish. The model returns fatality estimates 34 ± 11% lower when queried in the language of the
attacker than in the language of the targeted group, with evasive answers widening the gap, and
GPT-4 shows the same trend. A media content analysis of Arabic sources suggests the model fails
to link specific attacks to the fatality numbers reported in Arabic news, and instead, relying
on word co-occurrence, returns death tolls from higher-profile attacks or cumulative counts
prevalent in training data.

**Use.** A candidate for the turn sentence. It is concrete, and the mechanism is investigated
rather than simply asserted: the output appears driven by what is dense in the training corpus
rather than by the specific event asked about. That is a version of our concern, with a
quantitative estimate attached.

### Abdurahman, Salkhordeh Ziabari, Moore, Bartels & Dehghani. 2025

*Advances in Methods and Practices in Psychological Science* 8(2). Recommendations for authors
and reviewers on methodological rigor, replicability, and validity when LLMs are used to
automate data processing or simulate human data.

**Use.** Footnote at most, as evidence that evaluation practice is being codified. Not load-bearing.

### Rister Portinari Maranca et al. 2025

"Correcting the Measurement Errors of AI-Assisted Labeling in Image Analysis Using Design-Based
Supervised Learning." Same family as Egami et al., applied to images.

**Use.** Cite Egami or this, not both. Egami is the better fit since our data are text.
**Unverified: no PDF located, entry from the bib. Confirm before citing.**

### Xu et al. 2024. "Knowledge Conflicts for LLMs: A Survey." *EMNLP*: 8541–8565

Sets out parametric versus contextual knowledge as a common vocabulary in this literature, with
context-memory conflict as a named phenomenon.

**Use.** Supplies the terminology for the turn. The Introduction needs this one only; the fuller
treatment is `theory-citations.md` group B.

### Longpre et al. 2021. "Entity-Based Knowledge Conflicts in Question Answering." *EMNLP*: 7052–7063

Entity substitution shows models over-rely on parametric knowledge when context contradicts it,
and the effect is worse for high-frequency entities.

**Use.** Optional second cite in the turn. The frequency result is also our prominence-stratification
rationale, so it may be better saved for the theory section.

### Pinned for the paragraph 3 turn: upstream fixes exist, nobody audits them

*Recorded 2026-09-07. EJT wants to use this to motivate the discussion. Do not write the
Introduction's turn as "nobody intervenes upstream," which a reviewer can falsify from three
papers already cited.*

Existing interventions on the model side, all aimed at raising agreement:

- **@halterman2025b.** Supervised instruction-tuning substantially improves codebook-following
  for open-weight models. This is an upstream intervention on the model itself, and the closest
  published precedent for our fine-tuning lever.
- **Weidmann, Faulborn & García 2025.** Combining two LLM codings offsets the opposing
  directional attitudes of the individual models. An ensemble correction, upstream of the
  estimate.
- **Maerz & Weidmann 2026.** Human verification and rank-ordering of LLM-generated background
  information, upstream of the coder's score.

Downstream corrections, which take the annotation error as given:

- **Egami, Hinck, Stewart & Wei 2024.** Design-based supervised learning corrects downstream
  estimates for non-random annotation error.
- **Rister Portinari Maranca et al. 2025.** Same family, applied to images.

**The defensible gap.** Each upstream intervention is tuned for agreement and then evaluated on
agreement. None asks what the intervention did to *how the model uses the evidence*. Halterman
and Keith tune for codebook compliance and measure accuracy; they do not ask whether the tuned
model reads the document more closely or has instead learned a better prior over labels. That is
the question our fine-tuning conditions are built to answer, and it is what lets us treat
fine-tuning as a mechanism test rather than a performance improvement.

Phrase the turn as a question about auditing rather than about absence: the literature knows how
to make synthetic coders agree more, but not whether agreement was bought by better reading or
by a better prior.

### The two contributions, in order

**Core contribution: reading versus reciting.** We hold the evidence fixed and vary what the
model can recognize, so agreement with expert coders can be decomposed into what the model read
and what it already knew. This is the contribution the arc sets up, and it should be the
sentence the paragraph lands on.

**Ancillary contribution: how a synthetic coder integrates into a panel.** V-Dem aggregates many
raters through a measurement model that estimates each rater's reliability and thresholds, so a
new rater is judged by what it does to the aggregate, not by its standalone accuracy. We study
that directly: whether the synthetic coder sits in the goldilocks zone rather than merely near
the panel mean, whether its error tracks case difficulty the way a human's does, and whether
swapping it in for a human leaves the estimates intact.

**Do not claim this is unprecedented.** Cordell, Clay, Fariss, Wood and Wright are running
machine codings into a latent variable model on the repression side, which is the same two-stage
architecture. The honest distinction is narrower and still worth stating. Their measurement
model aggregates allegations extracted from documents into a latent score; it does not model a
pool of competing raters whose individual reliabilities and scale thresholds are estimated, and
nothing in that design appears to turn on whether a synthetic rater can take a human rater's
seat without moving the estimate. That last question is specific to the V-Dem panel
architecture, and it is the one we take up. Phrase the claim as "we ask what happens when a
synthetic coder joins the panel," not as "no one has studied machine coding into a measurement
model."

**Framing guidance.** State the panel contribution as the second of two, in its own short
sentence or as the second half of the contribution paragraph. It is the more concrete and
deployment-relevant result, but it is downstream of the core question: the panel dynamics only
matter if the synthetic coder is reading the evidence in the first place. If it is reciting a
prior, adding it to a panel injects correlated error into the aggregate, which is worse than
leaving the panel thin. That dependency is the reason to keep the order.

---

## Footnote: the discontinued-projects examples

The current footnote reads: "The CIRI Human Rights Data Project, START's Global Terrorism
Database, and long-standing efforts to code labor standards from country reports illustrate how
even prominent, widely used projects can lapse, scale back, or be discontinued once the coding
effort outgrows the resources available to sustain it."

**Problem: the labor standards example does not support "discontinued."** That effort was
revived and now underpins SDG indicator 8.8.2, hosted by the Center for Global Workers' Rights
at Penn State. What the record does support is **episodic coverage**, which is the sharper
version of the point. The sequence below is the argument.

**Also verify the GTD claim.** START had a real funding disruption, but the database was not
discontinued. "Scale back" may hold; "discontinued" does not.

### The labor standards sequence

- **Kucera, David. 2007.** "Measuring Trade Union Rights by Violations of These Rights." In
  *Qualitative Indicators of Labour Standards: Comparative Methods and Applications*, ed. David
  Kucera. Netherlands: Springer. Codes 170 countries for 1994–97 against 37 categories of
  potential freedom-of-association and collective-bargaining rights violations, drawn from three
  textual sources: the State Department country reports, the ICFTU Annual Survey of Violations
  of Trade Union Rights, and the ILO Committee on Freedom of Association reports. The multiple
  sources are a deliberate correction for the known bias of the State Department reports.
  Weighted violation counts are summed into an index. **Four years of coverage.**
- **Mosley & Uno. 2007.** "Racing to the Bottom or Climbing to the Top? Economic Globalization
  and Collective Labor Rights." *Comparative Political Studies* 40(8): 923–948. Uses a similar
  method to produce annual measures for 90 developing countries, 1986–2002, and analyzes the
  effect of economic globalization on labor rights. **Then the series stops.**
- **Kucera & Sari. 2019.** "New Labour Rights Indicators: Method and Trends for 2000–15."
  *International Labour Review* 158(3): 419–446. The rebuild, roughly a decade later, under new
  institutional sponsorship. 108 violation types coded across nine textual sources including six
  from the ILO, plus national legislation, for 185 ILO member states. Following a 2018 Resolution
  of the International Conference of Labour Statisticians it became the basis for SDG indicator
  8.8.2. **Five years coded between 2000 and 2015, not annual.**

Read together, the sequence suggests that coding cadence tracks available funding more than
research need. Rewrite the footnote around cadence rather than around discontinuation.

### Supporting cites

- **Teitelbaum. 2010.** "Measuring Trade Union Rights through Violations Recorded in Textual
  Sources: An Assessment." *Political Research Quarterly* 63(2). Self-cite. IRT assessment of
  whether Kucera's dichotomous violation items load on a single latent dimension, and a
  demonstration that a measurement model gives a more principled basis for combining them than
  the ad hoc weighting scheme. Also a precedent for applying a measurement model to
  violation-count coding, which parallels what the V-Dem model does to panel ratings. Confirm the
  page range against the PRQ proofs in `Final Submission/`.
- **Kucera & Sarna. 2006.** "Trade Union Rights, Democracy and Exports: A Gravity Model
  Approach." *Review of International Economics* 14(5): 859–882. Downstream use of the index.
  Probably not needed in the Introduction.
- **LaFree & Dugan. 2007.** "Introducing the Global Terrorism Database." *Terrorism and Political
  Violence* 19(2): 181–204. The GTD cite if it stays in the footnote.
- **Cingranelli & Richards, CIRI Human Rights Data Project.** Ended around 2014. Need the end
  date confirmed and a citable account of why, rather than asserting resource constraints. Note
  that CIRI is also one of the two datasets in the Greene/Park/Colaresi 2019 debate, so the
  Introduction can reuse it rather than introducing an unconnected example.

---

## What still needs doing

1. Add BibTeX entries to `paper/references.bib`. Nothing from this note is in there yet. SATP's
   `papers/classification/nlp-coding.bib` can be copied across for the Move 2 and Move 4 entries.
2. Pull PDFs into `v-dem-coding/_literature/` for the three Park/Greene/Colaresi papers and
   Cordell et al. 2022, and confirm page ranges against the published versions. Cordell 2022 is
   downloaded to the scratchpad; move it if we keep it.
3. **Get the Cordell working papers.** Four in-progress projects use LLM coding, and "Measuring
   Sub-national Levels of Repression" is the nearest neighbor to our design. Email her, or check
   whether drafts circulated at APSA or ISA. This determines how strongly we can state the second
   contribution.
4. Verify the two entries marked unverified: Le Mens & Gallego, and Rister Portinari Maranca et al.
5. Check whether Ornstein et al. has been published since the 2023 working paper.
6. Confirm the CIRI end date and the GTD funding history, or drop whichever cannot be sourced.
7. Confirm the Teitelbaum 2010 page range against the PRQ proofs.
