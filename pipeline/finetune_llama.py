#!/usr/bin/env python3
"""
QLoRA fine-tuning of Llama 3.3 70B Instruct on V-Dem coder-level ratings.

Loads the training JSONL from prepare_finetune_data.py, applies the Llama 3
chat template, and trains a LoRA adapter using TRL SFTTrainer. Loss is computed
only on the assistant turn (the integer rating), not on the prompt.

The saved adapter is loaded by vLLM at inference via --lora-modules, with the
served model name matching vdem_config.py ("llama-70b-vdem-ft").

Prerequisites:
  - finetune conda env: transformers peft bitsandbytes trl accelerate datasets flash-attn
  - data/processed/finetune_train.jsonl (from prepare_finetune_data.py)
  - Model weights at --model-path (from slurm/setup_models.sh)

Usage (via SLURM — preferred):
    sbatch slurm/run_finetune.sh

Usage (direct, for testing on a single GPU):
    python3 -m pipeline.finetune_llama \\
        --model-path /scratch/$USER/models/llama-3.3-70b-instruct \\
        --output-dir data/output/adapters/llama-70b-vdem-ft \\
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
    TrainingArguments,
)
from trl import DataCollatorForCompletionOnlyLM, SFTTrainer

TRAIN_DATA_PATH = (
    Path(__file__).parent.parent / "data" / "processed" / "finetune_train.jsonl"
)
DEFAULT_OUTPUT_DIR = (
    Path(__file__).parent.parent
    / "data" / "output" / "adapters" / "llama-70b-vdem-ft"
)

# All attention and MLP projection layers — standard for Llama 3 QLoRA
LORA_TARGET_MODULES = [
    "q_proj", "k_proj", "v_proj", "o_proj",
    "gate_proj", "up_proj", "down_proj",
]

# Llama 3 assistant header — DataCollatorForCompletionOnlyLM masks everything before this
ASSISTANT_HEADER = "<|start_header_id|>assistant<|end_header_id|>\n\n"


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


def apply_chat_template(examples: dict, tokenizer) -> dict:
    """Convert messages list to a single string using the model's chat template."""
    texts = []
    for messages in examples["messages"]:
        text = tokenizer.apply_chat_template(
            messages,
            tokenize=False,
            add_generation_prompt=False,
        )
        texts.append(text)
    return {"text": texts}


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
        default=str(TRAIN_DATA_PATH),
        help="Training JSONL from prepare_finetune_data.py",
    )
    parser.add_argument(
        "--output-dir",
        default=str(DEFAULT_OUTPUT_DIR),
        help="Directory to save LoRA adapter weights",
    )
    parser.add_argument("--epochs",       type=int,   default=3)
    parser.add_argument("--lora-rank",    type=int,   default=16)
    parser.add_argument("--lora-alpha",   type=int,   default=32)
    parser.add_argument("--lora-dropout", type=float, default=0.05)
    parser.add_argument("--lr",           type=float, default=2e-4)
    parser.add_argument("--batch-size",   type=int,   default=4)
    parser.add_argument("--grad-accum",   type=int,   default=4)
    parser.add_argument("--max-seq-len",  type=int,   default=16384)
    parser.add_argument("--save-steps",   type=int,   default=500,
        help="Save and evaluate a checkpoint every N training steps")
    parser.add_argument("--val-split",    type=float, default=0.1,
        help="Fraction of training data held out for checkpoint evaluation")
    parser.add_argument("--early-stopping-patience", type=int, default=10,
        help="Stop if eval_loss has not improved for this many eval steps (0 = disabled)")
    parser.add_argument("--resume-from-checkpoint", default=None,
        help="Path to a checkpoint directory to resume training from")
    parser.add_argument(
        "--no-flash-attn", action="store_true",
        help="Disable flash attention 2 (use if flash-attn is not installed)",
    )
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
    print(f"  {len(train_dataset):,} train  |  {len(eval_dataset):,} validation")

    # ── Tokenizer ──────────────────────────────────────────────────────────────
    print(f"Loading tokenizer from {args.model_path}...")
    tokenizer = AutoTokenizer.from_pretrained(args.model_path)
    tokenizer.pad_token = tokenizer.eos_token
    tokenizer.padding_side = "right"

    # Apply chat template before loading the model (CPU, fast)
    print("Applying chat template...")
    train_dataset = train_dataset.map(
        lambda ex: apply_chat_template(ex, tokenizer),
        batched=True,
        remove_columns=["messages"],
    )
    eval_dataset = eval_dataset.map(
        lambda ex: apply_chat_template(ex, tokenizer),
        batched=True,
        remove_columns=["messages"],
    )

    # ── Model ──────────────────────────────────────────────────────────────────
    bnb_config = BitsAndBytesConfig(
        load_in_4bit=True,
        bnb_4bit_quant_type="nf4",
        bnb_4bit_compute_dtype=torch.bfloat16,
        bnb_4bit_use_double_quant=True,
    )
    attn_impl = "eager" if args.no_flash_attn else "flash_attention_2"
    print(f"Loading base model from {args.model_path} (attn={attn_impl})...")
    model = AutoModelForCausalLM.from_pretrained(
        args.model_path,
        quantization_config=bnb_config,
        device_map="auto",
        torch_dtype=torch.bfloat16,
        attn_implementation=attn_impl,
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

    # ── Data collator: loss on assistant turn only ─────────────────────────────
    collator = DataCollatorForCompletionOnlyLM(
        response_template=ASSISTANT_HEADER,
        tokenizer=tokenizer,
    )

    # ── Training ───────────────────────────────────────────────────────────────
    training_args = TrainingArguments(
        output_dir=str(output_dir),
        num_train_epochs=args.epochs,
        per_device_train_batch_size=args.batch_size,
        gradient_accumulation_steps=args.grad_accum,
        learning_rate=args.lr,
        lr_scheduler_type="cosine",
        warmup_ratio=0.05,
        bf16=True,
        fp16=False,
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
        tokenizer=tokenizer,
        train_dataset=train_dataset,
        eval_dataset=eval_dataset,
        data_collator=collator,
        args=training_args,
        max_seq_length=args.max_seq_len,
        dataset_text_field="text",
        packing=False,
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
