#!/usr/bin/env bash
set -euo pipefail

# Install only the OS packages and base services needed for a single-node Slurm
# controller/worker. This script intentionally does not write Slurm config
# files; run generate-slurm-config-single-node.sh after reviewing the detected
# hardware.

if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: install-slurm-single-node.sh must be run as root." >&2
  echo "Use: sudo bash scripts/install-slurm-single-node.sh" >&2
  exit 1
fi

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SLURM_DIR="/etc/slurm"

export DEBIAN_FRONTEND=noninteractive

echo "==> Checking for existing Slurm configuration"
shopt -s nullglob
EXISTING_SLURM_CONFS=("${SLURM_DIR}"/*.conf)
if [[ "${#EXISTING_SLURM_CONFS[@]}" -gt 0 ]]; then
  echo "WARNING: existing Slurm configuration files were found:"
  printf '  %s\n' "${EXISTING_SLURM_CONFS[@]}"
  echo
  echo "This installer will not overwrite existing Slurm configuration."
  echo "Review the current configuration before running the generator."
else
  echo "No existing ${SLURM_DIR}/*.conf files found."
fi

echo
echo "==> Updating apt package index"
apt update

echo
echo "==> Installing MUNGE and Slurm packages"
apt install -y munge slurm-wlm

echo
echo "==> Enabling and starting MUNGE"
systemctl enable munge
systemctl start munge
systemctl status munge --no-pager || true

echo
echo "==> NVIDIA driver/GPU summary"
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi
  echo
  nvidia-smi -L
else
  echo "WARNING: nvidia-smi was not found in PATH."
  echo "Install the NVIDIA driver before expecting Slurm GPU GRES to work."
fi

echo
echo "==> Host summary"
echo "Short hostname:"
hostname -s
echo
echo "CPU summary:"
lscpu
echo
echo "Memory summary:"
free -m

cat <<EOF

Slurm package installation completed.

This script did not modify /etc/slurm/*.conf.

Next step: generate single-node Slurm configuration after reviewing the host
summary above.

Recommended command:
  sudo bash ${SOURCE_DIR}/scripts/generate-slurm-config-single-node.sh

The generator will create timestamped .bak files before replacing existing:
  /etc/slurm/slurm.conf
  /etc/slurm/gres.conf
  /etc/slurm/cgroup.conf
EOF
