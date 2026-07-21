# Implementation Strategy

Execution sequence for the panel-member pipeline.

---

## Status at a glance

| Stage | Status |
|---|---|
| Source documents (2016–2024: State Dept, Freedom House, IRFR) | done |
| Anonymization batch (2016–2018 training window; 2019, 2023 eval pools) | done |
| Summarization batch (2016–2018 training window; 2019, 2023 eval pools) | done |
| Few-shot example files (raw, anonymized, summarized) | done |
| Fine-tuning training data (FT-raw, FT-anon, FT-summ variants) | done |
| Fine-tuning training runs (FT-raw, FT-anon, FT-summ) | **in progress** — pipeline-testing / smoke-test stage; no adapter trained to completion |
| Inference — any condition, any model, any year | **not started** |

No conditions are blocked. What was previously the rate-limiting step (the anonymization and summarization batches) is complete for the years needed so far. The remaining work is: (1) finish training the three adapters to completion, (2) run inference across all conditions/models/years, (3) evaluate. Because fine-tuning inputs (raw, anonymized, summarized 2016–2018 text) are already prepared, all three fine-tuning tracks can proceed in parallel with each other and with Phase 1 base-model inference below.

---

## Pre-flight (before the first confirmatory inference run)

**#21 — Review prompts.** Read `prompts/panel-member-coding-prompt.md` and the codebook-only system message in `assemble_prompt.py` before any confirmatory runs. This is the last chance to catch structural issues before spending GPU hours or crossing into confirmatory (rather than pipeline-validation) territory.

**#18 — Fix HPC symlinks.** `data/processed-text/` uses relative symlinks that break when the job working directory differs from the project root. Confirm resolved before submitting any Slurm job for a confirmatory run.

---

## Phase 1 — Primary conditions on the base model (2019)

**What runs:** `codebook`, `evidence`, `anonymized`, `summarized` on Llama 3.3 70B Instruct (base). This is the only base model in the design (see `docs/experimental-design.md` — 405B and 8B are dropped outright, not contingently included).

**Year:** 2019 primary. 2023 and 2024 runs happen later, in Phases 3–4, scoped to the best-performing model.

**Command pattern:**
```bash
python3 -m pipeline.run_coding_batch \
    --year 2019 \
    --condition evidence \
    --model llama-70b \
    --indicators all
```
Repeat with `--condition codebook`, `anonymized`, `summarized`.

**Where results land:** `data/output/{model_key}_{condition}_{indicator}_2019.jsonl`

**Compute:** codebook is the cheapest run (no source-doc I/O); evidence, anonymized, and summarized are comparable to each other. ~32,800 CYI cells per condition at the full ~205-indicator universe.

**Suggested order:**
1. Smoke test: 3–5 indicators, one condition — verify output schema and no crashes (distinct from, and in addition to, the earlier unanalyzed Llama 8B smoke test — this one is on the actual 70B model that will produce confirmatory results, so its output should be discarded, not folded into any analysis)
2. Codebook — all 206 indicators
3. Evidence — all 206 indicators
4. Anonymized — all 206 indicators
5. Summarized — all 206 indicators

---

## Phase 2 — Fine-tuning (FT-raw, FT-anon, FT-summ)

Three adapters are trained in parallel — FT-raw (raw evidence text), FT-anon (anonymized text), FT-summ (summarized text) — on a shared, indicator-stratified ~100K-case subsample of the ~898K-row 2016–2018 training pool, with early stopping on held-out validation loss (see `notes/finetuning-epochs.md`). Training data preparation and anonymization/summarization of the training window are complete for all three variants; what remains is running each training job to completion (current status: smoke-tested, not yet trained to completion).

**Step 2-1 — Fine-tune on Pegasus** (one job per variant):
```bash
sbatch slurm/finetune_llama.sh --training-data finetune_train_raw.jsonl
sbatch slurm/finetune_llama.sh --training-data finetune_train_anon.jsonl
sbatch slurm/finetune_llama.sh --training-data finetune_train_summ.jsonl
```
QLoRA (4-bit, rank 16, alpha 32) on `meta-llama/Llama-3.3-70B-Instruct`, GW Pegasus GH200/A100 80GB. See `notes/hpc-execution-strategy.md` and `notes/finetuning-epochs.md` for partition names, GRES strings, and the early-stopping protocol.

**Step 2-2 — Run inference for each adapter (2019)**:
```bash
python3 -m pipeline.run_finetuned_batch --year 2019 --adapter <ft-raw-path> \
    --conditions codebook evidence-zeroshot anonymized-zeroshot summarized-zeroshot
python3 -m pipeline.run_finetuned_batch --year 2019 --adapter <ft-anon-path> \
    --conditions codebook evidence-zeroshot anonymized-zeroshot summarized-zeroshot
python3 -m pipeline.run_finetuned_batch --year 2019 --adapter <ft-summ-path> \
    --conditions codebook evidence-zeroshot anonymized-zeroshot summarized-zeroshot
```

At this point all four primary conditions have been run for all four models (70B base + FT-raw + FT-anon + FT-summ) on 2019. The full primary 4×4 identification analysis is available.

---

## Phase 3 — 2023 robustness check

**Requires:** Phase 1 and 2 results reviewed; best-performing model identified.

Run the best-performing model across all four conditions for 2023 (test-year replication), then the three zero-shot ablation conditions (few-shot calibration ablation), then the mechanism-test battery (re-identification, name swap, information shift), then the agreement test.

```bash
python3 -m pipeline.run_coding_batch --year 2023 --condition evidence --model <best>
python3 -m pipeline.run_coding_batch --year 2023 --condition anonymized --model <best>
python3 -m pipeline.run_coding_batch --year 2023 --condition summarized --model <best>
python3 -m pipeline.run_finetuned_batch --year 2023 --adapter <path>   # if best model is an FT variant

# Few-shot ablation (best model only)
python3 -m pipeline.run_coding_batch --year 2023 --condition evidence-zeroshot --model <best>
python3 -m pipeline.run_coding_batch --year 2023 --condition anonymized-zeroshot --model <best>
python3 -m pipeline.run_coding_batch --year 2023 --condition summarized-zeroshot --model <best>
```

Mechanism tests (re-identification follow-up prompts, name-swap condition set, ERT-tagged information-shift stratification) are run against this same 2023 output plus the follow-up/swap-specific calls described in `docs/experimental-design.md` Part 2 and `notes/mechanism-test-design.md`.

---

## Phase 4 — 2024 Freedom-House-only temporal holdout

**Requires:** Phase 3 complete; best-performing model identified.

```bash
python3 -m pipeline.run_coding_batch --year 2023 --condition evidence --model <best> --sources freedom-house
python3 -m pipeline.run_coding_batch --year 2024 --condition evidence --model <best> --sources freedom-house
# ...repeat for codebook, anonymized, summarized
```

Both the 2023 FH-only companion run and the 2024 FH-only run are needed for a clean within-source comparison (see `docs/experimental-design.md`, "2024 Freedom-House-only temporal holdout"). This requires 2024 source documents to be downloaded and section-mapped for Freedom House (State Dept is out of scope for this check — see rationale in the experimental design doc).

---

## Phase 5 — Evaluation

**Requires:** All inference runs for the target year complete.

```bash
# Calibration check: AI MAE from panel mean, compression diagnostic
python3 -m pipeline.substitution_eval --year 2019

# Replacement experiment: k=1 divergence
python3 -m pipeline.replacement_experiment --year 2023
```

Results feed into `analysis/`. See `analysis/` for R scripts and output tables.

---

## Sequencing notes

- Phase 1 (base-model inference) and Phase 2 (fine-tuning) have no dependency on each other and should run concurrently — the anonymization and summarization batches both are already complete for all years needed.
- Phase 3 and Phase 4 both depend on identifying the best-performing model from Phases 1–2, so they cannot start until that model-selection step is done.
- Phase 4 has an additional, independent prerequisite: 2024 Freedom House source documents must be downloaded and mapped before its first command can run.
