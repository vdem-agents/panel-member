# Fine-Tuning Internal Validation Split: CYI-Cell Leakage and Fix

Written 2026-07-22, after reviewing the completed FT-raw/FT-anon/FT-summ training logs
(jobs 73473530–73473532). Distinct from the two contamination types catalogued in
`notes/data-leakage-contamination.md` — this is not pretraining-corpus contamination,
it's a leak internal to the fine-tuning job's own train/eval split.

**Status: code fixed 2026-07-22.** `finetune_llama.py` now splits by CYI cell
(`grouped_cell_split()`). See "Implemented fix" below for where the implementation
deliberately departs from the original proposal. [ ] Update this line when the
leaky-split adapters have been deleted on Pegasus and the three re-runs have
completed.

## The problem

`finetune_llama.py:142` splits the training pool with:

```python
split = dataset.train_test_split(test_size=args.val_split, seed=42)
```

This splits at the individual **row** level, where one row = one (coder, country,
year, indicator) rating. But `assemble_prompt()` does not take `coder_id` — the
prompt for a given (country, year, indicator) cell is byte-identical regardless of
which coder rated it. With a mean of 8.4 coders per cell in the 2016–2018 pool, a
random 90/10 row split almost always splits a cell's coders across both sides: most
eval rows have several sibling rows, with the exact same input text, sitting in the
training set.

This gives the model an easy shortcut on eval: instead of inferring a rating from
document content, it can associate a specific (memorized) document with the majority
label its training-set siblings gave it. That's a materially easier task than
generalizing to a country-year-indicator the model has never seen anything about, and
it directly undermines the two things this internal validation set is used for —
`EarlyStoppingCallback` and `load_best_model_at_end` (`finetune_llama.py:236-256`).

## The exposure is near-universal, and the metric can't be trusted

Computed directly from `shared/vdem-data/human_ratings.csv`, restricted to the 206
indicators in `config/indicator_sections.yaml` and training years 2016–2018:

| Metric | Value |
|---|---|
| Coder-examples (config indicators, 2016–2018) | 897,643 |
| Cells with >1 coder | 97.6% |
| Multi-coder cells with actual disagreement | 91.2% |
| Mean rating spread on disagreeing cells (0–4 scale) | 2.83 |
| Weighted-average empirical entropy (nats **per rating**) | **0.858** (perplexity 2.36) |

With 97.6% of cells multi-coder, a random 90/10 row split places training-set
siblings (byte-identical prompt) next to nearly every eval row. Whatever eval_loss
then measures, it is not generalization to unseen cells — which is the only thing
early stopping and checkpoint selection are supposed to be optimizing.

**Caveat (2026-07-22, from the corrected runs' startup logs)**: the table above
describes the full 898K-row pool, but training actually runs on the ~100K-row
subsample (#59), which draws individual coder-rows at ~11% — so most cells
contribute only one or two of their ~8 coders. The realized `_sub` pool is 64,240
cells over ~99.7K rows (mean ~1.55 coders/cell), meaning only roughly half of
eval rows under the old row-level split would have had a byte-identical training
sibling, not "nearly every" one. The leak was real but less pervasive in the
actual training files than the full-pool numbers imply.

### Correction (2026-07-22): the "4x below the honest floor" claim was a units error

An earlier draft of this note argued the leak was *demonstrably* being exploited by
comparing the 0.858-nat coder-disagreement entropy against the observed eval_loss
plateau of 0.18–0.21 and calling the latter "4x below the honest floor." That
comparison is wrong: the 0.858 figure is **per rating**, while HF's eval_loss is
**per completion token**, averaged over the ~5–7 tokens of `{"rating": N}` — of
which only the rating digit carries real uncertainty. Converted to per-token units
the disagreement floor is roughly 0.12–0.17 nats, and the observed 0.18–0.21 is *at
or slightly above* it, not far below. (On why the disagreement entropy is the loss
floor at all — the training target is the conditional distribution of coder ratings,
not any individual rating — see `notes/finetune-training-target.md`.)

So the training logs are consistent with either an exploited shortcut or honest
near-floor performance — they neither prove nor rule out exploitation. The case for
the fix is the structural argument above plus cost asymmetry: the split was
indefensible in a preregistered design, no inference had been run, and re-running
cost ~45 GPU-hours total.

## What this does and doesn't affect

**Not at risk**: the primary confirmatory analysis. Per `docs/experimental-design.md`,
AI MAE vs. `panel_mean` runs on **2019**, which has zero row-level overlap with the
2016–2018 training pool — that comparison is a genuine temporal holdout regardless of
how the internal fine-tuning validation set was built.

**At risk**: checkpoint selection. `load_best_model_at_end` picked each variant's
archived adapter using the leaky metric, so the checkpoint that's actually about to be
evaluated on 2019 may not be the checkpoint that would generalize best. Because
leakage severity plausibly differs by condition — anonymization and summarization
change how "recognizable" a given cell's text is — this could introduce a differential
bias into the FT-raw vs. FT-anon vs. FT-summ comparison specifically, which is one of
the paper's central identification claims.

## Implemented fix (departs from the original proposal in three ways)

Group the split by CYI cell — `(country_text_id, iso3, year, indicator)`, deliberately
excluding `coder_id` — so all coders for one cell move together. This is available on
the `Dataset` before `to_prompt_completion` strips the ID columns. Implemented as
`grouped_cell_split()` in `pipeline/finetune_llama.py`.

The original draft proposed sklearn's `GroupShuffleSplit` with the downstream
`max_eval_examples` cap left unchanged. The implementation departs deliberately:

1. **Stdlib instead of sklearn.** The finetune conda env
   (`slurm/setup_finetune_env.sh`) does not install scikit-learn, and adding a
   dependency to a working aarch64 env for one function isn't worth it. The
   grouped split is ~20 lines of stdlib: collect row indices per cell key, sort
   the unique keys, shuffle with `random.Random(42)`, hold out the first
   `val_split` fraction of cells.

2. **The eval cap takes whole cells in shuffled order, not a row prefix.** The
   original code would have interacted badly with the untouched
   `eval_dataset.select(range(max_eval_examples))` cap. HF's `train_test_split`
   shuffles, so a row-prefix cap was previously a random draw — but
   `GroupShuffleSplit` returns row indices in ascending order, and the `_sub`
   files are in canonical case-ID sort order (`subsample_finetune_data.py`
   writes them that way for cross-variant step parity). The eval set would have
   come out alphabetical by country, and the first 500 rows would have been
   ~60 cells from Afghanistan through roughly Austria — early stopping and
   checkpoint selection driven by a handful of alphabetically-first countries.
   The implemented cap walks the held-out cells in shuffled order and takes
   whole cells until the row budget is reached: random, cell-complete, and —
   because the cell keys and seed are identical across the three `_sub` files —
   the same eval cells in all three variants. Held-out cells beyond the cap are
   excluded from training either way, so the cap never reintroduces leakage.

3. **Default `--max-eval-examples` raised 500 → 2000.** Leak-free eval rows in
   multi-coder cells are correlated observations of one prompt, so cell count,
   not row count, sets the independent sample size — and the same eval set
   drives `load_best_model_at_end`, where resolution matters most. Realized
   numbers from the corrected runs (jobs 73479339/73479345/73479346): the
   subsampled pool holds 64,240 cells at ~1.55 coders/cell, so 2,000 eval rows =
   1,282 independent cells (identical across variants; 6,424 cells — 10% — held
   out of training, eval capped at the first 1,282 in shuffled order). Eval cost
   is higher than the old help text suggested on the long-prompt variants
   (~20–40 min per 250-batch pass vs. ~4 min projected) but comfortably inside
   the wall limit at one eval per 100 training steps.

Cross-variant parity is preserved: the train split stays in canonical (ascending
file) order, so with the fixed `data_seed` every training step still processes the
same case at the same position in all three variants. Verified against the real
function with stubbed heavy deps: no cell on both sides of the split; eval cells
complete; identical case-ID sequences across variants; deterministic across calls;
eval spans ~140 countries rather than an alphabetical prefix.

Note `val_split` now targets cell count, not row count — with ~11K distinct CYI
cells in the pool, the realized eval-row fraction lands close to but not exactly
10%, which is fine.

## What not to do

Do not fix this by moving the internal validation set to 2019, 2022, or 2023:

- **2019** is pre-registered as "the clean one-year temporal holdout... with no
  exogenous anomalies" for the primary confirmatory analysis
  (`docs/experimental-design.md`). Using it for early-stopping/checkpoint selection
  during training — even without updating weights on it — is a form of validation-set
  reuse that breaks the clean-holdout guarantee the design is built on.
- **2023** is earmarked as a robustness check on the single best-performing model,
  run *after* the primary analysis picks a winner. Using it during training defeats
  that purpose.
- **2022** isn't part of the current design at all and would need independent
  justification to introduce.

The fix stays entirely inside the existing 2016–2018 training window — only which
specific rows land in the internal train/eval split changes.

## Disposition of the leaky-split runs (jobs 73473530–73473532)

All three adapters (scratch output dirs, checkpoints, and the
`~/panel-member-archive/adapters` copies) are deleted and the jobs resubmitted with
the grouped split before any inference is run. Deleting the checkpoints is load-bearing,
not just hygiene: `slurm/run_finetune.sh` auto-resumes from any checkpoint it finds in
the output dir, so a stale leaky-split checkpoint would silently poison the re-run.
**No fine-tuned model produced under the row-level split was ever used for inference,
and no evaluation metric was computed from any of them** — the only numbers ever read
off those runs are the training-log eval_loss curves quoted above. Before deletion, the
TensorBoard event logs for all three discarded runs (63K total — the evidence behind the
quoted eval_loss curves) were preserved on Pegasus at
`~/panel-member-archive/discarded-leaky-split-runs/{raw,anon,summ}-runs/`; the SLURM
stdout/stderr logs in `logs/finetune_734735*.{out,err}` also survive. Pull both into the
replication package alongside this note. The discarded runs
are disclosed as pilot/discarded work in the pre-registration (see
`docs/experimental-design.md`, Pilot work disclosure), not silently overwritten.

Each re-run is ~13–15h and already automated; catching this before 2019 inference
was far cheaper than discovering afterwards that early stopping promoted a
memorization-favoring adapter into the main results.

**Optional secondary check**: after the grouped-split re-run, a temporal internal
split (train 2016–2017, validate on all of 2018) would also be leak-free by
construction and is arguably a closer proxy for the eventual 2019 generalization test.
It costs roughly a third of the training pool, which cuts against the coverage
argument in `notes/finetuning-epochs.md` (rare indicator×level cells are "exactly
where the residual calibration risk sits") — worth running as a sensitivity check on
the early-stopping behavior, not as a replacement for the primary fix above.
