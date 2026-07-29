# Fine-Tuning Epochs and Data Budget: Rationale

*See also `notes/finetune-training-target.md` for what the training objective
estimates (the conditional distribution of coder ratings, not individual ratings) —
it explains why eval loss plateauing at the coder-disagreement entropy floor means
convergence, not underfitting.*

Updated 2026-07-20 after the smoke test (#54) measured single-GH200 throughput
(~0.375 samples/sec → ~25 days per epoch over the full 802K training set) and the
resulting redesign: a stratified ~100K-case subsample (#59) trained with early
stopping, 1-epoch budget with extension (see protocol below).

## Why fewer epochs for large LLMs than for BERT/BART

When fine-tuning smaller models like BERT or BART (110M–400M parameters) on small
datasets (5K–20K examples), more epochs are needed: the model sees little signal per
epoch and benefits from 5–10 passes to converge. Reviewer expectations of "5–10 epochs
with early stopping" come from that regime and are correct for it.

The situation is different here:

**Dataset size.** ~100K subsampled examples at effective batch 16 = ~6,250 gradient
steps per epoch, each on a fresh batch. The optimizer receives far more unique signal
per epoch than in a small-dataset BERT setting.

**Model scale and pretraining.** Llama 3.3 70B has already internalized rich
representations of political language, institutional actors, and human rights
conditions. Fine-tuning adjusts ordinal thresholds against a globally calibrated
standard — a lower-dimensional problem than learning the domain.

**Task simplicity.** The output is a single integer on an ordinal scale. Simple output
spaces converge fast. Empirically: the smoke test converged (eval loss flat, token
accuracy ~95%) within a single epoch on just 1,800 examples — though that subset was
near-single-indicator, so full-task convergence will take longer.

**Label noise.** Individual coder ratings have substantial within-panel variance.
Repeating noisy examples risks memorizing specific coder draws rather than learning
calibration patterns. Fewer passes reduce this risk.

## Unique examples beat repeated epochs at fixed compute

Given a fixed compute budget, is 50K examples × 2 epochs better than 100K × 1? No —
maximize unique examples:

1. **Information content.** A repeated example produces a gradient highly correlated
   with its first pass; a fresh example brings new signal. Muennighoff et al. (2023)
   find the penalty for a few data repeats is modest but fresh data weakly dominates
   whenever available — and we are discarding 700K examples either way.
2. **Coverage is the binding constraint, and epochs cannot buy it.** Halving the pool
   halves per-indicator coverage (~485 → ~242) and thins rare indicator × level cells —
   exactly where the residual calibration risk sits. Seeing one scarce level-4 example
   three times never substitutes for three different level-4 examples.
3. **Memorization arrives faster on repeats**, particularly for verbatim
   (evidence → rating) pairs.

Decision rule: maximize unique examples up to the compute budget; let early stopping
trim; let epoch extension add passes only if the data demands it.

## Underfitting vs. overfitting at this scale

- **Underfitting** (large-data regime makes it unlikely) shows up as eval loss still
  falling when the epoch ends — cheap to detect, cheap to fix (extend an epoch).
- **Overfitting** (large-model regime makes it possible) shows up as the train/eval
  gap opening. Two mitigations: early stopping monitors exactly this signal, and
  rank-16 LoRA caps trainable capacity at ~207M parameters (0.29% of the model —
  roughly BART-large-sized, though steering a 70B feature space). Full fine-tuning of
  70B on 100K examples would memorize quickly; the LoRA bottleneck damps it.
- Smoke-test evidence of a healthy fit: train loss 0.106 vs eval loss 0.095 at epoch
  end — no meaningful gap.

## Protocol (what we do, and how to phrase it for reviewers)

Training uses **early stopping on held-out validation loss** (patience 10 eval steps,
threshold 0.002, eval every 100 steps — matches `slurm/run_finetune.sh`'s
`--early-stopping-patience 10 --save-steps 100`; see #60) within a **1-epoch budget over the
shared 100K pool, extended by additional epochs over the same pool** for any variant
whose eval loss is still declining at the epoch boundary (checkpoint-resume makes
extension cheap; same-pool extension preserves cross-variant comparability — see #59).
Comparison is between best checkpoints (`load_best_model_at_end`).

The held-out validation set is drawn by **country-year-indicator cell, not by coder-row**:
all ~8 coder ratings of one cell (byte-identical prompt) land on the same side of the
split, and the same cells are held out in every variant. A coder-row split leaks eval
prompts into training and lets eval_loss reward document memorization — this bug was
caught after the first full training runs and forced a from-scratch re-run of all three
variants; see `notes/finetune-validation-split-leakage.md`.

The methods section should *not* say "we trained for 1 epoch." It should say: "we
trained with early stopping on a held-out validation set, with an epoch budget extended
until convergence; all variants' stoppers fired after X, Y, Z steps respectively." The
data — not a fixed epoch count — decides when training ends, which satisfies the
substance of the multi-epoch reviewer critique in both the BART and LLM regimes.

Differential stopping times across variants are an outcome, not a confound, given the
shared case pool, identical stopping rule, and identical seeds (see #59 for the
three-seed protocol).

## What the literature says

- Muennighoff, N., Rush, A. M., Barak, B., Le Scao, T., Piktus, A., Tazi, N.,
  Pyysalo, S., Wolf, T., & Raffel, C. (2023). Scaling data-constrained language
  models. *Advances in Neural Information Processing Systems 36* (NeurIPS 2023).
  — repeating data yields diminishing returns relative to fresh data; small numbers
  of repeats are tolerable, fresh data weakly dominates.
- Taori, R., Gulrajani, I., Zhang, T., Dubois, Y., Li, X., Guestrin, C., Liang, P., &
  Hashimoto, T. B. (2023). Alpaca: A strong, replicable instruction-following model.
  Stanford CRFM. — 3 epochs on 52K instruction examples.
- Touvron, H., et al. (2023). Llama 2: Open foundation and fine-tuned chat models.
  arXiv:2307.09288. — supervised fine-tuning for 2 epochs.
- Zhou, C., et al. (2023). LIMA: Less is more for alignment. *NeurIPS 2023*. —
  small high-quality datasets suffice for capable base models; supports the
  thresholds-not-domain-knowledge view of what fine-tuning contributes here.
- OpenAI fine-tuning guidance recommends fewer epochs as dataset size increases;
  1–3 epochs is standard for instruction/classification fine-tuning of large LLMs.

## Per-variant step time: summ is slower despite shorter sequences

Observed in job run 2026-07-20 (cancelled at step ~300 before checkpoint-500):

| Variant | batch_size | grad_accum | max_seq_len | s/it  |
|---------|-----------|------------|-------------|-------|
| raw     | 1         | 16         | 8192        | 42.30 |
| anon    | 1         | 16         | 8192        | 43.49 |
| summ    | 2         | 8          | 4096        | 60.77 |

The summ configuration was intended to exploit shorter sequences by doubling the
micro-batch, but it ran ~43% slower per optimizer step. Two likely causes:

1. **Backward pass cost scales with micro-batch size.** Each of summ's 8 accumulation
   steps runs a backward pass over 2 examples. Raw/anon run 16 backward passes over 1
   example each. Total backward-pass compute is the same, but 2-example backward passes
   are not 2× faster than two 1-example passes — batched backward passes carry overhead.

2. **Padding waste.** Summ sequences have p99 of 1,943 tokens but are padded to 4096,
   wasting ~50% of each forward pass on padding positions.

**For future re-runs:** switch summ to `BATCH_SIZE=1, GRAD_ACCUM=16` (matching raw/anon)
and tighten `MAX_SEQ_LEN` to 2048 (just above p99=1,943) to eliminate padding waste.
Changing these parameters mid-run risks optimizer state mismatch, so apply only when
starting from scratch. The current 6-day wall clock has sufficient headroom (~3.7 days
estimated for summ at 60 s/it over ~5,300 remaining steps).
