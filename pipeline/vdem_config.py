"""
Central config for the panel-member pipeline: LLM model definitions and constants.

All models use the OpenAI-compatible chat completions API. Swapping between Together.xyz
(development) and GW Pegasus vLLM (production) requires only changing the model key.

Environment variables:
  TOGETHER_API_KEY   — Together.xyz models (dev/testing)
  VLLM_API_KEY       — vLLM local server (can be any non-empty string if auth is off)
  VLLM_BASE_URL      — vLLM server address (default: http://localhost:8000/v1)
"""

import os

_VLLM_URL = os.environ.get("VLLM_BASE_URL", "http://localhost:8000/v1")

LLM_CONFIGS = {
    # ── Open models via Together.xyz (dev / small-scale testing) ────────────────
    "llama-405b": {
        "base_url": "https://api.together.xyz/v1",
        "model": "meta-llama/Meta-Llama-3.1-405B-Instruct-Turbo",
        "api_key_env": "TOGETHER_API_KEY",
    },
    "llama-70b": {
        "base_url": "https://api.together.xyz/v1",
        "model": "meta-llama/Llama-3.3-70B-Instruct-Turbo",
        "api_key_env": "TOGETHER_API_KEY",
    },
    "llama-8b": {
        "base_url": "https://api.together.xyz/v1",
        "model": "meta-llama/Llama-3.1-8B-Instruct-Turbo",
        "api_key_env": "TOGETHER_API_KEY",
    },

    # ── Open models via GW Pegasus vLLM (production runs) ────────────────────────
    # Set VLLM_BASE_URL to http://<node-hostname>:<port>/v1 before running.
    # Set VLLM_API_KEY to any non-empty string if the server runs without auth.
    # supports_logprobs: vLLM's OpenAI server returns top_logprobs, so these keys capture
    # the rating-token distribution for the expectation (mean) readout. Left off the
    # Together keys above (dev-only; top_logprobs support is inconsistent) and off any
    # non-logprob provider — code_country_year only requests logprobs where this is True.
    "llama-405b-local": {
        "base_url": _VLLM_URL,
        "model": "meta-llama/Meta-Llama-3.1-405B-Instruct",
        "api_key_env": "VLLM_API_KEY",
        "supports_logprobs": True,
    },
    "llama-70b-local": {
        "base_url": _VLLM_URL,
        "model": "meta-llama/Llama-3.3-70B-Instruct",
        "api_key_env": "VLLM_API_KEY",
        "supports_logprobs": True,
    },
    "llama-8b-local": {
        "base_url": _VLLM_URL,
        "model": "meta-llama/Llama-3.1-8B-Instruct",
        "api_key_env": "VLLM_API_KEY",
        "supports_logprobs": True,
    },

    # ── Fine-tuned models (FT-raw, FT-anon, FT-summ) ─────────────────────────
    # Three QLoRA adapters, served via local vLLM with --lora-modules.
    # The "model" value must match the alias given to --lora-modules at vLLM launch.
    "llama-70b-ft-raw": {
        "base_url": _VLLM_URL,
        "model": "llama-70b-vdem-ft-raw",
        "api_key_env": "VLLM_API_KEY",
        "supports_logprobs": True,
    },
    "llama-70b-ft-anon": {
        "base_url": _VLLM_URL,
        "model": "llama-70b-vdem-ft-anon",
        "api_key_env": "VLLM_API_KEY",
        "supports_logprobs": True,
    },
    "llama-70b-ft-summ": {
        "base_url": _VLLM_URL,
        "model": "llama-70b-vdem-ft-summ",
        "api_key_env": "VLLM_API_KEY",
        "supports_logprobs": True,
    },

    # ── Exploratory extension: Qwen2.5-72B (cross-family robustness) ─────────────
    # Same block recipe as Llama (RMSNorm/RoPE/GQA/SwiGLU, same 7 LoRA projections),
    # so finetune_llama.py and the LoRA target modules are reused unchanged. Qwen adds
    # attention bias, but bias="none" leaves it frozen. Native system role. Verify
    # single-token rating digits + token-length p99 with verify_tokenizer.py first.
    "qwen-72b": {  # Together.xyz (dev / smoke)
        "base_url": "https://api.together.xyz/v1",
        "model": "Qwen/Qwen2.5-72B-Instruct-Turbo",
        "api_key_env": "TOGETHER_API_KEY",
    },
    "qwen-72b-local": {  # GW Pegasus vLLM (production)
        "base_url": _VLLM_URL,
        "model": "Qwen/Qwen2.5-72B-Instruct",
        "api_key_env": "VLLM_API_KEY",
        "supports_logprobs": True,
    },
    "qwen-72b-ft-raw": {
        "base_url": _VLLM_URL,
        "model": "qwen-72b-vdem-ft-raw",
        "api_key_env": "VLLM_API_KEY",
        "supports_logprobs": True,
    },
    "qwen-72b-ft-anon": {
        "base_url": _VLLM_URL,
        "model": "qwen-72b-vdem-ft-anon",
        "api_key_env": "VLLM_API_KEY",
        "supports_logprobs": True,
    },
    "qwen-72b-ft-summ": {
        "base_url": _VLLM_URL,
        "model": "qwen-72b-vdem-ft-summ",
        "api_key_env": "VLLM_API_KEY",
        "supports_logprobs": True,
    },

    # ── Exploratory extension: Gemma 3 27B (different family/architecture) ───────
    # Multimodal checkpoint; finetune_llama.py loads the text-only Gemma3ForCausalLM.
    # System role is folded by Gemma's own chat template (verify_tokenizer: "native"),
    # so no shim. Single-token rating digits confirmed. Raw variant only, to match
    # the Qwen extension.
    "gemma-27b-local": {  # GW Pegasus vLLM (production)
        "base_url": _VLLM_URL,
        "model": "google/gemma-3-27b-it",
        "api_key_env": "VLLM_API_KEY",
        "supports_logprobs": True,
    },
    "gemma-27b-ft-raw": {
        "base_url": _VLLM_URL,
        "model": "gemma-27b-vdem-ft-raw",
        "api_key_env": "VLLM_API_KEY",
        "supports_logprobs": True,
    },
}

# Valid prompt conditions for the 4-condition primary experiment.
CONDITIONS = ["codebook", "evidence", "anonymized", "summarized"]

# Zero-shot ablation conditions (2019 primary year, 70B base only).
# Same as the primary conditions but with the few-shot calibration block omitted.
# Part of the primary analysis: isolates the few-shot block's contribution and gives
# the FT-vs-base comparison a prompt-structure-matched baseline. The few-shot
# comparators are the base model's primary-condition runs.
CONDITIONS_ZEROSHOT = ["evidence-zeroshot", "anonymized-zeroshot", "summarized-zeroshot"]

# Conditions for fine-tuned model inference.
# FT adapters run under these conditions; calibration is in the adapter weights.
# "finetuned-anon", "finetuned-raw", "finetuned-summ" are training-data-assembly
# shorthands only — accepted by assemble_prompt.py, rejected by code_country_year.py.
FT_CONDITIONS = ["codebook", "evidence-zeroshot", "anonymized-zeroshot", "summarized-zeroshot"]

# All runnable conditions (primary + ablation)
ALL_CONDITIONS = CONDITIONS + CONDITIONS_ZEROSHOT

# Base model for the confirmatory design: Llama 3.3 70B only. 405B and 8B are not part
# of the confirmatory 4-condition x 4-model design (see docs/experimental-design.md).
#   - llama-405b: aspirational only. Does not fit GW Pegasus's available allocation
#     (2 eight-A100 nodes cluster-wide). If compute becomes available it may be run later
#     as an exploratory addition, reported separately from the confirmatory results —
#     never folded into them after the fact. Left in LLM_CONFIGS for that possibility.
#   - llama-8b: used only for an early pipeline-validation smoke test (codebook + evidence,
#     unanalyzed). Not part of the confirmatory design. Left in LLM_CONFIGS for reuse if
#     more smoke testing is needed.
PRIMARY_MODELS = ["llama-70b"]

# All confirmatory models (base + fine-tuned)
ALL_MODELS = ["llama-70b",
              "llama-70b-ft-raw", "llama-70b-ft-anon", "llama-70b-ft-summ"]

# On GW Pegasus, swap in local variants:
# PRIMARY_MODELS_LOCAL = ["llama-70b-local"]

PROMPT_VARIANT = "panel-member-v1"
