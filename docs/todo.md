# Panel Member: Outstanding Work

*Updated 2026-07-21. Items are roughly ordered by pipeline dependency.*

**Status at pre-registration**: no blocking conditions remain. Anonymization, summarization,
and fine-tuning training-data preparation are complete for all years needed so far
(2016–2018, 2019, 2023). Fine-tuning (FT-raw, FT-anon, FT-summ) is in the
pipeline-testing / smoke-test stage — no adapter has been trained to completion. **No
inference or evaluation has been run** on any confirmatory condition, model, or year.
Llama 405B and 8B are dropped from the design outright (not contingently); an early,
unanalyzed two-condition (codebook, evidence) smoke test was run on Llama 8B to validate
pipeline mechanics only. See `docs/experimental-design.md` for the full reconciled design.

---

## GW Pegasus HPC setup (before any HPC runs)

- [x] **Confirm partition and GPU resource names** — done 2026-07-08.
  Pegasus now uses TRES scheduling (upgraded February 2026). Confirmed partition and
  GRES names via `sinfo` on login node log001. All `slurm/*.sh` scripts updated.
  See `notes/hpc-sequencing-strategy.md` for full details and TRES resource table.
  - Partitions: `cpu` (non-GPU), `gpu` (all GPU jobs), `basestar` (Grace Hopper)
  - GRES: `gpu:v100:1` (8B), `gpu:a100:1` (70B / fine-tuning), `gpu:a100:4` (405B)
  - TRES style: use `--cpus-per-gpu` and `--mem-per-gpu` for GPU jobs

- [ ] **Download model weights to Pegasus scratch storage** (run once on login node).
  Run `slurm/setup_models.sh` after setting `HF_TOKEN` in `.env`. Requires a
  HuggingFace account with Meta Llama access approved. Llama 3.3 70B (~140 GB) is the only
  model needed for the confirmatory design — base and all three fine-tuned variants
  (FT-raw, FT-anon, FT-summ) use the same weights. Llama 3.1 8B (~18 GB) was downloaded
  for the pipeline-validation smoke test only and is not otherwise part of the design.
  Llama 3.1 405B (~810 GB) is dropped from the design outright — do not download.

- [x] **Confirm scratch quota** is sufficient for model weights + output data.
  810 GB for 405B alone; 70B + 8B add another ~160 GB. Contact research computing
  if quota needs to be increased. (Can potentially run 405B on A100 node but it would be a long wait)

- [x] **Set up conda environments** on Pegasus:
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

- [x] **Copy `ingest.py` and `extract_sections.py` to Pegasus** (already copied locally on 2026-07-09;
  repeat after pushing to the remote or cloning fresh on Pegasus).

- [x] **Test vLLM startup** with a small model (8B) before running full batches.
  Submit `slurm/run_coding_8b.sh` with `--indicators v2csreprss` and `--year 2020`
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
  filtering criteria and present in `config/indicator_sections.yaml` (206 indicators,
  2016–2018). **Inference/evaluation**: full universe of ~205 mapped Type C indicators,
  unconditionally — no sampling fallback. The proportional-stratified-sample fallback
  (one third per module, floor of 2, ~60–70 total, fixed seed) originally pre-registered
  as a contingency for 405B not completing within 3 job submissions is retired: 405B is
  now dropped from the design outright, so there is no trigger condition left to key a
  fallback to. Same evaluation set for all conditions and models.
  See `notes/evaluation-indicator-scope.md` (rationale retained for the record).

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

- [x] **Verify SD Section 2c content in 2016–2018 training window** (#5 — closed 2026-07-13).
  Section 2c universally redirects to the IRFR with no inline text across all years
  (2016–2023, 915 files confirmed). IRFR executive summaries downloaded for all years
  2016–2023 (~194 countries/year) via `shared/pipeline/download_reports.py --source irfr`.
  PDF fallback added for countries without HTML exec summary (Colombia, Romania, Côte d'Ivoire,
  others). `extract_sections.py` now intercepts `2c` and loads `processed-text/irfr/{year}/{slug}.txt`
  instead; falls back to SD exec summary if IRFR file is missing. Affects 9 indicators mapped to `2c`.

- [x] **Decide on SD Section 6 / FiW G sub-parsing** (#6 — closed 2026-07-13).
  Section 6 sub-parsed by indicator target population via a year-aware prose-header
  parser. 20 of 33 Section 6 indicators now extract a targeted sub-section (Women,
  Minorities, Trafficking in Persons, or Other Societal Violence or Discrimination);
  13 cross-cutting indicators receive the full block. Minorities header is year-aware
  (changed 2020, again 2021). FH Section G is 2–6K chars and requires no sub-parsing.
  Sections 3, 4, 5 are short undivided narratives; Section 7 is already sub-keyed
  (7a–7e) and forced-labor indicators already reference 7b specifically. Implementation:
  sec6_subsections field in indicator_sections.yaml; _resolve_sec6_header() and
  _parse_sec6_subsection() in pipeline/extract_sections.py.

- [ ] **Populate `data/fewshot_examples.json`** for all evaluation indicators (#8).
  Covers all ~205 indicators in `config/indicator_sections.yaml`. For each indicator:
  5 examples (one per ordinal level), globally distributed, drawn from 2016–2018 training
  window. Fields: `country`, `slug`, `country_name`, `year`, `level`, `raw_mean`, `region`.
  Evidence text loaded on-the-fly; only metadata here. If the pre-registered fallback is
  triggered (see `notes/evaluation-indicator-scope.md`), write
  `pipeline/select_eval_indicators.py` (fixed seed) to produce `data/eval_indicators.txt`
  from the stratified sample before populating examples.
  **Blocked on**: source documents downloaded and ingested (#9).

---

## Condition 3 (anonymized) and Condition 4 (summarized) prerequisites — resolved

- [x] **Run `anonymize_section.py`** on all few-shot example countries before running
  any anonymized condition batches. The anonymized condition prompt uses anonymized
  few-shot examples as well as anonymized focal evidence.

- [x] **Build `data/fewshot_examples_anonymized.json`**.
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

- [x] **Run `summarize_indicator.py`** on all few-shot example countries before running
  any summarized condition batches, and run `run_summarize_batch.py` for the 2016–2018
  training window and the 2019/2023 evaluation pools. Unlike anonymization, summarization
  caches at the indicator level, not the section level (see `notes/summarization-strategy.md`).

- [x] **Build `data/fewshot_examples_summarized.json`** via `populate_fewshot_summarized.py`,
  parallel in structure to `fewshot_examples_anonymized.json` but storing summarized text.

- [x] **Anonymize and summarize the 2019 and 2023 evaluation pools.** Both batches are
  complete; no further ingestion is required before running the `anonymized` or
  `summarized` conditions on 2019 or 2023 data.

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

## Fine-tuning infrastructure — resolved
*(Note: this section predates the current condition numbering. "Condition 4" below refers
to the fine-tuning training-data-assembly shorthand, not the summarized condition —
which is Condition 4 in the reconciled 4-condition design; see `docs/experimental-design.md`.)*

- [x] **Write `pipeline/prepare_finetune_data.py`**. Done 2026-07-09; extended to a
  `--variant {raw,anon,summ}` flag and cross-variant stratified subsampling (issues #58, #59).
  Builds training JSONL from (evidence-variant prompt, individual coder rating) pairs.
  Training window 2016–2018. Outputs `finetune_train_{variant}.jsonl` and
  `training_set_{variant}.csv`.

- [x] **Write `pipeline/finetune_llama.py`**. Done 2026-07-09; retuned for early stopping
  and epoch extension over the shared ~100K subsample (see `notes/finetuning-epochs.md`).
  QLoRA fine-tune on Pegasus GH200/A100 80GB. Base: `meta-llama/Llama-3.3-70B-Instruct`.
  LoRA rank 16, alpha 32, lr 2e-4. Run once per variant (raw, anon, summ); currently in
  the pipeline-testing / smoke-test stage for all three, no adapter trained to completion.

- [x] **Write `slurm/run_finetune.sh`**. Done 2026-07-09.
  SLURM wrapper for `finetune_llama.py`. Single A100 80GB, ~3–5 hr wall-clock.
  Archives adapter to `$HOME/panel-member-archive/adapters/` on completion.

- [x] **Write `pipeline/run_finetuned_batch.py`**. Done 2026-07-09.
  Thin wrapper around `run_coding_batch.run_batch()` with fixed condition="finetuned-anon"
  and model="llama-70b-finetuned". Requires vLLM running with adapter via --lora-modules.

- [x] **Write `slurm/run_inference_finetuned.sh`**. Done 2026-07-09.
  Starts vLLM with `--lora-modules`, runs `run_finetuned_batch.py`, archives output.

- [x] **Revise or remove `held_out` flag in `config/indicator_sections.yaml`** (#2 — closed).
  Flag removed entirely from all YAML entries and from `generate_indicator_yaml.R`.
  Done as part of #1 resolution (2026-07-11).

- [x] **Generate `data/processed/human_ratings.csv`** from V-Dem v15 coder-level data in R.
  Required columns: `country_text_id`, `iso3`, `year`, `indicator`, `coder_id`, `rating`.
  Include both training indicators (2016–2018) and all evaluation indicators (including
  weak-coverage). Used by `prepare_finetune_data.py` (training) and `substitution_eval.py`
  (LOO MAE evaluation). The `iso3` column is required by `prepare_finetune_data.py` for
  anonymized text lookup.
  **Date filter**: filter to `format(historical_date, "%m-%d") == "12-31"` before
  exporting — the dataset has two rows per coder-country-year (Jan 1 + Dec 31) as a
  structural feature. Without this filter, `prepare_finetune_data.py` produces ~2× the
  training examples (~1.8M instead of ~898K), doubling fine-tuning time to ~20–36 A100
  hours with no benefit (duplicated identical prompts and ratings).

---

## Source documents: download locally (do before any coding runs) (#9)

- [x] **Download 2019 Freedom House and State Dept reports** (primary test year — do first).
  Run `bridge-coder/pipeline/download_reports.py --year 2019` on laptop. Lands in
  `shared/source-docs/{state-dept,freedom-house}/2019/`. ~170 countries, ~30 min.
  Then run `python3 -m pipeline.ingest --year 2019` to extract plain text.

- [x] **Download 2016–2018 source documents** (fine-tuning training window).
  Same script, one run per year. ~6 × 30 min. Can chip away across sessions — the
  download script checkpoints so interrupted runs resume cleanly. Ingest each year
  after downloading.

- [x] **Download 2023 source documents** (robustness check year; best model only).
  Already ingested and confirmed clean — all 16 SD sections in 193 files; all 7 FH
  sections in 210 files (confirmed via issue #14, closed 2026-07-12).

- [ ] **Download 2024 source documents** (temporal holdout on data outside the model's pretraining cutoff). Scope decided: **Freedom House only** — the 2024 State Department reports changed substantially in content and editorial mandate under a new administration, confounding a clean temporal comparison, while Freedom House maintained format and editorial continuity (see `docs/experimental-design.md`, "2024 Freedom-House-only temporal holdout"). Still need: download 2024 FH documents, confirm section mapping holds, and run a Freedom-House-only 2023 companion pass for a clean within-source comparison.  

---

## Infrastructure

- [x] **Add zero-shot prompt conditions to the pipeline** (#20 — closed 2026-07-14).
  `"evidence-zeroshot"`, `"anonymized-zeroshot"`, and (since extended to the summarized
  condition) `"summarized-zeroshot"` implemented in `assemble_prompt.py`: same
  text-loading path as their few-shot counterparts but `calibration_section = ""`.
  `CONDITIONS_ZEROSHOT` and `ALL_CONDITIONS` added to `vdem_config.py`. Validation and
  CLI choices updated in `assemble_prompt.py`, `code_country_year.py`, and
  `run_coding_batch.py`. No special-casing needed in the batch runner.
  **Still blocked on**: primary 4×4 results — do not run until the best-performing model
  is identified.

- [x] **Reconcile `vdem_config.py` model list with experimental design docs** (#19 — closed 2026-07-14).
  Removed `claude-sonnet` from `PRIMARY_MODELS`, `ALL_MODELS`, `MODEL_PRIORITY` in
  `replacement_experiment.py`, and all pipeline docstring examples. `claude-sonnet` entry
  also removed from `LLM_CONFIGS` entirely — anonymization uses Llama 70B, not Claude.
  Default model in `code_country_year.py` CLI updated to `llama-70b`.

- [x] **Audit country name harmonization between V-Dem and source-doc slugs** (#10 — closed 2026-07-14).
  Audited all slugs across 2016–2023. Found 7 hard failures and 3 wrong fuzzy matches:
  failures included both China multi-territory slug variants, `democratic-peoples-republic-of-korea`,
  `israel-and-the-occupied-territories`, `israel-golan-heights-west-bank-and-gaza`,
  `malaysia-2`, and `swaziland`; wrong matches were `niger` → Nigeria (should be NER),
  `republic-of-korea` → PRK North Korea (should be KOR), and `kosovo` → Serbia (should be XKX).
  All corrected. `SLUG_OVERRIDES` and `build_country_map()` consolidated into
  `pipeline/country_map.py`; duplicated code removed from both batch runners.

- [x] **Set up vLLM on GW Pegasus** for Llama 405B, 70B, 8B.
  - 405B: 8×A100 80GB node (needs ~200GB at 4-bit). May require allocation request.
  - 70B: single A100 80GB node (~35GB at 4-bit).
  - 8B: V100 16GB node (~5GB at 4-bit).
  Set `VLLM_BASE_URL` to the node's address; `VLLM_API_KEY` to any non-empty string
  if auth is disabled (typical for cluster jobs).

- [x] **Note on `v2juncind` vs `v2juhcind`**: bridge-coder's `config/indicator_sections.yaml`
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

## Documentation

- [x] **Add pipeline flow diagram to `docs/`** (#17). Mermaid diagram in
  `docs/pipeline-flow.md` showing inputs, outputs, and data flow across all pipeline
  stages and modules. Should cover ingest → section extraction (incl. 2c and Section 6
  sub-parsing) → prompt assembly (four conditions) → anonymization → coding →
  fine-tuning → evaluation. Include config and data file dependencies
  (`indicator_sections.yaml`, `fewshot_examples.json`, `panel_means.csv`,
  `human_ratings.csv`).

- [x] **Redo documentation to reflect third FT mode** (completed 2026-07-21). `docs/overview.md`,
  `docs/architecture.md`, and `docs/experimental-design.md` now describe the 4-condition
  (codebook, evidence, anonymized, summarized) / 4-model (70B base + FT-raw + FT-anon +
  FT-summ) design, the dropped 405B/8B scale comparison, and the restructured mechanism-test
  section (re-identification + name swap + information shift) and 2024 FH-only holdout from
  `notes/mechanism-test-design.md`. The earlier checked-off instance of this item (prior to
  2026-07-21) was inaccurate — the docs had not actually been updated at that time.

---

## Model runs

### Finetuning 

Finetune on State Department Human Rights Reports and Freedom House Freedom in the World reports for 2018-2019 using human coder ratings as the target variable.  

- [] **FT on raw packets** - Finetune Llama 3.3 Instruct 70B model on raw non-anomyzed evidence packets.  
- [] **FT on anonymized packets** - Finetune Llama 3.3 Instruct 70B model on anonymzed versions of evidence packets. 
- [] **FT on summarized sections** - Finetune Llama 3.3. Instruct 70B model on summarized evidence packets. 

### Inference on 2019 validation set

Run inference on four conditions for all four models: 1) codebook only; 2) raw evidence packets; 3) anonymized evidence packets; 4) summarized evidence packets. 405B and 8B are dropped from the design (see `docs/experimental-design.md`) — the only base model is 70B.

- [ ] **Inference on base 70B model** - Run inference on Llama 3.3 Instruct 70B base model, all four conditions.
- [ ] **Inference on FT-raw** - Run inference on Llama 3.3 Instruct 70B model finetuned on raw evidence packets.
- [ ] **Inference on FT-anonymized** - Run inference on Llama 3.3 Instruct 70B model finetuned on anonymized evidence packets.
- [ ] **Inference on FT-summarized** - Run inference on Llama 3.3 Instruct 70B model finetuned on summarized evidence packets.

### Robustness checks on 2023 data (with best model)

- [ ] **Test year replication** - Rerun experiment on 2023 test set across four conditions (codebook only, raw evidence, anonymized and summarized).
- [ ] **Few shot ablation** - Rerun inference for the raw evidence, anonymized and summarized versions of the best model without few shot examples.
- [ ] **Mechanism tests** - Unified section per `notes/mechanism-test-design.md`:
  - Re-identification test for the anonymized and summarized conditions (reuse test-year-replication inference results; only the follow-up identification prompt is new).
  - Name-swap test: transition-adjacent country-year paired with a stable same-regime-type neighbor, three-condition prompt structure (name+codebook, name+correct summary, name+swapped summary), stratified by re-identification status.
  - Information shift test: ERT-tagged transition-adjacent vs. stable country-years (reuse test-year-replication results).
- [ ] **Applied performance (agreement test)** - Compare MAE and directional bias of model codings versus human codings, all four conditions (can use test year replication results - no new inference required).

### 2024 Freedom-House-only temporal holdout

- [ ] **FH-only 2023 companion run** - Rerun best model, all four conditions, Freedom House sources only (needed for a clean within-source comparison against the 2024 run).
- [ ] **2024 out-of-sample run** - Run best model across all four conditions on 2024 FH-only data (outside Llama 3.3's pretraining cutoff). Report Δ(Evidence − Codebook) and Δ(Anonymized − Codebook) for 2023 FH-only vs. 2024 FH-only as the year-level information-shift result.

---

## Paper / analysis (non-blocking)

- [x] **Revise paper framing** (#7 — closed 2026-07-14). `docs/overview.md` now leads with
  the core decomposition question (what information — pretrained knowledge, structured
  source evidence, country identity — do LLMs draw on when coding political texts?) and
  positions V-Dem panel attrition as the application that makes the question consequential.
  The three-condition design is described as an identification strategy throughout.

- [ ] **Write `pipeline/select_cy_pool.py`**: filter `panel_means.csv` to 2019 rows
  with `n_coders ≥ 8` and save to `data/processed/cy_pool.csv`. No sampling, no cap —
  all eligible CYs from the evaluation pool. Run after Stage 1 to lock the pool.

- [ ] **Attrition sample**: identify countries with ≥8 coders in 2015 and ≤5 by 2022
  for the augmentation-of-attrited-panels secondary analysis.
