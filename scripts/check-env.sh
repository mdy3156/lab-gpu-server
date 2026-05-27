#!/usr/bin/env bash
set -u

section() {
  printf '\n== %s ==\n' "$1"
}

run() {
  printf '$'
  printf ' %q' "$@"
  printf '\n'
  "$@" || true
}

section "OS"
run cat /etc/os-release
run uname -a

section "Python"
run command -v python3
run python3 --version
run command -v pip3
run pip3 --version
run /opt/lab-server/venv/bin/python --version
run /opt/lab-server/venv/bin/pip --version

section "Node.js"
run command -v node
run node --version
run command -v npm
run npm --version
run command -v configurable-http-proxy
run configurable-http-proxy --version

section "GPU"
run command -v nvidia-smi
run nvidia-smi

section "Slurm commands"
run command -v sinfo
run command -v squeue
run command -v srun
run command -v sbatch
run command -v scontrol

section "Slurm status"
run sinfo
run squeue
run scontrol show node
