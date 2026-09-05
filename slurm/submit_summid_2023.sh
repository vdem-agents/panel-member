#!/bin/bash
# One-shot submitter for the Summarized-Identified 2023 pipeline. Not a SLURM job itself —
# run it on the login node from the repo root:
#
#   bash slurm/submit_summid_2023.sh
#
# It chains, with afterok dependencies, so you can fire and forget:
#   1. IDENTIFIED=1 summarise for the few-shot pool years (2016-2018) and the target year (2023)
#   2. build fewshot_examples_summarized_identified.json once the three pool years finish
#   3. base coding (llama / qwen / gemma) on 2023 once the few-shot JSON and the 2023 summary
#      are both in place
#
# All sbatch calls use --export=ALL,VAR=... rather than the inline `VAR=val sbatch` form,
# which has silently failed to propagate on this cluster before.
set -eo pipefail
cd "$(dirname "$0")/.."

j16=$(sbatch --parsable --export=ALL,IDENTIFIED=1,YEAR=2016 slurm/run_summarize.sh)
j17=$(sbatch --parsable --export=ALL,IDENTIFIED=1,YEAR=2017 slurm/run_summarize.sh)
j18=$(sbatch --parsable --export=ALL,IDENTIFIED=1,YEAR=2018 slurm/run_summarize.sh)
j23=$(sbatch --parsable --export=ALL,IDENTIFIED=1,YEAR=2023 slurm/run_summarize.sh)
echo "summarise: 2016=$j16  2017=$j17  2018=$j18  2023=$j23"

jpop=$(sbatch --parsable \
    --dependency=afterok:"$j16":"$j17":"$j18" \
    slurm/run_populate_fewshot_summid.sh)
echo "populate few-shot JSON: $jpop  (after $j16,$j17,$j18)"

for base in llama qwen gemma; do
    jc=$(sbatch --parsable \
        --export=ALL,YEAR=2023,BASE="$base",CONDITION=summarized-identified \
        --time=06:00:00 \
        --dependency=afterok:"$jpop":"$j23" \
        slurm/run_coding_base.sh)
    echo "coding $base: $jc  (after $jpop,$j23)"
done
