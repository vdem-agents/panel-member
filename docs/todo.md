# Panel Member: Outstanding Work

*Updated 2026-07-08. Items are roughly ordered by pipeline dependency.*

---

## GW Pegasus HPC setup (before any HPC runs)

- [x] **Confirm partition and GPU resource names** — done 2026-07-08.
  Pegasus now uses TRES scheduling (upgraded February 2026). Confirmed partition and
  GRES names via `sinfo` on login node log001. All `slurm/*.sh` scripts updated.
  See `notes/hpc-sequencing-strategy.md` for full details and TRES resource table.
  - Partitions: `cpu` (non-GPU), `gpu` (all GPU jobs), `basestar` (Grace Hopper)
  - GRES: `gpu:v100:1` (9B), `gpu:a100:1` (70B / fine-tuning), `gpu:a100:4` (405B)
  - TRES style: use `--cpus-per-gpu` and `--mem-per-gpu` for GPU jobs

- [ ] **Claude API jobs: run from laptop, not HPC**.
  Outbound internet access to `api.anthropic.com` from Pegasus compute nodes is
  unconfirmed. Claude requires no GPU and JSONL checkpointing makes it safe to run
  across sessions. Do not submit `run_coding_claude.sh` to Pegasus — run it locally.

- [ ] **Download model weights to Pegasus scratch storage** (run once on login node).
  Run `slurm/setup_models.sh` after setting `HF_TOKEN` in `.env`. Requires a
  HuggingFace account with Meta Llama access approved. Approximate sizes:
  - Llama 3.2 9B: ~18 GB
  - Llama 3.3 70B: ~140 GB
  - Llama 3.1 405B: ~810 GB (check scratch quota before downloading)

- [ ] **Confirm scratch quota** is sufficient for model weights + output data.
  810 GB for 405B alone; 70B + 9B add another ~160 GB. Contact research computing
  if quota needs to be increased.

- [ ] **Set up conda environments** on Pegasus:
  ```bash
  # Coding pipeline environment
  conda create -n panel-member python=3.11
  conda activate panel-member
  pip install -r requirements.txt

  # vLLM environment (separate due to CUDA/torch conflicts)
  conda create -n vllm python=3.11
  conda activate vllm
  pip install vllm
  ```

- [ ] **Create symlinks on Pegasus** (same as local, but in the Pegasus copy of the repo):
  ```bash
  cd panel-member/pipeline
  ln -s ../../bridge-coder/pipeline/ingest.py ingest.py
  ln -s ../../bridge-coder/pipeline/extract_sections.py extract_sections.py
  ```

- [ ] **Test vLLM startup** with a small model (9B) before running full batches.
  Submit `slurm/run_coding_9b.sh` with `--indicators v2csreprss` and `--year 2020`
  on a handful of countries to confirm the vLLM health-check loop and batch runner
  work end-to-end before committing GPU time to 405B.

---

## Blocking: cannot run any coding until resolved

- [ ] **Create symlinks** in `pipeline/`:
  ```bash
  cd panel-member/pipeline
  ln -s ../../bridge-coder/pipeline/ingest.py ingest.py
  ln -s ../../bridge-coder/pipeline/extract_sections.py extract_sections.py
  ```
  Both scripts look for `data/processed-text/` relative to their own parent directory,
  so the symlink approach requires the panel-member processed-text dir to mirror
  bridge-coder's. Alternatively, copy and update the `PROCESSED_DIR` path constant.

- [ ] **Generate `data/processed/panel_means.csv`** from V-Dem v15 coder-level data.
  Required columns: `country_text_id`, `year`, `indicator`, `raw_mean`, `n_coders`,
  `theta_quintile` (1–5 from v15 `v2x_polyarchy` quintiles).
  The `theta_quintile` column is used by `calibration_check.py` for compression diagnostics
  and by the pool stratification. If not available, set to 0 (disables quintile analysis).

- [ ] **Expand `data/fewshot_examples.json`** from 4 indicators to all 12.
  Current file (from bridge-coder) covers: `v2csreprss`, `v2mecenefm`, `v2clkill`,
  `v2juncind`. Need to add: `v2cltort`, `v2jupoatck`, `v2mecenefi`, `v2juhcind`,
  `v2clacfree`, `v2clslavef`, `v2psoppaut`, `v2excrptps`, `v2pepwrsoc`.
  Each indicator needs 5 examples (one per ordinal level 0–4), globally distributed,
  with fields: `country`, `slug`, `country_name`, `year`, `level`, `raw_mean`, `region`.
  The evidence text is loaded on-the-fly by `assemble_prompt.py`; only the metadata
  needs to be in the JSON.

- [ ] **Verify codebook text for 8 new indicators** in `config/indicator_sections.yaml`.
  The entries for `v2cltort`, `v2jupoatck`, `v2mecenefi`, `v2juhcind`, `v2clacfree`,
  `v2clslavef`, `v2psoppaut`, `v2excrptps`, `v2pepwrsoc` contain approximate text
  marked `# TODO`. Verify against the V-Dem codebook (vdemdata::codebook in R or the
  PDF codebook) before running any coding — incorrect codebook text goes directly into
  the prompt and degrades output quality.

- [ ] **Confirm section mappings for all 12 indicators** against
  `initial-exploration/explore-indicators/02-indicator-source-map.html`.
  The YAML section keys were derived from `02-indicator-selection.html` but should be
  cross-checked against the source map, particularly for indicators that span multiple
  sections (e.g., `v2jupoatck` maps to 1e in State Dept — verify this covers government
  attacks on the judiciary, not just fair trial denials).

---

## Blocking: cannot run Condition 3 (anonymized) until resolved

- [ ] **Run `anonymize_section.py`** on all few-shot example countries before running
  any anonymized condition batches. The anonymized condition prompt uses anonymized
  few-shot examples as well as anonymized focal evidence.

- [ ] **Build `data/fewshot_examples_anonymized.json`**.
  After running anonymize_section.py on the few-shot example countries, compile the
  anonymized text into a JSON file parallel to `fewshot_examples.json`. Expected format:
  ```json
  {
    "v2csreprss": [
      {"level": 0, "raw_mean": 0.1, "anonymized_text": "..."},
      ...
    ]
  }
  ```
  Note: anonymized examples do not include `country`, `slug`, or `country_name` fields
  (that is the point). The text is the full combined anonymized evidence from both sources.

---

## Blocking: cannot run generalization test until resolved

- [ ] **Finalize and lock hold-out indicators** (verify before any fine-tuning runs).
  Candidates — v2clrelig, v2meharjrn, v2cseeorgs, v2jucorrdc — are now in
  `config/indicator_sections.yaml` with `held_out: true` and approximate codebook text,
  but all four are marked `# TODO: verify`. Before locking:
  - Confirm indicator codes exist in V-Dem v15 (check `vdemdata::codebook` in R)
  - Verify codebook question wording, clarification text, and response categories
    against the official PDF or `vdemdata::codebook`
  - Confirm State Dept and Freedom House section mappings against
    `initial-exploration/explore-indicators/02-indicator-source-map.html`
  - Decide whether all four are kept or whether any are dropped (e.g. if section
    coverage is poor or the indicator is retired in v15)

- [ ] **Generate `data/processed/human_ratings.csv`** — individual coder ratings from
  V-Dem v15 coder-level dataset for both trained and held-out indicators.
  Required columns: `country_text_id`, `year`, `indicator`, `coder_id`, `rating`.
  Used for MAE evaluation of fine-tuned model on both indicator sets.

---

## Secondary analysis: integration robustness (k=1 replacement check)

Previously the primary experiment; now a supplemental robustness check. Simplified
to k=1 only — k=2 and k=3 dropped since a single fine-tuned adapter cannot provide
multiple genuinely distinct AI coders.

- [ ] **Lock `data/processed/cy_pool.csv`** after Stage 1 calibration results are in.
  Eligibility: ≥8 distinct coders, 2019 only (same year as calibration — AI ratings
  already exist; no extra ingestion or coding needed). Use all eligible CYs, no cap.
  Run `pipeline/select_cy_pool.py` to generate the file reproducibly.

- [ ] **Simplify `pipeline/replacement_experiment.py`** to k=1 only.
  Remove k=2, k=3 logic and the MODEL_PRIORITY assignment. Single AI rating from
  best-calibrated model per bootstrap draw.

---

## Blocking: cannot run Condition 4 (fine-tuning) until resolved

- [x] **Write `pipeline/prepare_finetune_data.py`**. Done 2026-07-09.
  Builds training JSONL from (Condition 4 prompt, individual coder rating) pairs.
  Training window 2013–2018. Outputs `finetune_train.jsonl` and `training_set.csv`.

- [x] **Write `pipeline/finetune_llama.py`**. Done 2026-07-09.
  QLoRA fine-tune on Pegasus A100 80GB. Base: `meta-llama/Llama-3.3-70B-Instruct`.
  LoRA rank 16, alpha 32, lr 2e-4, batch 4 × grad_accum 4, 3 epochs.
  Saves adapter only to `data/output/adapters/llama-70b-vdem-ft/`.

- [x] **Write `slurm/run_finetune.sh`**. Done 2026-07-09.
  SLURM wrapper for `finetune_llama.py`. Single A100 80GB, ~3–5 hr wall-clock.
  Archives adapter to `$HOME/panel-member-archive/adapters/` on completion.

- [x] **Write `pipeline/run_finetuned_batch.py`**. Done 2026-07-09.
  Thin wrapper around `run_coding_batch.run_batch()` with fixed condition="finetuned"
  and model="llama-70b-finetuned". Requires vLLM running with adapter via --lora-modules.

- [x] **Write `slurm/run_inference_finetuned.sh`**. Done 2026-07-09.
  Starts vLLM with `--lora-modules`, runs `run_finetuned_batch.py`, archives output.

- [ ] **Generate `data/processed/human_ratings.csv`** from V-Dem v15 coder-level data in R.
  Required columns: `country_text_id`, `iso3`, `year`, `indicator`, `coder_id`, `rating`.
  Include both training indicators (2013–2018) and held-out indicators (for MAE eval).
  The `iso3` column is required by `prepare_finetune_data.py` for anonymized text lookup.

---

## Source documents: download locally (do before any coding runs)

- [ ] **Download 2019 Freedom House and State Dept reports** (primary test year).
  Run `bridge-coder/pipeline/download_reports.py --year 2019` on laptop. Store in
  `bridge-coder/data/raw/{state-dept,freedom-house}/2019/`. Symlink or copy to
  panel-member as needed. ~170 countries, ~30 min on home internet.

- [ ] **Download 2013–2018 source documents** (fine-tuning training window).
  Same script, one run per year. ~6 × 30 min. Can chip away across sessions — the
  download script checkpoints so interrupted runs resume cleanly.

- [ ] **Download 2024 source documents** (deployment robustness check, best model only).
  Run `download_reports.py --year 2024`. Note: State Dept 2024 report (covering 2024
  events) was published early 2025; confirm URL pattern still holds.

---

## Infrastructure

- [ ] **Set up vLLM on GW Pegasus** for Llama 405B, 70B, 9B.
  - 405B: 8×A100 80GB node (needs ~200GB at 4-bit). May require allocation request.
  - 70B: single A100 80GB node (~35GB at 4-bit).
  - 9B: V100 16GB node (~5GB at 4-bit).
  Set `VLLM_BASE_URL` to the node's address; `VLLM_API_KEY` to any non-empty string
  if auth is disabled (typical for cluster jobs).

- [ ] **Note on `v2juncind` vs `v2juhcind`**: bridge-coder's `config/indicator_sections.yaml`
  uses `v2juncind` with "High court independence" as description, which appears to be a
  typo for `v2juhcind`. Panel-member uses `v2juhcind`. Verify which code is correct in
  V-Dem v15 before running bridge-coder Stage 2.

---

## Pre-registration (before running replacement experiment)

- [ ] **Divergence threshold**: choose and justify the value (in raw rating points on 0–4
  scale) above which the 95% CI lower bound triggers "replacement tolerance exceeded."
  Document in a pre-registration file.

- [ ] **Persona exploratory condition**: write strict and lenient framing text; decide
  which indicators and models to test; lock before running.

- [ ] **Divergence threshold**: choose and justify the value (in rating points on 0–4
  scale) at which the 95% CI lower bound would indicate non-negligible panel distortion.

- [ ] **Stopping rule and k progression**: document the rule for reporting results at
  k=2 and k=3 (contingent on exploratory temperature/persona results producing
  genuinely distinct AI draws). What k triggers "replacement tolerance exceeded" and
  do you report results beyond that point?

- [ ] **Coder removal sensitivity**: random removal is primary; decide whether to
  report worst-first and best-first bounds as supplementary robustness checks.

---

## Paper / analysis (non-blocking)

- [ ] **Write `pipeline/select_cy_pool.py`**: filter `panel_means.csv` to 2019 rows
  with `n_coders ≥ 8` and save to `data/processed/cy_pool.csv`. No sampling, no cap —
  all eligible CYs from the calibration pool. Run after Stage 1 to lock the pool.

- [ ] **Attrition sample**: identify countries with ≥8 coders in 2015 and ≤5 by 2022
  for the augmentation-of-attrited-panels secondary analysis.

- [ ] **Temperature sensitivity**: plan the temperature=0.7 runs on best model.
  Decide whether to run on the full pool or a subset.
