# Implementation Strategy

Execution sequence for the panel-member pipeline. Organized by what can run now versus what is blocked, and by increasing infrastructure complexity.

---

## Status at a glance

| Condition / model | 2019 | 2023 | Blocker |
|---|---|---|---|
| `codebook` (all 5 models) | ✅ ready | ✅ ready | — |
| `evidence` (base models) | ✅ ready | ✅ ready | — |
| `anonymized` (base models) | ⛔ blocked | ⛔ blocked | #15 → #16 → anonymization batch |
| FT-raw training | ⛔ blocked | — | code gap in `prepare_finetune_data.py` + Pegasus |
| FT-raw inference (`evidence-zeroshot`, `anonymized-zeroshot`) | ⛔ blocked | ⛔ blocked | FT-raw adapter |
| FT-anon training | ⛔ blocked | — | anonymization batch (2016–2018) + Pegasus |
| FT-anon inference (`evidence-zeroshot`, `anonymized-zeroshot`) | ⛔ blocked | ⛔ blocked | FT-anon adapter |
| 2023 ablation (`evidence-zeroshot`, `anonymized-zeroshot`, best base model) | — | ⛔ blocked | 2023 anonymization batch |

Source documents confirmed available for 2016–2023 (`shared/processed-text/`). `fewshot_examples.json` covers all 206 indicators. `human_ratings.csv` present.

---

## Pre-flight (before first inference run)

**#21 — Review prompts.** Read `prompts/panel-member-coding-prompt.md` and the codebook-only system message in `assemble_prompt.py` before any runs. This is the only chance to catch structural issues before spending GPU hours.

**#18 — Fix HPC symlinks.** `data/processed-text/` uses relative symlinks that break when the job working directory differs from the project root. Must be resolved before submitting any Slurm job. Not a blocker for local runs.

---

## Phase 1 — Codebook and evidence conditions

**What runs:** `codebook`, `evidence`, `evidence-zeroshot` on all three base models (Llama 405B, 70B, 9B).

**Year:** 2019 primary. Run 2023 for the best-performing model only after Phase 1 results are reviewed.

**Command pattern:**
```bash
python3 -m pipeline.run_coding_batch \
    --year 2019 \
    --condition evidence \
    --model llama-70b \
    --indicators all
```

**Where results land:** `data/output/{model_key}_{condition}_{indicator}_2019.jsonl`

**Compute:** Codebook and evidence conditions are the cheapest runs. Run these first to establish the baseline and catch any prompt or output-parsing issues before scaling to all 206 indicators.

**Suggested order:**
1. Smoke test: 3–5 indicators, one model, one condition — verify output schema and no crashes
2. Codebook — all 206 indicators, all three models (fastest; no source-doc I/O)
3. Evidence — all 206 indicators, all three models
4. Evidence-zeroshot — all 206 indicators, best model (ablation; lower priority than 1–3)

---

## Phase 2 — Anonymization batch (prerequisite for everything downstream)

This is the rate-limiting step for the rest of the pipeline.

### Step 2a — Anonymize few-shot example countries (#15)

Run `anonymize_section.py` on every country that appears in `fewshot_examples.json`. The full set of affected (country, year, indicator) triples is in `data/fewshot_example_pool.json`. These must be done before building the anonymized few-shot file.

```bash
python3 -m pipeline.anonymize_section \
    --iso SWE --slug sweden --name Sweden \
    --year 2017 --indicators all
```

### Step 2b — Build fewshot_examples_anonymized.json (#16)

After Step 2a, compile the cached anonymized texts into `data/fewshot_examples_anonymized.json`. This file is parallel in structure to `fewshot_examples.json` but stores the anonymized text inline rather than a slug for on-the-fly retrieval.

### Step 2c — Anonymize 2019 eval pool

Run `run_anonymize_batch.py` for all countries × 206 indicators in 2019. This is the largest single batch in the pipeline — roughly ~160 countries × ~163 indicators with source docs, ~26,000 LLM calls total. Each call is fast but wall time is substantial.

```bash
python3 -m pipeline.run_anonymize_batch --year 2019
```

Already-cached files are skipped automatically, so runs are safe to interrupt and resume.

**Fix #18 (HPC symlinks) before submitting this as a Slurm job.**

---

## Phase 3 — Anonymized conditions

**Requires:** Phase 2 complete.

Run `anonymized` and `anonymized-zeroshot` on all three base models, 2019.

```bash
python3 -m pipeline.run_coding_batch \
    --year 2019 \
    --condition anonymized \
    --model llama-70b \
    --indicators all
```

At this point all six conditions have been run for the three base models. The evidence vs. anonymized comparison is available.

---

## Phase 4 — Fine-tuning

Two adapters are trained: **FT-raw** (on raw section text) and **FT-anon** (on anonymized text). They have different prerequisites and can proceed in parallel once their respective blockers are cleared.

### Track A — FT-raw

FT-raw does not require the anonymization batch. It can start after source documents and `human_ratings.csv` are confirmed available (i.e., after Phase 1 is underway).

**Blocker**: `prepare_finetune_data.py` currently only generates FT-anon training data. A `--raw` flag or equivalent needs to be added before this track can run. See open issue tracker.

**Step 4A-1 — Generate FT-raw training data** (once code gap is fixed):
```bash
python3 -m pipeline.prepare_finetune_data --raw
```
Pairs raw section text (2016–2018) with individual coder ratings. Writes `data/processed/finetune_train_raw.jsonl`.

**Step 4A-2 — Fine-tune on Pegasus**:
```bash
sbatch slurm/finetune_llama.sh --training-data finetune_train_raw.jsonl
```

**Step 4A-3 — Run FT-raw inference (2019)**:
```bash
python3 -m pipeline.run_finetuned_batch --year 2019 --adapter <ft-raw-path> \
    --conditions codebook evidence-zeroshot anonymized-zeroshot
```

### Track B — FT-anon

**Requires:** Phase 2 complete (anonymized text for 2016–2018).

**Step 4B-1 — Anonymize the training window**:
```bash
for year in 2016 2017 2018; do
    python3 -m pipeline.run_anonymize_batch --year $year
done
```

**Step 4B-2 — Generate FT-anon training data**:
```bash
python3 -m pipeline.prepare_finetune_data
```
Pairs anonymized section text (2016–2018) with coder ratings. Writes `data/processed/finetune_train_anon.jsonl`.

**Step 4B-3 — Fine-tune on Pegasus**:
```bash
sbatch slurm/finetune_llama.sh --training-data finetune_train_anon.jsonl
```
QLoRA on Llama-3.3-70B-Instruct. Estimated ~75–80 A100-hours each run. See `notes/hpc-execution-strategy.md` for partition names and GRES strings.

**Step 4B-4 — Run FT-anon inference (2019)**:
```bash
python3 -m pipeline.run_finetuned_batch --year 2019 --adapter <ft-anon-path> \
    --conditions codebook evidence-zeroshot anonymized-zeroshot
```

---

## Phase 5 — 2023 robustness check

**Requires:** Phase 1 results reviewed; best model identified.

Run the best-performing model across all conditions for 2023. Same sequence as Phases 1–4 but scoped to one model. The 2023 anonymization batch is the main time cost.

```bash
python3 -m pipeline.run_anonymize_batch --year 2023
python3 -m pipeline.run_coding_batch --year 2023 --condition evidence --model <best>
python3 -m pipeline.run_coding_batch --year 2023 --condition anonymized --model <best>
python3 -m pipeline.run_finetuned_batch --year 2023 --adapter <path>
```

---

## Phase 6 — Evaluation

**Requires:** All inference runs for the target year complete.

```bash
# Calibration check: MAD from panel mean, compression diagnostic
python3 -m pipeline.substitution_eval --year 2019

# Replacement experiment: divergence curve by k
python3 -m pipeline.replacement_experiment --year 2019
```

Results feed into `analysis/`. See `analysis/` for R scripts and output tables.

---

## Blocking dependency graph

```
#21 Review prompts ──────────────────────────────────────────────────────────────┐
#18 Fix HPC symlinks ──────────────────────┐                                     │
                                           │                                     ▼
                           ┌───────────────▼──────────────────── Phase 1 (codebook + evidence)
                           │                                              │
                           │                                              │ (source docs + HR available)
                           │                                              ▼
Fix code gap in            │                              Track A: FT-raw training data
prepare_finetune_data.py ──┼─────────────────────────────── → finetune_llama (Pegasus)
                           │                              → FT-raw inference (codebook,
                           │                                evidence-zeroshot, anonymized-zeroshot)
                           │
fewshot_examples.json      │
(done — Issue #8) ─────────┤
                           ▼
                      #15 Anonymize few-shot countries
                           │
                           ▼
                      #16 Build fewshot_examples_anonymized.json
                           │
                 ┌─────────┴──────────────┐
                 ▼                        ▼
    Anonymize 2019 eval pool       Anonymize 2016–2018
                 │                        │
                 ▼                        ▼
    Phase 3: anonymized           Track B: FT-anon training data
    conditions (2019)              → finetune_llama (Pegasus)
                 │                 → FT-anon inference (codebook,
                 │                   evidence-zeroshot, anonymized-zeroshot)
                 │                        │
                 └──────────┬─────────────┘
                            │
          [mirror for 2023 — best model only, includes 2023 anonymization batch]
                            │
                            ▼
                     Phase 6: Evaluation
```
