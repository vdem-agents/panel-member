## Discussion

### Persona prompting

Persona prompting was the original design for this project and was set aside in July 2026. The
literature since then has sorted itself out in a way that makes the decision easy to defend and
also points to a better version of the idea. The short form is that telling a model who someone
is does not work, while showing it what that person has previously said does. None of this is a
limitation of older models — it holds at the frontier — so the question for a synthetic panel is
not whether to wait for better models but what to condition them on.

1. **Demographic conditioning does almost nothing.** Bisbee et al. built three prompts from the
   same ANES respondents — demographics only, politics only, and both — and the politics-only
   prompt performs about as well as the full one. Taday Morocho et al. isolate the same thing with
   a matched design in which the persona and control prompts differ only by the demographic
   clauses, and find no consistent gain.

2. **Political identity carries the signal, and overdoes it.** In Bisbee et al., ideology tracks
   the human data closely and partisanship tracks it strongly, while the remaining covariates do
   far worse and sometimes reverse sign. But the partisan relationship is stronger in the synthetic
   data than in the human data. This is the same pattern Vallejo Vera and Driggers report: the
   models respond to party cues that did nothing to human coders, reading the cue more widely than
   people do. Aher et al. find a third version of it, which they call a hyper-accuracy distortion —
   in a Wisdom of Crowds replication the larger and more aligned models give answers that are more
   accurate than any human crowd, in the extreme case with most simulated participants answering
   every question exactly right. In all three the model produces the stereotyped response more
   cleanly than the people it is imitating.

3. **The optimists now concede the point.** Horton et al.'s 2026 revision attributes the poor
   fidelity of much of this literature to its reliance on "simple social and demographic traits,"
   noting that instructions like "respond as a 30-year-old male" assume the model can represent how
   those traits interact with the setting, and that when it cannot the simulation "default[s] to
   caricatures of the target persona." What they defend instead is conditioning on a theoretically
   grounded preference structure — and they report that giving agents hobbies or favourite
   television shows does nothing for fit while social-preference descriptions do.

4. **This is not a model-generation problem.** Jia et al. run GPT-5.4, Gemini 3 Flash and Claude
   Haiku 4.5, and conclude that model choice is secondary: gains from the choice of model are small
   next to gains from the persona architecture. The failures persist at the frontier.

5. **What works is conditioning on the person's own prior answers.** Jia et al.'s best-performing
   setup retrieves a respondent's pre-2023 survey history rather than describing their attributes,
   and it improves alignment with the distribution of human answers substantially over a no-context
   baseline.

6. **Where personas work is where a panel needs them least.** Jia et al. find accuracy highest for
   low-variability questions and common response patterns, and lowest for high-variability
   questions and rare ones. Taday Morocho et al. report the matching result that subgroup fidelity
   sometimes degrades in low-support strata. Coder disagreement is high variability by definition,
   and thin panels are low support, so the diversity a synthetic panel would need to reproduce sits
   in the region where the method performs worst.

7. **Too little variance is the specific failure, and it inflates apparent sample size.** Bisbee et
   al.'s synthetic responses have far smaller standard deviations than the human ones. Their power
   calculation makes the cost concrete: on the synthetic estimates, 33 partisan respondents would
   suffice for 99% power. Applied to a panel, this is the failure that matters — five synthetic
   coders that differ in their prompts but cluster tightly in their ratings would be read by the
   measurement model as five coders' worth of information when there is only one.

8. **Fine-tuning and persona conditioning answer different questions.** Both can use the same
   coder-level ratings; the difference is where coder identity lives. Fine-tuning pools across
   coders and puts a single standard into the weights, dissolving individual identity — which is
   what this paper wants, and which yields exactly one synthetic coder. Conditioning at inference
   keeps coder identity as a run-time variable, so one model can supply many coders without many
   trainings. Our question is whether an AI coder can match the panel; the persona question is
   whether AI coders can be a panel.

9. **Our few-shot condition is already the architecture that wins in this literature, pooled.**
   Supplying retrieved evidence-and-rating examples is the same operation as Jia et al.'s
   retrieval-augmented persona. The difference is the conditioning target: we pool to a single
   global standard rather than conditioning on one coder. The open question is therefore not
   persona versus our approach but whether the calibration target should be a coder or the panel.

10. **The obstacles to a per-coder version are specific.** Fine-tuning pools, so thin coders borrow
    strength from the rest; per-coder conditioning has no pooling, and the panels most in need of
    filling are the ones whose coders have the least history to condition on. Conditioning on a
    coder's own prior-year score for the same country would largely hand over the answer, since
    V-Dem ratings are strongly autocorrelated — the legitimate version conditions on that coder's
    ratings of other countries. And a persona that succeeded in reproducing a lenient regional
    coder would be importing the calibration variance the project exists to reduce.

11. **A better future direction than prompting.** Fine-tune with the coder identifier as an input,
    training on evidence, coder, and rating together, so the model learns per-coder offsets rather
    than being told about them in prose. Learned offsets are more likely to survive than described
    ones, which is the central lesson of this literature.


**Argyle, Busby, Fulda, Gubler, Rytting & Wingate 2023.** "Out of One, Many: Using Language Models
to Simulate Human Samples." *Political Analysis* 31(3): 337–351. doi:10.1017/pan.2023.2.
Key `argyle2023`.
PDF: `_literature/Argyle et. al. 2023 - Out of One, Many - Using Language Models to Simulate Human Samples (Political Analysis).pdf`

> The paper that made the case. The authors give GPT-3 the background details of thousands of real survey respondents — age, race, education, ideology, party, and so on — and treat the model's answers as a "silicon sample" standing in for those people. They run three tests: asking the model to list words describing the other party, and reproducing the relationships between demographics, attitudes and reported vote in two American election surveys. In each the synthetic pattern resembles the human one. They name the property they are measuring algorithmic fidelity and argue that where it can be established, researchers can use silicon samples to explore hypotheses before spending money on human subjects.

**Horton, Filippas & Manning 2023.** "Large Language Models as Simulated Economic Agents: What Can
We Learn from Homo Silicus?" NBER Working Paper 31122 (April 2023, revised February 2026).
arXiv:2301.07543. Key `horton2023`.
PDF: `_literature/Horton et. al. 2023 - Large Language Models as Simulated Economic Agents - What Can We Learn from Homo Silicus (NBER).pdf`

> Argues that a language model can be used the way economists use a model of rational behavior: give it an endowment, a set of preferences and a situation, and see what it does. The authors rerun several classic experiments this way — on fairness in bargaining, on whether raising a price after a demand shock is judged unfair, and on the tendency to stick with a default option — and recover results that resemble the originals. The revised version is more cautious than the first: it checks whether the models are simply reciting the published studies by moving the scenarios away from the familiar examples, it concedes that a researcher can try prompts until one gives the desired answer and proposes publishing all code as a remedy, and it reports cases where different models disagree. It also explains why so much of this literature gets poor results, pointing at prompts built from simple demographic traits.

**Aher, Arriaga & Kalai 2023.** "Using Large Language Models to Simulate Multiple Humans and
Replicate Human Subject Studies." *Proceedings of the 40th International Conference on Machine
Learning*, PMLR 202: 337–371. Key `aher2023`.
PDF: `_literature/Aher et. al. 2023 - Using Large Language Models to Simulate Multiple Humans and Replicate Human Subject Studies (ICML).pdf`

> Proposes simulating not one person but a whole sample of participants, and tests the idea by rerunning four well-known studies drawn from economics, psycholinguistics and social psychology. Three of the four reproduce the published findings. The fourth does not, and the way it fails is the interesting part: asked general-knowledge questions of the kind used to study the accuracy of crowds, the larger and better-aligned models answer far more accurately than people do, to the point where most simulated participants get every question exactly right. The authors call this a hyper-accuracy distortion. It is the clearest demonstration that a model asked to imitate a population can produce something more orderly than the population itself.

**Bisbee, Clinton, Dorff, Kenkel & Larson 2024.** "Synthetic Replacements for Human Survey Data? The
Perils of Large Language Models." *Political Analysis* 32(4): 401–416. doi:10.1017/pan.2024.5.
Key `bisbee2024`.
PDF: `_literature/Bisbee et. al. 2024 - Synthetic Replacements for Human Survey Data.pdf`

> Repeats the silicon-sample exercise carefully and finds it breaks down wherever it matters. Personas built from real survey respondents are asked how warmly they feel toward eleven political and social groups. The averages look right — every synthetic mean falls within one standard deviation of the human one — but the spread around them is far too narrow, and when the synthetic data are used for the kind of regression a researcher would actually run, just under half the coefficients differ significantly from their human counterparts, some with the opposite sign. Two further results matter here. Splitting the persona into a demographic half and a political half shows that the political half does nearly all the work. And the artificially narrow spread has a cost that can be counted: on the synthetic estimates, a study would appear to need only 33 respondents for very high power.

**Taday Morocho, Cima, Fagni, Avvenuti & Cresci 2026.** "Assessing the Reliability of
Persona-Conditioned LLMs as Synthetic Survey Respondents." *Companion Proceedings of the ACM Web
Conference 2026*, 320–329. doi:10.1145/3774905.3795477. arXiv:2602.18462. Key `tadaymorocho2026`.
PDF: `_literature/Taday Morocho et. al. 2026 - Assessing the Reliability of Persona-Conditioned LLMs as Synthetic Survey Respondents (ACM).pdf`

> Isolates the contribution of the demographic description itself. Two prompts are compared that are identical except for the clauses naming the respondent's attributes, and both are scored against a third party's actual answers in a large international values survey, across more than seventy thousand respondent-question pairs, with a random guesser as the floor. Adding the persona produces no consistent improvement: on one model it helps slightly, on the other it hurts slightly, and the effect varies item by item. Agreement with particular subgroups does not improve reliably either, and gets noticeably worse for the smallest ones. The authors' recommendation is to stop treating persona prompting as generally beneficial and to report the matched no-persona baseline alongside it. Note that both models tested are small.

**Jia, Chen, Sharma & Diaz-Rodriguez 2026.** "When Can Digital Personas Reliably Approximate Human
Survey Findings?" arXiv:2605.10659. Key `jia2026`.
PDF: `_literature/Jia et. al. 2026 - When Can Digital Personas Reliably Approximate Human Survey Findings (arXiv).pdf`

> Sets up the strongest test of the idea so far and returns a conditional answer. Personas are built from a long-running Dutch panel — not only each respondent's background but their own answers to earlier waves — and then scored against what those same people said in later waves the models could not have seen. Four ways of building the persona are compared across three current models. Giving the model the person's own past answers works best, and personas of this kind match the overall distribution of human responses much better than a model given no context at all. What they still cannot do is predict any particular individual, or reproduce the way one person's answers hang together across topics. Two findings bear directly on using personas to diversify a panel: which model is used barely matters next to how the persona is built, and accuracy is highest on questions where people mostly agree and lowest where their answers are varied or unusual.