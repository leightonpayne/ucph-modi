#!/usr/bin/env bash

export DIR=~/modi_mount/ucph-modi/tutorials/01_hmmsearch

source "${CONDA_DIR}/etc/profile.d/conda.sh"

conda activate ~/modi_mount/conda_envs/ucph-modi-01-hmmer

function hmmsearch_wrapper() {
    local id=$(basename "${1%.fasta}")
    hmmsearch --acc --domtblout "${DIR}/domtblout/${id}.domtblout" "${DIR}/PFAM.hmm" "${1}"
}

export -f hmmsearch_wrapper

parallel --progress -j 4 'hmmsearch_wrapper {}' ::: $(find ${DIR}/faa -name "*.fasta")