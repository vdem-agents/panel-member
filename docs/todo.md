# Panel Member: Outstanding Work

*Updated 2026-07-10. Items are roughly ordered by pipeline dependency.*

---

## GW Pegasus HPC setup (before any HPC runs)

- [x] **Confirm partition and GPU resource names** — done 2026-07-08.
  Pegasus now uses TRES scheduling (upgraded February 2026). Confirmed partition and
  GRES names via `sinfo` on login node log001. All `slurm/*.sh` scripts updated.
  See `notes/hpc-sequencing-strategy.md` for full details and TRES resource table.
  - Partitions: `cpu` (non-GPU), `gpu` (all GPU jobs), `basestar` (Grace Hopper)
  - GRES: `gpu:v100:1` (9B), `gpu:a100:1` (70B / fine-tuning), `gpu:a100:4` (405B)
  - TRES style: use `--cpus-per-gpu` and `--mem-per-gpu` for GPU jobs

- [x] **Claude API internet access confirmed** (July 2026).
  Outbound access to `api.anthropic.com` from Pegasus compute nodes is confirmed.
  Still: Claude requires no GPU and running it from the laptop avoids HPC queue
  latency. Run `run_coding_claude.sh` locally.

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

- [ ] **Copy `ingest.py` and `extract_sections.py` to Pegasus** (already copied locally on 2026-07-09;
  repeat after pushing to the remote or cloning fresh on Pegasus).

- [ ] **Test vLLM startup** with a small model (9B) before running full batches.
  Submit `slurm/run_coding_9b.sh` with `--indicators v2csreprss` and `--year 2020`
  on a handful of countries to confirm the vLLM health-check loop and batch runner
  work end-to-end before committing GPU time to 405B.

---

## Blocking: cannot run any coding until resolved

- [x] **Copy `ingest.py` and `extract_sections.py`** into `pipeline/` — done 2026-07-09.
  Copied from `bridge-coder/pipeline/`. Both pipelines may diverge (different section
  mappings), so independent copies are intentional. Update `PROCESSED_DIR` path constant
  if needed once ingestion is tested.

- [ ] **Generate `data/processed/panel_means.csv`** from V-Dem v15 coder-level data.
  Required columns: `country_text_id`, `year`, `indicator`, `raw_mean`, `n_coders`,
  `theta_quintile` (1–5 from v15 `v2x_polyarchy` quintiles).
  The `theta_quintile` column is used by `substitution_eval.py` for compression diagnostics
  and by the pool stratification. If not available, set to 0 (disables quintile analysis).
  **Date filter**: The coder-level dataset has two rows per coder-country-year (Jan 1 and
  Dec 31) as a structural feature. Filter to `format(historical_date, "%m-%d") == "12-31"`
  before computing means to get one rating per coder per year, matching V-Dem's published
  end-of-year values. Omitting this filter doubles the effective N without adding signal.

- [ ] **Decide inference scope and lock evaluation indicator set** (#3). Two options:
  25–30 selected indicators (3–4 per module, spanning coverage tiers) or all retained
  indicators (~170). See issue for tradeoffs. Once resolved, confirm section-mapping
  assignments before any inference runs.

- [ ] **Populate section mappings in `config/indicator_sections.yaml`** (#1). Fill
  `state-dept` and `freedom-house` fields for all retained indicators from
  `initial-exploration/explore-indicators/section-mapping-notes.md`. Remove excluded
  modules (`v2ed*`, `v2med*`, `v2reg*`). Codebook text is already generated; only
  section keys need to be added manually.

- [ ] **Decide on executive summary extraction for SD and FiW parsers** (#4). Both
  sources have substantive preamble blocks (SD executive summary; FiW Overview and Key
  Developments) currently discarded by the parser. Proposal: include as a baseline
  context block in every evidence packet. Affects `pipeline/extract_sections.py` and
  `pipeline/assemble_prompt.py`. Required before any evidence-condition coding runs.

- [ ] **Verify SD Section 2c content in 2013–2018 training window** (#5). In 2020
  reports, Section 2c universally redirects to the standalone IRFR with no inline text.
  Check whether pre-2020 reports contain inline text; if the redirect is consistent
  across years, consider ingesting the IRFR as a third source. Affects 9 indicators
  currently mapped to `2c`.

- [ ] **Decide on SD Section 6 / FiW G sub-parsing** (#6). Section 6 is an undivided
  narrative covering multiple sub-populations; including it in full may introduce
  cross-topic noise for indicators targeting a single group. Options: full inclusion,
  sub-parse by prose headers, or indicator-level sub-topic tagging. Try full inclusion
  first; revisit if pilot results show interference.

- [ ] **Expand `data/fewshot_examples.json`** to cover all evaluation indicators (exact
  set TBD pending #3). Current file covers: `v2csreprss`, `v2mecenefm`, `v2clkill`,
  `v2juncind`. Each indicator needs 5 examples (one per ordinal level 0–4), globally
  distributed, with fields: `country`, `slug`, `country_name`, `year`, `level`,
  `raw_mean`, `region`. Evidence text is loaded on-the-fly; only the metadata goes here.

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

- [ ] **Revise or remove `held_out` flag in `config/indicator_sections.yaml`** (#2).
  The flag currently marks indicators with <6 median coders (a criterion that has been
  dropped). Options: drop the flag entirely, repurpose it for coverage tier, or keep on
  `lg`/`sv`/`st` modules with updated rationale. Affects `prepare_finetune_data.py`
  training split only — does not suppress inference.

- [ ] **Generate `data/processed/human_ratings.csv`** from V-Dem v15 coder-level data in R.
  Required columns: `country_text_id`, `iso3`, `year`, `indicator`, `coder_id`, `rating`.
  Include both training indicators (2013–2018) and all evaluation indicators (including
  weak-coverage). Used by `prepare_finetune_data.py` (training) and `substitution_eval.py`
  (LOO MAE evaluation). The `iso3` column is required by `prepare_finetune_data.py` for
  anonymized text lookup.
  **Date filter**: filter to `format(historical_date, "%m-%d") == "12-31"` before
  exporting — the dataset has two rows per coder-country-year (Jan 1 + Dec 31) as a
  structural feature. Without this filter, `prepare_finetune_data.py` produces ~2× the
  training examples (~2–4M instead of ~1–2M), doubling fine-tuning time to ~20–36 A100
  hours with no benefit (duplicated identical prompts and ratings).

---

## Source documents: download locally (do before any coding runs)

- [ ] **Download 2019 Freedom House and State Dept reports** (primary test year).
  Run `bridge-coder/pipeline/download_reports.py --year 2019` on laptop. Store in
  `bridge-coder/data/raw/{state-dept,freedom-house}/2019/`. Symlink or copy to
  panel-member as needed. ~170 countries, ~30 min on home internet.

- [ ] **Download 2013–2018 source documents** (fine-tuning training window).
  Same script, one run per year. ~6 × 30 min. Can chip away across sessions — the
  download script checkpoints so interrupted runs resume cleanly.

- [ ] **Download 2022 source documents** (robustness check year; best model only).
  Run `download_reports.py --year 2022` on laptop.

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

- [ ] **Persona exploratory condition**: lock strict and lenient framing text; specify
  indicator subset (suggest: 4 high-observability indicators). Run on best fine-tuned
  model only. **Pre-registered as exploratory**: if persona shifts are reliable and
  directional, k=2/k=3 from persona draws becomes viable; if not, report null and close
  the question. Lock both the framing text and the indicator subset before running.

- [ ] **Temperature sensitivity**: lock the temperature=0.7 exploratory plan — which
  model, which indicators, full pool or subset — before running.

---

## Paper / analysis (non-blocking)

- [ ] **Write `pipeline/select_cy_pool.py`**: filter `panel_means.csv` to 2019 rows
  with `n_coders ≥ 8` and save to `data/processed/cy_pool.csv`. No sampling, no cap —
  all eligible CYs from the evaluation pool. Run after Stage 1 to lock the pool.

- [ ] **Attrition sample**: identify countries with ≥8 coders in 2015 and ≤5 by 2022
  for the augmentation-of-attrited-panels secondary analysis.
