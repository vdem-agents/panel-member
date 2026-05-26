# Panel Member: Pipeline Architecture

## Overview

The pipeline has four stages: ingest, retrieve, code, analyze. The IRT runner (Stage 2+)
is a fifth stage that takes coded output and tests it against the V-Dem measurement model.

```
PDFs (State Dept + Freedom House)
    │
    ▼
[1] Ingestion: PDF extraction → plain text (per country-year)
    │
    ▼
[2] Retrieval: ChromaDB per-country index → fixed-budget evidence packets
    │
    ▼
[3] Coding: factorial design matrix → persona config → prompt assembly → LLM API → output
    │
    ▼
[4] Analysis: regression of deviation on attribute indicators (Stage 1 results)
    │
    ▼
[5] IRT runner: simplified Stan model → θ_aug vs. θ_full trajectory (Stage 2)
```

---

## Stage 1: Ingestion

**Reuse from existing pipeline**: `extract_reports_for_graphrag.py` in
`initial-exploration/V-Dem-agentic-pipeline/`. Copy to `pipeline/ingest.py`.

The extraction step is identical between this repo and `bridge-coder`. If you maintain both
repos, keep the extraction scripts in sync or extract to a shared utility.

**Output structure**:
```
data/raw/
  state-dept/{year}/{country_code}.pdf
  freedom-house/{year}/{country_code}.pdf

data/processed/
  text/
    state-dept/{year}/{country_code}.txt
    freedom-house/{year}/{country_code}.txt
```

**Priority years**: 2010–2022 for Stage 1 (factorial experiment pool). 1977–2009 for
Stage 3 historical deployment.

---

## Stage 2: Retrieval (ChromaDB vector RAG, per-country)

### Why vector RAG, not GraphRAG

The panel member simulates a country expert reasoning from a country-specific information
environment. Standard vector RAG — retrieving the most relevant chunks from the target
country's own documents — directly instantiates this local information frame.

GraphRAG's cross-country reasoning would confound the Panel Member experiment: if the model
is reasoning laterally across countries, it is approximating a bridge coder, not a local
expert. Paper 1's Stage 1 is testing what attributes make the AI behave like a local
expert; cross-national retrieval would contaminate that measurement.

(The bridge-coder repo uses GraphRAG with global query mode for the opposite reason.)

### Index construction

Build **one ChromaDB collection per country**, containing all years' chunks for that
country. Query by year at retrieval time via metadata filter.

```python
import chromadb
from chromadb.utils import embedding_functions

client = chromadb.PersistentClient(path="data/chromadb/")
embed_fn = embedding_functions.SentenceTransformerEmbeddingFunction(
    model_name="BAAI/bge-large-en-v1.5"
)

# Index one country
collection = client.get_or_create_collection(
    name=f"vdem_{country_code}",
    embedding_function=embed_fn
)

# Chunk and add documents
for chunk, metadata in chunks_with_metadata:
    collection.add(
        documents=[chunk],
        metadatas=[{"country": country_code, "year": year, "source": source}],
        ids=[f"{country_code}_{year}_{source}_{chunk_idx}"]
    )
```

**Chunking**: fixed-length chunks of 400–500 tokens with ~50-token overlap. This chunk
size is small enough to be topically coherent and large enough to carry meaningful context.
Use the same chunker for State Dept and Freedom House so chunks are comparable across
sources.

### Query construction

Indicator-specific queries from codebook text:

```python
def build_retrieval_query(indicator_code, codebook_question, key_terms):
    return f"{codebook_question} {' '.join(key_terms)}"

# Example for v2csreprss:
# "Does the government attempt to repress civil society organizations?
#  repression harassment arrests NGO restrictions"
```

### Packet assembly and standardization

```python
def retrieve_packet(country_code, year, query, n_chunks=3):
    collection = client.get_collection(f"vdem_{country_code}")
    results = collection.query(
        query_texts=[query],
        n_results=n_chunks,
        where={"year": {"$eq": year}}
    )
    return "\n\n".join(results["documents"][0])
```

**Packet richness levels** (Stage 1 attribute):

| Level | n_chunks | Sources |
|---|---|---|
| Full | 5 (3 State Dept + 2 Freedom House) | Both |
| Partial | 3 (State Dept only) | State Dept |
| Minimal | 1 (State Dept only) | State Dept |

Chunk count is fixed per level so token budget is approximately constant. Do not use a
token budget truncation here (unlike the bridge-coder pipeline) — varying chunk count IS
the packet richness manipulation; truncation would collapse the levels.

---

## Stage 3: Coding (Factorial Experiment)

### Design matrix generation

Generate the fractional factorial design matrix in R before running any LLM calls.

```r
library(AlgDesign)

# Define attribute levels
factors <- list(
  threshold    = c("strict", "neutral", "lenient"),
  reliability  = c("high", "medium", "low"),
  conception   = c("liberal", "majoritarian", "participatory", "deliberative"),
  domestic     = c("yes", "no"),
  diligence    = c("high", "standard"),
  packet       = c("full", "partial", "minimal"),
  source       = c("state_dept", "state_and_fh")
)

# Generate D-optimal fractional factorial, main effects only
design <- optFederov(
  ~ threshold + reliability + conception + domestic + diligence + packet + source,
  data    = expand.grid(factors),
  nTrials = 48,
  criterion = "D"
)

# If pre-specifying source × domestic interaction:
# nTrials = 64, add the interaction term to the formula
```

Save the design matrix to `data/processed/design_matrix.csv` before running. This is
the pre-registration artifact — lock it before touching the LLM.

### Configuration → prompt mapping

Each row in the design matrix is one configuration. The coding runner iterates over
configurations × country-years:

```python
for config_id, config in design_matrix.iterrows():
    for country, year in country_year_pool:
        persona_block     = build_persona_block(config)
        calibration_block = build_calibration_block(config)
        evidence          = retrieve_packet(country, year, query,
                                            n_chunks=PACKET_LEVELS[config["packet"]])
        prompt = assemble_prompt(
            persona_block, calibration_block,
            codebook_text, evidence
        )
        rating = call_llm(prompt)
        save_output(config_id, country, year, rating)
```

### Prompt assembly

See `prompts/panel-member-prompt-v1.md` for the full template. Components in order:

1. **Persona block**: threshold tendency + reliability instruction (from config)
2. **Calibration block**: synthetic vignette example if applicable (from config)
3. **Democracy conception block**: framing sentence (from config)
4. **Domestic/foreign framing**: (from config)
5. **Coding instruction**: indicator name, codebook question, ordinal descriptions verbatim
6. **Evidence block**: ChromaDB packet at the configured richness level
7. **Output instruction**: integer 0–4 + one-sentence justification

**No temporal context injection**: do not provide the previous year's V-Dem estimate.
Within Stage 1, each call should be independent of prior year ratings to avoid anchoring
effects that would confound the attribute estimates.

### LLM API layer

Same OpenAI-compatible abstraction as bridge-coder:

```python
LLM_CONFIG = {
    "base_url": "https://api.anthropic.com/v1",
    "model":    "claude-sonnet-4-6",
    "api_key":  os.environ["ANTHROPIC_API_KEY"],
}
```

Swap base URL and model name for Together.ai (Llama 3.3 70B) or Pegasus vLLM replication.

### Output schema

```json
{
  "config_id":    12,
  "country":      "HTI",
  "year":         2015,
  "indicator":    "v2csreprss",
  "model":        "claude-sonnet-4-6",
  "threshold":    "strict",
  "reliability":  "high",
  "conception":   "liberal",
  "domestic":     "yes",
  "diligence":    "high",
  "packet":       "full",
  "source":       "state_dept",
  "rating":       1,
  "justification": "...",
  "human_panel_mean": 1.8,
  "signed_deviation": -0.8,
  "abs_deviation": 0.8
}
```

Store as JSONL. Human panel means are joined from `data/processed/vdem_panel_means.csv`
(precomputed from v15 coder-level data).

---

## Stage 4: Analysis (Stage 1 results)

### Script: `pipeline/analyze_stage1.R`

```r
library(tidyverse)
library(fixest)  # or lm_robust from estimatr

results <- read_jsonl("data/processed/stage1_ratings.jsonl")

# Signed deviation model (directional attributes)
signed_model <- feols(
  signed_deviation ~ threshold + domestic + conception | country_year,
  data    = results,
  cluster = ~country_year
)

# Absolute deviation model (precision attributes)
abs_model <- feols(
  abs_deviation ~ reliability + diligence + packet | country_year,
  data    = results,
  cluster = ~country_year
)
```

Country-year fixed effects are included at no power cost since the same N_cy pool is
used across all 48 configurations (complete matrix design).

**Preregistration**: the regression specification, directional predictions, and
progression rule must be locked in `docs/preregistration.md` before running any LLM calls.

---

## Stage 5: IRT Runner (Stages 2–3)

### Architecture

Same three-script Stan chain as the bridge-coder repo. The data contract and Stan model
(`quasilda4.stan`) are identical. The difference is in how AI coder rows are appended:

- **Bridge-coder**: AI rows add a single globally-calibrated coder appearing in every
  country's panel
- **Panel-member**: AI rows add k persona-specified coders to selected thin panels,
  replacing k removed human coders

### Sequential replacement script: `pipeline/irt/sequential_replacement.R`

```r
# For each replacement step k = 1, 2, ..., K:
#   1. Remove k human coders from the target panel
#   2. Load AI ratings for the same country-years (from Stage 3 coding output)
#   3. Append AI rows with synthetic coder IDs
#   4. Build mm input and run Stan
#   5. Record ||θ_aug_k − θ_full||

replacement_curve <- map_dfr(1:K, function(k) {
  panel_k <- drop_k_coders(full_panel, k)
  ai_rows  <- load_ai_ratings(country, years, best_config_id)
  augmented <- bind_rows(panel_k, ai_rows)
  theta_aug <- run_mm(augmented, variable)
  tibble(k = k, divergence = norm(theta_aug - theta_full))
})
```

### Persona matching for Stage 2

Use Stage 1 results to select the best-performing configuration (lowest absolute deviation,
correct sign in signed deviation). Draw β_r and γ_{r,k} from V-Dem CurateND posteriors
to match the AI persona profile to the profile of the human coder being replaced.

CurateND posteriors: download from the V-Dem CurateND archive (linked in Pemstein et al.,
WP21, 2025). Link to coder IDs via `coder_id` in the v15 coder-level dataset.

---

## What to import from `initial-exploration`

| Component | Source | Action |
|---|---|---|
| PDF extraction | `V-Dem-agentic-pipeline/extract_reports_for_graphrag.py` | Copy to `pipeline/ingest.py` |
| Data loader | Magid-Branch `vdem_data_loader.py` | `git show origin/Magid-Branch:"V-Dem agentic pipeline/vdem_data_loader.py"` |
| IRT sandbox | Magid-Branch `stage2_irt_sandbox.py` | Reference only; rebuild properly in R using Stan plan |
| LangGraph pipeline | Magid-Branch `langgraph_coding_pipeline.py` | Defer — needed for Stage 3 multi-agent but not Stage 1 |
| Stage 1 experimental design | Magid-Branch `stage1_experimental_design.py` | Do not import; implements ablation, not factorial |
| Ablation runner | Magid-Branch `run_ablation_experiments.py` | Do not import; wrong design |
| Stage 0 model comparison | Main branch `stage0_vdem_expert_assignment.py` | Do not import; wrong criterion |

---

## Directory structure

```
panel-member/
  pipeline/
    ingest.py                    # PDF → text (from existing pipeline)
    build_chromadb_index.py      # Per-country ChromaDB index builder
    retrieve.py                  # ChromaDB query + packet assembly
    assemble_prompt.py           # Persona + calibration + codebook + evidence
    code_country_year.py         # Single LLM call + output schema
    run_stage1_experiment.py     # Full factorial loop with retry/backoff
    analyze_stage1.R             # Regression analysis of Stage 1 results
    generate_design_matrix.R     # AlgDesign fractional factorial matrix
    irt/
      build_mm_input.R
      sequential_replacement.R
      run_mm.R
      eval_mm.R
      quasilda4.stan              # Copied from V-Dem public repo
    vdem_config.py               # Model config, paths, constants
    vdem_data_loader.py          # From Magid-Branch
  data/
    raw/                         # PDFs (gitignored)
    processed/                   # Text, ChromaDB index, outputs (gitignored)
    chromadb/                    # Vector store (gitignored)
```
