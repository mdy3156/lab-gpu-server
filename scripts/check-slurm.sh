#!/usr/bin/env bash
set -u

echo "== Slurm partitions/nodes =="
sinfo

echo
echo "== GPU allocation smoke test =="
echo "If your cluster requires a partition, add: -p <partition>"
echo "If your cluster uses a different GRES name, edit: --gres=gpu:1"

srun --gres=gpu:1 --cpus-per-task=4 --mem=8G --pty bash -lc 'hostname; echo "${CUDA_VISIBLE_DEVICES:-}"; nvidia-smi'
