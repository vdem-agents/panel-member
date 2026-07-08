# Panel Member: Outstanding Work

*Updated 2026-07-08. Items are roughly ordered by pipeline dependency.*

---

## GW Pegasus HPC setup (before any HPC runs)

- [ ] **Confirm partition and GPU resource names** with GW research computing.
  The SLURM scripts in `slurm/` use placeholder names (`gpuq`, `compute`,
  `gpu:A100:1`, `gpu:V100:1`). Replace with Pegasus's actual partition and GRES
  names before submitting any jobs.

- [ ] **Check whether compute nodes have outbound internet access**.
  The Claude API (`api.anthropic.com`) requires outbound HTTPS from the node running
  the job. If compute nodes are firewalled, run `run_coding_claude.sh` from the login
  node instead. The JSONL checkpoint makes it safe to run interactively and resume.

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

## Blocking: cannot run replacement experiment until resolved

- [ ] **Lock `data/processed/cy_pool.csv`** (replacement experiment pool).
  Eligibility: ≥8 distinct coders, 2018–2022, stratified by `theta_quintile`
  (10 CYs per quintile = 50 total). Lock before running any LLM calls for the replacement
  experiment. Required columns: `country_text_id`, `year`, `indicator`, `theta_quintile`.

- [ ] **Generate `data/processed/human_ratings.csv`** — individual coder ratings from
  V-Dem v15 coder-level dataset. Required columns: `country_text_id`, `year`,
  `indicator`, `coder_id`, `rating`. Needed by `replacement_experiment.py`.

- [ ] **Update `MODEL_PRIORITY`** in `pipeline/replacement_experiment.py` after Stage 1
  calibration results are in. The priority list determines which models serve as AI panel
  members for k=2 and k=3 replacements. Must be pre-registered before running.

---

## Blocking: cannot run Condition 4 (fine-tuning) until resolved

- [ ] **Write `pipeline/prepare_finetune_data.py`**.
  Generates the training JSONL from (anonymized section text, raw panel mean) pairs.
  Training window: 2010–2015 (held out of all evaluation pools). Save list of training
  CYIs to `data/processed/training_set.csv` before training.

- [ ] **Write `pipeline/finetune_llama.py`**.
  QLoRA fine-tune on GW Pegasus A100 80GB. Base: `meta-llama/Llama-3.3-70B-Instruct`.
  Dependencies: `transformers`, `peft`, `bitsandbytes`, `trl`, `accelerate` (install
  in a separate conda env — see HPC setup section above).
  Hyperparameters to pre-register: LoRA rank, alpha, learning rate, batch size, epochs,
  base model commit hash.

- [ ] **Write `slurm/run_finetune.sh`**.
  SLURM script wrapping `finetune_llama.py`. Single A100 80GB node, ~2–4 hours per
  indicator. Same pattern as `run_coding_llama70b.sh` but no vLLM — training runs
  directly via `python3 -m pipeline.finetune_llama`.

- [ ] **Write `pipeline/run_finetuned_batch.py`**.
  Inference with fine-tuned weights served via local vLLM with LoRA adapter loaded
  via `--lora-modules`. Output schema same as other conditions with
  `condition="finetuned"`. Corresponding SLURM script: adapt `run_coding_llama70b.sh`
  with `--model llama-70b-finetuned` and the adapter path added to the vLLM launch.

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

- [ ] **Stopping rule**: document the k progression rule and whether you will report
  results beyond the tolerance threshold.

---

## Paper / analysis (non-blocking)

- [ ] **Write `pipeline/select_cy_pool.py`**: script to select the locked pool from
  v15 panel-size and θ data, applying eligibility criteria and quintile stratification.
  Makes the pool selection reproducible.

- [ ] **Attrition sample**: identify countries with ≥8 coders in 2015 and ≤5 by 2022
  for the augmentation-of-attrited-panels secondary analysis.

- [ ] **Temperature sensitivity**: plan the temperature=0.7 runs on best model.
  Decide whether to run on the full pool or a subset.
