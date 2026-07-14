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
    "llama-9b": {
        "base_url": "https://api.together.xyz/v1",
        "model": "meta-llama/Llama-3.2-9B-Instruct-Turbo",
        "api_key_env": "TOGETHER_API_KEY",
    },

    # ── Open models via GW Pegasus vLLM (production runs) ────────────────────────
    # Set VLLM_BASE_URL to http://<node-hostname>:<port>/v1 before running.
    # Set VLLM_API_KEY to any non-empty string if the server runs without auth.
    "llama-405b-local": {
        "base_url": _VLLM_URL,
        "model": "meta-llama/Meta-Llama-3.1-405B-Instruct",
        "api_key_env": "VLLM_API_KEY",
    },
    "llama-70b-local": {
        "base_url": _VLLM_URL,
        "model": "meta-llama/Llama-3.3-70B-Instruct",
        "api_key_env": "VLLM_API_KEY",
    },
    "llama-9b-local": {
        "base_url": _VLLM_URL,
        "model": "meta-llama/Llama-3.2-9B-Instruct",
        "api_key_env": "VLLM_API_KEY",
    },

    # ── Fine-tuned models (FT-raw and FT-anon) ────────────────────────────────
    # Two QLoRA adapters, served via local vLLM with --lora-modules.
    # The "model" value must match the alias given to --lora-modules at vLLM launch.
    # FT-raw: trained on raw section text; FT-anon: trained on anonymized section text.
    # Both run under codebook, evidence-zeroshot, and anonymized-zeroshot at inference.
    "llama-70b-ft-raw": {
        "base_url": _VLLM_URL,
        "model": "llama-70b-vdem-ft-raw",
        "api_key_env": "VLLM_API_KEY",
    },
    "llama-70b-ft-anon": {
        "base_url": _VLLM_URL,
        "model": "llama-70b-vdem-ft-anon",
        "api_key_env": "VLLM_API_KEY",
    },
}

# Valid prompt conditions for the 3-condition primary experiment.
CONDITIONS = ["codebook", "evidence", "anonymized"]

# Zero-shot ablation conditions (2023 robustness only, best base model only).
# Same as "evidence" and "anonymized" but with the few-shot calibration block omitted.
# Run only after the best base model is identified from the primary 3×5 results.
CONDITIONS_ZEROSHOT = ["evidence-zeroshot", "anonymized-zeroshot"]

# Conditions for fine-tuned model inference.
# FT-raw and FT-anon run under all three; calibration is in the adapter weights.
# "finetuned" and "finetuned-raw" are training-data-assembly shorthands only —
# they are accepted by assemble_prompt.py but rejected by code_country_year.py.
FT_CONDITIONS = ["codebook", "evidence-zeroshot", "anonymized-zeroshot"]

# All runnable conditions (primary + ablation)
ALL_CONDITIONS = CONDITIONS + CONDITIONS_ZEROSHOT

# Base models for the 3-condition substitution experiment (405B contingent on HPC availability)
PRIMARY_MODELS = ["llama-405b", "llama-70b", "llama-9b"]

# All models (base + fine-tuned)
ALL_MODELS = ["llama-405b", "llama-70b", "llama-9b", "llama-70b-ft-raw", "llama-70b-ft-anon"]

# On GW Pegasus, swap in local variants:
# PRIMARY_MODELS_LOCAL = ["llama-405b-local", "llama-70b-local", "llama-9b-local"]

PROMPT_VARIANT = "panel-member-v1"
