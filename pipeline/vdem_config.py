"""
Central config for the panel-member pipeline: LLM model definitions and constants.

All models use the OpenAI-compatible chat completions API. Swapping between Together.xyz
(development) and GW Pegasus vLLM (production) requires only changing the model key.

Environment variables:
  ANTHROPIC_API_KEY  — Claude (required for claude-sonnet)
  TOGETHER_API_KEY   — Together.xyz models (dev/testing)
  VLLM_API_KEY       — vLLM local server (can be any non-empty string if auth is off)
  VLLM_BASE_URL      — vLLM server address (default: http://localhost:8000/v1)
"""

import os

_VLLM_URL = os.environ.get("VLLM_BASE_URL", "http://localhost:8000/v1")

LLM_CONFIGS = {
    # ── Frontier model ──────────────────────────────────────────────────────────
    "claude-sonnet": {
        "base_url": "https://api.anthropic.com/v1",
        "model": "claude-sonnet-4-6",
        "api_key_env": "ANTHROPIC_API_KEY",
    },

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

    # ── Fine-tuned model (Condition 4) ─────────────────────────────────────────
    # Served via local vLLM with --lora-modules pointing at QLoRA adapter weights.
    # The model name below must match the --served-model-name argument at vLLM launch.
    "llama-70b-finetuned": {
        "base_url": _VLLM_URL,
        "model": "llama-70b-vdem-ft",
        "api_key_env": "VLLM_API_KEY",
    },
}

# Valid prompt conditions (in order of increasing richness)
# Fine-tuned Llama 70B (llama-70b-finetuned) uses the "anonymized" prompt format
# without the few-shot block; it is handled as a separate model, not a condition.
CONDITIONS = ["codebook", "evidence", "anonymized"]

# Base models for the 3-condition calibration experiment
PRIMARY_MODELS = ["claude-sonnet", "llama-405b", "llama-70b", "llama-9b"]

# All five models (base + fine-tuned); fine-tuned runs only under "anonymized" format
ALL_MODELS = ["claude-sonnet", "llama-405b", "llama-70b", "llama-9b", "llama-70b-finetuned"]

# On GW Pegasus, swap in local variants:
# PRIMARY_MODELS_LOCAL = ["claude-sonnet", "llama-405b-local", "llama-70b-local", "llama-9b-local"]

PROMPT_VARIANT = "panel-member-v1"
