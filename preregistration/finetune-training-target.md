# What the Fine-Tuning Target Actually Is: A Distribution, Not a Rating

Written 2026-07-22, alongside the validation-split fix in
`notes/finetune-validation-split-leakage.md`. Companion to
`notes/finetuning-epochs.md` (which covers how long to train) — this note covers
*what is being estimated* when we train. The point is deceptively simple and worth
writing down, because the training files make it look like the target is the
individual coder rating, and it isn't.

## The apparent target

Each row of `finetune_train_{variant}.jsonl` pairs an assembled prompt (evidence
text for one country-year-indicator cell) with one coder's integer rating as the
assistant completion — `{"rating": 2}`. Read naively, the training task is "predict
what this coder said," and the natural worry follows: coder ratings are noisy, so
aren't we training the model to reproduce noise?

## The actual target

The model's output at the rating position is not an integer — it is a probability
distribution over the rating tokens 0–4. What cross-entropy training estimates is
the **conditional distribution of coder ratings given the evidence text**:

    P(rating | prompt)

To see why, take a cell whose three coders rated 2, 2, 3. The prompt is
byte-identical across the three rows (`assemble_prompt()` does not take
`coder_id`), so the model must emit one distribution p for all of them. The cell's
total loss is

    −log p₂ − log p₂ − log p₃

and the p that minimizes this is exactly the empirical frequencies: p₂ = 2/3,
p₃ = 1/3. Not the majority label, not a point mass — the distribution. This is the
general property of maximum likelihood: gradient descent is pushed toward 2 twice
and toward 3 once, and the pushes average. Panel disagreement is not noise around
the target; **it is the target**.

"Calibrated" is the out-of-sample form of this property: among cells where the
trained model assigns 70% probability to rating 2, roughly 70% of actual coder
ratings are 2. The model's probabilities are trustworthy as frequencies.

Three consequences follow.

### 1. The loss floor is the disagreement entropy

A perfectly trained model's cross-entropy at a cell equals the entropy of that
cell's coder-rating distribution — loss cannot fall below the entropy of the
distribution being matched. Averaged over cells, that is the "honest floor"
discussed in `notes/finetune-validation-split-leakage.md` (≈0.86 nats **per
rating** over the full 2016–2018 pool; ≈0.12–0.17 nats per completion token —
mind the units, which that note's original draft got wrong). Eval loss
meaningfully below the floor is not excellence; it is evidence the eval metric is
leaking. A model at the floor is not failing to converge; it is done.

### 2. The estimand matches V-Dem's measurement model

V-Dem's IRT machinery treats each coder as a noisy draw from a latent
quantity-plus-disagreement process; published scores aggregate those draws. An AI
"panel member" that learns P(rating | evidence) behaves like **a draw from the
panel** — it can be queried for its mode, its expectation, or a sample, and its
uncertainty is meaningful. A model trained toward point estimates (majority label,
or rounded panel mean) would instead behave like a committee that has already met:
it slams ~all probability onto one rating even for genuinely contested cells,
erasing exactly the disagreement information the design cares about. Same argmax
accuracy, wrong estimand. This is the principled reason the training data is
coder-level rows rather than cell-level aggregates, and it is worth a sentence in
the methods section because reviewers will otherwise read the coder-level targets
as an oversight.

### 3. Single draws per cell are unbiased but noisier — which bears on subsampling

If each cell contributed only one randomly chosen coder (the "unique-CYI
subsample" alternative considered when fixing the validation split), training
would still target the same conditional distribution *in expectation*: the drawn
label is 2 with probability 2/3 and 3 with probability 1/3, so the expected
gradient is unchanged, and the model's limited capacity forces it to fit a smooth
function across cells rather than memorizing each one — which is what does the
averaging in practice. What is lost is variance reduction at the exact input:
2, 2, 3 on one prompt is direct within-prompt evidence of disagreement at that
specific evidence text; single draws make the model infer disagreement from how
similar cells got different labels. Each contested cell becomes a single coin
flip.

In the realized ~100K subsample this distinction is mostly moot: row-level
subsampling at ~11% thins cells to ~1.55 coders each (64,240 cells — see the
corrected-run numbers in `notes/finetune-validation-split-leakage.md`), so most
cells are single coin flips already. The within-prompt soft-labeling channel
operates only in the minority of multi-coder cells. This is why keeping the
committed subsample and fixing only the split was low-cost, and why a
unique-CYI sampling design (more cell coverage, no exact-duplicate prompts by
construction) remains a live option for future work — see
`notes/follow-on-benchmarking-paper.md`.

## The train/eval asymmetry, in one sentence

The same mechanism flips sign across the split: multiple coders on one prompt is
soft labeling **in training** (the model is taught the distribution) but was
leakage **in evaluation** under the old row-level split (the model recalls the
distribution for a memorized prompt instead of generalizing) — the fix keeps
whole cells on one side precisely so the mechanism operates only where it is a
feature.

## Inference side: the extraction is the mode, and that choice is already locked

Learning a calibrated distribution does not by itself dictate how a rating is
extracted at inference. Greedy decoding returns the mode of P(rating | evidence);
sampling returns a draw; the expectation over rating-token probabilities is a
third option. These differ exactly on contested cells: a 2/3–1/3 cell has mode 2,
expectation ≈2.33, and a sampled draw is either.

The pipeline already answers this: `code_country_year.py` calls the model with
`temperature=0`, and `run_finetuned_batch.py` routes through the same
`run_coding_batch.run_batch` path — so every condition, base and fine-tuned,
extracts the **mode**. The integer-output constraint is also by design: the AI is
prompted to act as a single coder returning one ordinal rating, and the evaluation
(`AI MAE = |AI_rating − panel_mean|`, bootstrapped at the CYI level) compares that
integer to the continuous panel mean, exactly as the human benchmark compares an
individual coder's integer rating to the (leave-one-out) panel mean — see
`notes/loo-mae-computation.md`. Answering with the fractional expectation would
abandon the panel-member framing and unfairly advantage the AI against coders who
must answer on the ordinal scale.

One interpretive consequence for the LOO substitution check ("is the AI more or
less consistent than the average human coder?"): greedy extraction makes the AI
the **modal** panel member, not a typical draw. A real coder's deviation from the
panel mean includes their personal draw from the disagreement distribution; the
mode has that sampling variance removed by construction. So the AI can beat the
human LOO MAE partly by being variance-free rather than by being better centered
— the comparison is "the AI's best single guess vs. a typical coder's draw,"
which is the deployment-relevant comparison (nobody would deploy the AI at
temperature 1), but the asymmetry deserves a sentence when the result is
reported. A sampled-decoding companion run would isolate how much of any AI
advantage is variance removal; unregistered, exploratory-only if ever run.

This mode-vs-draw distinction is also the theoretical motivation for the
temperature-sampling mechanism in `notes/substitution-experiment-future-paper.md`:
if greedy decoding is the variance-free extreme of P(rating | evidence), the natural
follow-on question is whether some temperature T > 0 makes the AI's *sampled* rating
dispersion match a real human panel's dispersion — turning "add temperature to get
some spread" into a principled search for a variance-matching operating point.
