#!/usr/bin/env bash
set -u

echo "== Slurm partitions/nodes =="
sinfo

echo
echo "== Slurm CPU/GRES/memory summary =="
sinfo -o "%P %G %c %m %D %N"

echo
echo "== GPU allocation smoke test =="
echo "If your cluster requires a partition, add: -p <partition>"
echo "If your cluster uses a different GRES name, edit: --gres=gpu:1"
echo "If this fails with a memory error, lower --mem here and req_memory in config/jupyterhub_config.py"

srun --gres=gpu:1 --cpus-per-task=4 --mem=8G --pty bash -lc 'hostname; echo "${CUDA_VISIBLE_DEVICES:-}"; nvidia-smi'
