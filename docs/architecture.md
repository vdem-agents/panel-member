# Panel Member: Pipeline Architecture

*Updated July 2026. IRT runner removed. Four prompt conditions (codebook-only, evidence
packets, anonymized summaries, fine-tuning). Anonymization agent added as Stage 2b.
Raw panel means replace calibration-weighted means. Fine-tuning covers all strong +
partial Type C indicators (~174); inference runs on 25–30 selected evaluation indicators.*

## Overview

```
PDFs (State Dept) + plain text (Freedom House)
    │
    ▼
[1] Ingestion: PDF → plain text
    │           shared with bridge-coder pipeline
    ▼
[2a] Section extraction: regex → indicator-relevant text (free, deterministic)
    │           config/indicator_sections.yaml (expanded to 12 indicators)
    │
    ├──────────────────────────────────────────────────────┐
    │                                                      │
    ▼                                                      ▼
[2b] (Conditions 3 & 4 only)                    (Conditions 1 & 2)
    Anonymization agent: LLM rewrites              Pass through
    extracted text, strips country identity
    │
    ▼
[3] Coding: prompt assembly → LLM → 0–4 ratings (JSONL)
    │   Condition 1: codebook-only (no source text)
    │   Condition 2: raw section text
    │   Condition 3: anonymized section text (few-shot)
    │   Condition 4: anonymized section text → fine-tuned Llama 70B
    ▼
[4] Calibration check: MAD from raw panel mean (primary calibration metric)
    ▼
[5] Replacement experiment: compare AI-augmented panel mean to full-panel mean
```

---

## Stage 1: Ingestion

**Shared with bridge-coder**. `pipeline/ingest.py` (symlink or copy from bridge-coder).

State Dept PDFs → plain text via PyPDF2. Freedom House plain text copied directly.
Output:
```
data/raw/
  state-dept/{year}/{country_code}.pdf
  freedom-house/{year}/{country_code}.txt

data/processed-text/
  state-dept/{year}/{country_code}.txt
  freedom-house/{year}/{country_code}.txt
```

If bridge-coder has already downloaded and processed a year, do not re-download.

---

## Stage 2a: Section Extraction

**Shared with bridge-coder**. `pipeline/extract_sections.py` + `config/indicator_sections.yaml`.

Regex parsing of document structure, pulling indicator-relevant sections. The YAML config
must be expanded from the 4-indicator bridge-coder version to cover all ~174 training
indicators and the ~25–30 evaluation indicators. Current confirmed section mappings for
the original 12 indicators (to be extended; lock before running):

```yaml
# High observability
v2clkill:    {state-dept: ["1a", "1b"], freedom-house: ["F"]}
v2cltort:    {state-dept: ["1c"],       freedom-house: ["F"]}
v2mecenefm:  {state-dept: ["2a"],       freedom-house: ["D"]}
v2csreprss:  {state-dept: ["2b", "5"],  freedom-house: ["E"]}
v2jupoatck:  {state-dept: ["1e"],       freedom-house: ["F"]}

# Medium observability
v2mecenefi:  {state-dept: ["2a"],       freedom-house: ["D"]}
v2juhcind:   {state-dept: ["1e"],       freedom-house: ["F"]}
v2clacfree:  {state-dept: ["2b"],       freedom-house: ["D"]}
v2clslavef:  {state-dept: ["7b"],       freedom-house: ["F"]}
v2psoppaut:  {state-dept: ["3"],        freedom-house: ["B"]}
v2excrptps:  {state-dept: ["4"],        freedom-house: ["C"]}

# Low observability
v2pepwrsoc:  {freedom-house: ["B"]}
```

Section mappings derived from `02-indicator-selection.html` (Section 8). Confirm against
the source map before locking.

---

## Stage 2b: Anonymization Agent

**New for panel-member**. `pipeline/anonymize_section.py`.

Used only for Conditions 3 and 4. Makes one LLM call that rewrites the extracted section
text to:
- Replace the country name with `[COUNTRY]`
- Replace named political parties, government bodies, and leaders with generic descriptions
  (e.g., "the ruling party", "the opposition", "senior officials")
- Paraphrase datable named events that would identify the country-year

Motivation: bridge-coder preliminary results show compression bias (AI ratings of
autocracies are systematically too high; democracies too low) even with few-shot
calibration examples. The hypothesis is that models are using country identity as a
regime-type anchor rather than reasoning from described conditions. Anonymization tests
this directly by comparing Conditions 2 and 3 on the same extracted text.

The anonymized text is saved separately so Conditions 2 and 3 can be compared on equal
footing:
```
data/processed-text/anonymized/{year}/{country_code}/{indicator}.txt
```

The few-shot examples used in Condition 3 should also be anonymized to keep the prompt
format consistent between training and evaluation.

---

## Stage 3: Coding

### Output schema (all conditions)

```json
{
  "country":       "HTI",
  "year":          2018,
  "indicator":     "v2csreprss",
  "model":         "claude-sonnet-4-6",
  "model_key":     "claude-sonnet",
  "condition":     "evidence",
  "rating":        1,
  "justification": "...",
  "raw_mean":      1.6,
  "signed_dev":   -0.6,
  "abs_dev":        0.6,
  "sources":       ["state-dept", "freedom-house"],
  "section_keys":  {"state-dept": ["2b", "5"], "freedom-house": ["E"]}
}
```

`condition` values: `"codebook"` | `"evidence"` | `"anonymized"` | `"finetuned"`

### Condition 1 — Codebook-only

Prompt: global comparative framing + codebook question text + response scale + output
instruction. No source text. Identical prompt across all four models. Measures the
latent calibration signal in pretraining data.

Output path: `data/output/{model_key}_codebook_{indicator}_{year}.jsonl`

### Condition 2 — Evidence packets

Prompt: global framing + codebook text + few-shot examples (one per ordinal level,
globally distributed) + raw section text + output instruction. Identical to
bridge-coder Stage 1 prompt. See `bridge-coder/docs/architecture.md` Stage 3.

Output path: `data/output/{model_key}_evidence_{indicator}_{year}.jsonl`

### Condition 3 — Anonymized summaries

Same structure as Condition 2 but with anonymized section text in place of raw section
text. Few-shot examples are also anonymized (same format throughout). The only difference
from Condition 2 is the input text.

Output path: `data/output/{model_key}_anonymized_{indicator}_{year}.jsonl`

### Condition 4 — Fine-tuning

**Training data** (`pipeline/prepare_finetune_data.py`):
```python
{
    "messages": [
        {"role": "system", "content": GLOBAL_FRAMING},
        {"role": "user",   "content": section_text},
        {"role": "assistant", "content": str(individual_coder_rating)}
    ]
}
```

One row per coder per country-year-indicator — individual coder ratings from the V-Dem
v15 coder-level dataset, not panel means. Training window: **2013–2018** (post-lateral-coder
drop; pre-attrition panels; no overlap with 2019 test year or 2024 deployment check).
Expected scale: ~6 years × ~150 CYs × ~174 indicators × ~11 coders ≈ ~1–2M training
examples (exact count pending data generation). The ~174 indicator count is derived from
the 2020 coder-level cross-section in `02-indicator-selection.qmd`; the actual count for
the 2013–2018 training window may differ if some indicators have sparse early-year
coverage. Save training CYI list to `data/processed/training_set.csv`.

**Evaluation design**:
- Primary: MAE/MSE/exact match against held-out individual coder ratings — standard
  supervised evaluation against the training target.
- Secondary: include fine-tuned model in cross-model MAD comparison alongside
  Conditions 1–3 — it outputs a 0–4 rating and slots directly into `substitution_eval.py`.
- Replacement experiment: participates as a model candidate alongside few-shot models.

**Fine-tuning** (`pipeline/finetune_llama.py`):
- Base: `meta-llama/Llama-3.3-70B-Instruct`
- Method: QLoRA (4-bit, rank 16, alpha 32)
- Platform: GW Pegasus A100 80GB, `--partition=gpu --gres=gpu:a100:1`
- Batch: 4; gradient accumulation: 4 (effective 16); epochs: 3
- Learning rate: 2e-4 with cosine decay
- Estimated time: joint training on ~174 indicators ≈ 10–18 A100-hours total
- Adapter size: ~500 MB–1 GB per indicator; base model weights (~140 GB) stored once

At inference: section text only — no few-shot examples. Calibration is in the weights.

Output path: `data/output/llama70b_finetuned_{indicator}_{year}.jsonl`

---

## Stage 4: Calibration Check

`pipeline/substitution_eval.py`

Computes MAD from raw panel mean per condition × model × indicator. Reports:
- MAD table: rows = condition × model combinations, columns = indicators
- Signed deviation by democracy quintile (compression diagnostic)
- Best condition × model for each indicator and overall

Identifies the best-performing combination to carry forward to Stage 5.

---

## Stage 5: Replacement Experiment

`pipeline/replacement_experiment.py`

```python
for cy in eval_pool:
    full_mean = raw_panel_mean(cy)          # from v15 coder-level data
    ai_ratings = best_condition_output[cy]  # list of AI ratings, one per model

    for k in [1, 2, 3]:
        divergences = []
        for b in range(B):
            removed = sample(human_coders[cy], k)
            human_subset = [r for r in human_ratings[cy] if r.coder_id not in removed]
            ai_subset = ai_ratings[:k]      # k models, one rating each
            aug_mean = mean(human_subset + ai_subset)
            divergences.append(abs(aug_mean - full_mean))
        record(cy, k, divergences)
```

For k > 1, AI ratings come from k distinct models (e.g., k=2: Claude + Llama 70B;
k=3: Claude + Llama 405B + Llama 70B). The assignment rule is pre-registered before
running.

Output: divergence curve by k (mean ± 95% CI), stratified by democracy quintile.

---

## Directory structure

```
panel-member/
  config/
    indicator_sections.yaml    # expanded to ~174 training + ~28 eval indicators; confirm mappings
  pipeline/
    ingest.py                  # symlink → bridge-coder/pipeline/ingest.py
    extract_sections.py        # symlink → bridge-coder/pipeline/extract_sections.py
    anonymize_section.py       # new: LLM call to strip country identity
    assemble_prompt.py         # condition-aware prompt assembly
    code_country_year.py       # single LLM coding call + output schema
    run_coding_batch.py        # batch runner for conditions 1–3
    prepare_finetune_data.py   # generate anonymized training JSONL for condition 4
    finetune_llama.py          # QLoRA training
    run_finetuned_batch.py     # inference with fine-tuned weights
    substitution_eval.py       # MAD from raw panel mean
    replacement_experiment.py  # panel mean divergence by k
    vdem_config.py             # model configs, paths, constants
  data/
    raw/                          # source documents (gitignored)
    processed-text/
      state-dept/{year}/
      freedom-house/{year}/
      anonymized/{year}/{iso}/    # per-indicator anonymized text
    processed/
      cy_pool.csv                 # locked replacement experiment pool
      training_set.csv            # fine-tuning pairs (held out)
      panel_means.csv             # raw panel means from v15 coder-level data
    output/                       # coded JSONL files (gitignored)
  notes/
    persona-prompting-design-archive.md
    hpc-sequencing-strategy.md     # Pegasus/Raptor setup, TRES resource requests, sequencing
```

**Shared files**: bridge-coder is the authoritative copy of source documents, ingest.py,
extract_sections.py, and any years already downloaded. Symlink rather than copy where
possible. The indicator_sections.yaml for panel-member is a superset of the bridge-coder
version and should be kept in sync.
