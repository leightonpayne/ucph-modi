#!/usr/bin/env bash

#SBATCH --partition=modi_devel
#SBATCH --job-name=tutorial_01
#SBATCH --time=00:15:00
#SBATCH --cpus-per-task=32
#SBATCH --output=logs/%x_%A_%N_stdout.log
#SBATCH --error=logs/%x_%A_%N_stderr.log

srun singularity exec ~/modi_images/hpc-notebook-23.11.9.sif \
  ~/modi_mount/ucph-modi/tutorials/01_hmmsearch/01_run_hmmsearch.sh