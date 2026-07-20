#!/usr/bin/env python3
"""
QLoRA fine-tuning of Llama 3.3 70B Instruct on V-Dem coder-level ratings.

Written for the modern TRL API (>= 1.0, verified against 1.8.0 / transformers 5.x).
Training records are converted from `messages` to conversational prompt/completion
format at load time; TRL applies the chat template internally (single BOS) and
computes loss on the completion only (the JSON rating), not the prompt.

The saved adapter is loaded by vLLM at inference via --lora-modules, with the
served model name matching vdem_config.py ("llama-70b-vdem-ft").

Prerequisites:
  - finetune conda env: transformers peft bitsandbytes trl accelerate datasets
    (flash-attn not required — attention uses PyTorch SDPA, which dispatches to
    flash-attention kernels on Hopper-class GPUs)
  - data/processed/finetune_train_{variant}.jsonl (from prepare_finetune_data.py)
  - Model weights at --model-path (from slurm/setup_models.sh)

Usage (via SLURM — preferred):
    sbatch slurm/run_finetune.sh

Usage (direct, for testing on a single GPU):
    python3 -m pipeline.finetune_llama \\
        --model-path /scratch/$USER/models/llama-3.3-70b-instruct \\
        --train-data data/processed/finetune_train_anon.jsonl \\
        --output-dir data/output/adapters/llama-70b-vdem-ft-anon \\
        --epochs 1
"""

import argparse
import json
import os
from pathlib import Path

import torch
from datasets import Dataset
from peft import LoraConfig, TaskType, get_peft_model, prepare_model_for_kbit_training
from transformers import (
    AutoModelForCausalLM,
    AutoTokenizer,
    BitsAndBytesConfig,
    EarlyStoppingCallback,
)
from trl import SFTConfig, SFTTrainer

# All attention and MLP projection layers — standard for Llama 3 QLoRA
LORA_TARGET_MODULES = [
    "q_proj", "k_proj", "v_proj", "o_proj",
    "gate_proj", "up_proj", "down_proj",
]


def load_jsonl(path: Path) -> Dataset:
    records = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line:
                records.append(json.loads(line))
    if not records:
        raise ValueError(f"No records found in {path}")
    return Dataset.from_list(records)


def to_prompt_completion(example: dict) -> dict:
    """Split [system, user, assistant] messages into TRL prompt/completion format.

    With a conversational prompt/completion dataset, SFTTrainer applies the chat
    template itself and masks loss to the completion (completion_only_loss).
    """
    messages = example["messages"]
    if messages[-1]["role"] != "assistant":
        raise ValueError(f"Last message is not an assistant turn: {messages[-1]['role']}")
    return {"prompt": messages[:-1], "completion": messages[-1:]}


def main() -> None:
    parser = argparse.ArgumentParser(
        description="QLoRA fine-tune Llama 3.3 70B on V-Dem coder ratings"
    )
    parser.add_argument(
        "--model-path",
        default=os.path.expandvars("/scratch/$USER/models/llama-3.3-70b-instruct"),
        help="Path to base model weights",
    )
    parser.add_argument(
        "--train-data",
        required=True,
        help="Training JSONL from prepare_finetune_data.py (finetune_train_{variant}.jsonl)",
    )
    parser.add_argument(
        "--output-dir",
        required=True,
        help="Directory to save LoRA adapter weights (e.g. data/output/adapters/llama-70b-vdem-ft-anon)",
    )
    parser.add_argument("--epochs",       type=int,   default=3)
    parser.add_argument("--lora-rank",    type=int,   default=16)
    parser.add_argument("--lora-alpha",   type=int,   default=32)
    parser.add_argument("--lora-dropout", type=float, default=0.05)
    parser.add_argument("--lr",           type=float, default=2e-4)
    parser.add_argument("--batch-size",   type=int,   default=8)
    parser.add_argument("--grad-accum",   type=int,   default=2)
    parser.add_argument("--max-seq-len",  type=int,   default=8192)
    parser.add_argument("--save-steps",   type=int,   default=500,
        help="Save and evaluate a checkpoint every N training steps")
    parser.add_argument("--val-split",    type=float, default=0.1,
        help="Fraction of training data held out for checkpoint evaluation")
    parser.add_argument("--max-eval-examples", type=int, default=2000,
        help="Cap the eval set at this many examples (0 = no cap). Keeps eval "
             "passes cheap; a 2K sample is ample for early-stopping decisions")
    parser.add_argument("--early-stopping-patience", type=int, default=10,
        help="Stop if eval_loss has not improved for this many eval steps (0 = disabled)")
    parser.add_argument("--resume-from-checkpoint", default=None,
        help="Path to a checkpoint directory to resume training from")
    parser.add_argument("--dataset-num-proc", type=int, default=8,
        help="Worker processes for TRL dataset preparation (tokenization)")
    args = parser.parse_args()

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    # ── Load training data ─────────────────────────────────────────────────────
    print(f"Loading training data from {args.train_data}...")
    dataset = load_jsonl(Path(args.train_data))
    print(f"  {len(dataset):,} total examples")

    split = dataset.train_test_split(test_size=args.val_split, seed=42)
    train_dataset = split["train"]
    eval_dataset  = split["test"]
    if args.max_eval_examples and len(eval_dataset) > args.max_eval_examples:
        eval_dataset = eval_dataset.select(range(args.max_eval_examples))
    print(f"  {len(train_dataset):,} train  |  {len(eval_dataset):,} validation")

    # ── Tokenizer ──────────────────────────────────────────────────────────────
    print(f"Loading tokenizer from {args.model_path}...")
    tokenizer = AutoTokenizer.from_pretrained(args.model_path)
    tokenizer.pad_token = tokenizer.eos_token

    # ── Pre-flight: estimate truncation at the chosen --max-seq-len ────────────
    # Truncation is keep_start, so over-long examples lose their completion (the
    # rating) and contribute no loss — they waste compute but do not corrupt
    # training. Keep this fraction well under 1%.
    sample_size = min(5_000, len(train_dataset))
    n_over_sample = 0
    for messages in train_dataset.select(range(sample_size))["messages"]:
        ids = tokenizer.apply_chat_template(messages, tokenize=True)
        if len(ids) > args.max_seq_len:
            n_over_sample += 1
    est_truncated = int(n_over_sample / sample_size * len(train_dataset))
    print(f"Pre-flight: ~{est_truncated:,} of {len(train_dataset):,} training examples "
          f"estimated to exceed {args.max_seq_len:,} tokens "
          f"({n_over_sample / sample_size:.1%})")

    # ── Convert messages → prompt/completion ───────────────────────────────────
    print("Converting records to prompt/completion format...")
    train_dataset = train_dataset.map(
        to_prompt_completion, remove_columns=["messages"],
        num_proc=args.dataset_num_proc,
    )
    eval_dataset = eval_dataset.map(
        to_prompt_completion, remove_columns=["messages"],
    )

    # ── Model ──────────────────────────────────────────────────────────────────
    bnb_config = BitsAndBytesConfig(
        load_in_4bit=True,
        bnb_4bit_quant_type="nf4",
        bnb_4bit_compute_dtype=torch.bfloat16,
        bnb_4bit_use_double_quant=True,
    )
    print(f"Loading base model from {args.model_path} (attn=sdpa)...")
    model = AutoModelForCausalLM.from_pretrained(
        args.model_path,
        quantization_config=bnb_config,
        device_map="auto",
        dtype=torch.bfloat16,
        attn_implementation="sdpa",
    )
    model = prepare_model_for_kbit_training(model)

    # ── LoRA ───────────────────────────────────────────────────────────────────
    lora_config = LoraConfig(
        task_type=TaskType.CAUSAL_LM,
        r=args.lora_rank,
        lora_alpha=args.lora_alpha,
        lora_dropout=args.lora_dropout,
        target_modules=LORA_TARGET_MODULES,
        bias="none",
    )
    model = get_peft_model(model, lora_config)
    model.print_trainable_parameters()

    # ── Training config ────────────────────────────────────────────────────────
    training_args = SFTConfig(
        output_dir=str(output_dir),
        num_train_epochs=args.epochs,
        per_device_train_batch_size=args.batch_size,
        per_device_eval_batch_size=args.batch_size,
        gradient_accumulation_steps=args.grad_accum,
        learning_rate=args.lr,
        lr_scheduler_type="cosine",
        warmup_ratio=0.05,
        bf16=True,
        gradient_checkpointing=True,
        gradient_checkpointing_kwargs={"use_reentrant": False},
        optim="paged_adamw_8bit",
        max_grad_norm=0.3,
        logging_steps=50,
        eval_strategy="steps",
        eval_steps=args.save_steps,
        save_strategy="steps",
        save_steps=args.save_steps,
        save_total_limit=3,        # keep last 3 checkpoints; enough to recover from a kill
        load_best_model_at_end=True,
        metric_for_best_model="eval_loss",
        greater_is_better=False,
        data_seed=42,              # reproducible shuffle order across epochs
        report_to="tensorboard",
        # SFT-specific
        max_length=args.max_seq_len,
        completion_only_loss=True,
        packing=False,
        dataset_num_proc=args.dataset_num_proc,
    )

    callbacks = []
    if args.early_stopping_patience > 0:
        callbacks.append(EarlyStoppingCallback(
            early_stopping_patience=args.early_stopping_patience,
        ))
        print(f"Early stopping: patience = {args.early_stopping_patience} eval steps "
              f"({args.early_stopping_patience * args.save_steps:,} training steps)")

    trainer = SFTTrainer(
        model=model,
        args=training_args,
        train_dataset=train_dataset,
        eval_dataset=eval_dataset,
        processing_class=tokenizer,
        callbacks=callbacks,
    )

    resume = args.resume_from_checkpoint
    if resume:
        print(f"Resuming from checkpoint: {resume}")
    print("Starting training...")
    trainer.train(resume_from_checkpoint=resume)

    # ── Save adapter only (not merged weights) ─────────────────────────────────
    # vLLM loads the base model separately and applies this adapter via --lora-modules.
    # The served model name must match vdem_config.py: "llama-70b-vdem-ft"
    print(f"Saving LoRA adapter to {output_dir}...")
    trainer.model.save_pretrained(str(output_dir))
    tokenizer.save_pretrained(str(output_dir))
    print(f"Done. Adapter size: ~{sum(p.numel() for p in model.parameters() if p.requires_grad) / 1e6:.0f}M trainable params")


if __name__ == "__main__":
    main()
