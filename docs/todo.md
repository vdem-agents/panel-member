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

- [x] **Generate `data/processed/panel_means.csv`** from V-Dem v15 coder-level data. **Done** — file exists at `shared/vdem-data/panel_means.csv`.

- [x] **Decide inference scope** (#3 — closed). **Training**: all indicators meeting
  filtering criteria and present in `config/indicator_sections.yaml` (~174 indicators,
  2013–2018). **Inference/evaluation**: proportional stratified sample of ~1/4 to 1/3 of
  retained indicators (~50–80), drawn proportionally across modules with floor of 2 per
  module, spanning all coverage tiers. Same evaluation set for all conditions and models.
  Exact list locked after section-mapping completion (#1).

- [x] **Populate section mappings in `config/indicator_sections.yaml`** (#1 — closed).
  All 206 retained indicators now have `state-dept` and `freedom-house` fields filled
  from `section-mapping-notes.md`. Excluded modules (`v2ed*`, `v2med*`, `v2reg*`) absent
  from YAML; `v2svstterr` excluded as interval scale (0–100). `v2dl*` and `v2exl*`
  (deliberation, executive legitimation) added to YAML; indicators with no section
  mapping use empty lists and will receive the default executive-summary evidence packet.
  `held_out` flag removed from all entries (design holdover). Script:
  `pipeline/populate_section_mappings.py`.

- [x] **Executive summary extraction for SD and FiW parsers** (#4 — closed 2026-07-11).
  Both parsers now capture the preamble as `exec_summary`: SD text before `Section 1.`,
  FiW text before `## A` (Overview + Key Developments). `extract_sections()` always
  prepends it; indicators with empty section mappings receive the exec summary alone
  as their baseline context block. No prompt-template changes needed.

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

- [ ] **Populate `data/fewshot_examples.json`** for all evaluation indicators (#8).
  Draw proportional stratified sample: one third of each module's indicators, floor of 2
  per module (~50–70 total). Write `pipeline/select_eval_indicators.py` (fixed seed) to
  produce `data/eval_indicators.txt`. For each selected indicator: 5 examples (one per
  ordinal level), globally distributed, drawn from 2013–2018 training window.
  Fields: `country`, `slug`, `country_name`, `year`, `level`, `raw_mean`, `region`.
  Evidence text loaded on-the-fly; only metadata here.
  **Blocked on**: source documents downloaded and ingested (#9).

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

- [x] **Revise or remove `held_out` flag in `config/indicator_sections.yaml`** (#2 — closed).
  Flag removed entirely from all YAML entries and from `generate_indicator_yaml.R`.
  Done as part of #1 resolution (2026-07-11).

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

## Source documents: download locally (do before any coding runs) (#9)

- [ ] **Download 2019 Freedom House and State Dept reports** (primary test year — do first).
  Run `bridge-coder/pipeline/download_reports.py --year 2019` on laptop. Lands in
  `shared/source-docs/{state-dept,freedom-house}/2019/`. ~170 countries, ~30 min.
  Then run `python3 -m pipeline.ingest --year 2019` to extract plain text.

- [ ] **Download 2013–2018 source documents** (fine-tuning training window).
  Same script, one run per year. ~6 × 30 min. Can chip away across sessions — the
  download script checkpoints so interrupted runs resume cleanly. Ingest each year
  after downloading.

- [ ] **Download 2022 source documents** (robustness check year; best model only).
  Run `download_reports.py --year 2022` on laptop. Ingest after downloading.

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

- [ ] **Revise paper framing artfully** (#7). `docs/overview.md` and `paper/outline.qmd`
  have been updated with a quick reframe (July 2026) to lead with the learning question
  and reposition V-Dem as the application. The current revision is intentionally rough —
  prose, section titles, and contribution claims need a careful pass before submission or
  pre-registration. Return to this after the pipeline is set up and the open design
  issues (#1–#6) are resolved.

- [ ] **Write `pipeline/select_cy_pool.py`**: filter `panel_means.csv` to 2019 rows
  with `n_coders ≥ 8` and save to `data/processed/cy_pool.csv`. No sampling, no cap —
  all eligible CYs from the evaluation pool. Run after Stage 1 to lock the pool.

- [ ] **Attrition sample**: identify countries with ≥8 coders in 2015 and ≤5 by 2022
  for the augmentation-of-attrited-panels secondary analysis.
