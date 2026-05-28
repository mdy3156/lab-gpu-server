#!/usr/bin/env bash
set -euo pipefail

# Generate a conservative single-node Slurm configuration for a GPU server.
# The output is intended for "first make --gres=gpu:1 work" rather than for a
# highly customized cluster policy. Existing config files are backed up before
# they are replaced.

if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: generate-slurm-config-single-node.sh must be run as root." >&2
  echo "Use: sudo bash scripts/generate-slurm-config-single-node.sh" >&2
  exit 1
fi

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TEMPLATE_DIR="${SOURCE_DIR}/slurm"
SLURM_DIR="/etc/slurm"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

SLURM_CONF="${SLURM_DIR}/slurm.conf"
GRES_CONF="${SLURM_DIR}/gres.conf"
CGROUP_CONF="${SLURM_DIR}/cgroup.conf"

require_template() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    echo "ERROR: missing template: ${path}" >&2
    exit 1
  fi
}

backup_if_exists() {
  local path="$1"
  if [[ -e "${path}" ]]; then
    local backup="${path}.bak-${TIMESTAMP}"
    echo "==> Backing up ${path} to ${backup}"
    cp -a "${path}" "${backup}"
  fi
}

detect_gpu_count() {
  if ! command -v nvidia-smi >/dev/null 2>&1; then
    echo "ERROR: nvidia-smi was not found in PATH; cannot detect NVIDIA GPUs." >&2
    exit 1
  fi

  # Count lines like "GPU 0: ...". This avoids depending on the GPU model name
  # and works for A100 as well as other NVIDIA cards.
  local count
  count="$(nvidia-smi -L | awk '/^GPU [0-9]+:/ {count++} END {print count+0}')"
  if [[ "${count}" -lt 1 ]]; then
    echo "ERROR: nvidia-smi -L did not report any GPUs." >&2
    exit 1
  fi
  echo "${count}"
}

gpu_file_pattern() {
  local count="$1"
  if [[ "${count}" -eq 1 ]]; then
    echo "/dev/nvidia0"
  else
    echo "/dev/nvidia[0-$((count - 1))]"
  fi
}

render_template() {
  local template="$1"
  local output="$2"

  # Use sed for simple token replacement. Values are detected locally and are
  # limited to host/resource strings, so no shell evaluation is involved.
  sed \
    -e "s|@NODE_NAME@|${NODE_NAME}|g" \
    -e "s|@CPU_COUNT@|${CPU_COUNT}|g" \
    -e "s|@REAL_MEMORY_MB@|${REAL_MEMORY_MB}|g" \
    -e "s|@GPU_COUNT@|${GPU_COUNT}|g" \
    -e "s|@GPU_FILE_PATTERN@|${GPU_FILE_PATTERN}|g" \
    "${template}" > "${output}"
}

require_template "${TEMPLATE_DIR}/slurm.conf.template"
require_template "${TEMPLATE_DIR}/gres.conf.template"
require_template "${TEMPLATE_DIR}/cgroup.conf.template"

if ! getent passwd slurm >/dev/null; then
  echo "ERROR: the slurm user does not exist. Install slurm-wlm first." >&2
  exit 1
fi

NODE_NAME="$(hostname -s)"
CPU_COUNT="$(nproc --all)"
REAL_MEMORY_MB="$(awk '/^MemTotal:/ {print int($2 / 1024)}' /proc/meminfo)"
GPU_COUNT="$(detect_gpu_count)"
GPU_FILE_PATTERN="$(gpu_file_pattern "${GPU_COUNT}")"

if [[ -z "${NODE_NAME}" || -z "${CPU_COUNT}" || -z "${REAL_MEMORY_MB}" ]]; then
  echo "ERROR: failed to detect hostname, CPU count, or memory." >&2
  exit 1
fi

cat <<EOF
==> Detected single-node Slurm resources
NodeName:   ${NODE_NAME}
CPUs:       ${CPU_COUNT}
Memory MB:  ${REAL_MEMORY_MB}
GPUs:       ${GPU_COUNT}
GPU files:  ${GPU_FILE_PATTERN}
EOF

echo
echo "==> Creating ${SLURM_DIR}"
install -d -m 0755 "${SLURM_DIR}"

echo
echo "==> Creating Slurm state and log directories"
# Ubuntu packages normally create the slurm user. These directories are named in
# slurm.conf and must be writable before slurmctld/slurmd start.
install -d -o slurm -g slurm -m 0755 /var/lib/slurm/slurmctld
install -d -o slurm -g slurm -m 0755 /var/lib/slurm/slurmd
install -d -o slurm -g slurm -m 0755 /var/log/slurm

backup_if_exists "${SLURM_CONF}"
backup_if_exists "${GRES_CONF}"
backup_if_exists "${CGROUP_CONF}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

echo
echo "==> Rendering Slurm configuration files"
render_template "${TEMPLATE_DIR}/slurm.conf.template" "${TMP_DIR}/slurm.conf"
render_template "${TEMPLATE_DIR}/gres.conf.template" "${TMP_DIR}/gres.conf"
render_template "${TEMPLATE_DIR}/cgroup.conf.template" "${TMP_DIR}/cgroup.conf"

install -m 0644 "${TMP_DIR}/slurm.conf" "${SLURM_CONF}"
install -m 0644 "${TMP_DIR}/gres.conf" "${GRES_CONF}"
install -m 0644 "${TMP_DIR}/cgroup.conf" "${CGROUP_CONF}"

echo
echo "==> Installed configuration"
ls -l "${SLURM_CONF}" "${GRES_CONF}" "${CGROUP_CONF}"

echo
echo "==> Reloading systemd and restarting Slurm services"
systemctl daemon-reload
systemctl restart munge slurmctld slurmd
systemctl enable munge slurmctld slurmd

echo
echo "==> Slurm partition/node summary"
sinfo

echo
echo "==> Slurm node detail"
scontrol show node "${NODE_NAME}"

cat <<EOF

Single-node Slurm configuration completed.

GPU smoke test:
  bash ${SOURCE_DIR}/scripts/check-slurm-gpu-isolation.sh

JupyterHub profile setting for this configuration:
  partition = "gpu"
  gres = "gpu:1"
EOF
