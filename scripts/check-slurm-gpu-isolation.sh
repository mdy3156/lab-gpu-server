#!/usr/bin/env bash
set -euo pipefail

# Smoke-test that Slurm can allocate exactly one GPU through GRES/cgroup. The
# important checks are CUDA_VISIBLE_DEVICES and the number of GPUs visible in
# nvidia-smi inside the srun shell.

echo "==> Slurm partitions/nodes"
sinfo

echo
echo "==> Slurm node detail"
scontrol show node

cat <<'EOF'

==> GPU isolation smoke test
This runs one interactive Slurm step with:
  --gres=gpu:1 --cpus-per-task=4 --mem=8G

Inside the job, confirm:
  - CUDA_VISIBLE_DEVICES contains a single device index, often 0
  - nvidia-smi shows only one GPU when Slurm cgroup device isolation is active

If all GPUs are still visible, check /etc/slurm/cgroup.conf, TaskPlugin in
/etc/slurm/slurm.conf, and restart slurmctld/slurmd.

EOF

srun --gres=gpu:1 --cpus-per-task=4 --mem=8G --pty bash -lc 'hostname; echo $CUDA_VISIBLE_DEVICES; nvidia-smi'
