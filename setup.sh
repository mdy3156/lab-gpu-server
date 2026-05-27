#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/opt/lab-server"
SERVICE_LINK="/etc/systemd/system/jupyterhub.service"

if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: setup.sh must be run as root. Use: sudo bash setup.sh" >&2
  exit 1
fi

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

sync_to_install_dir() {
  if [[ "${SOURCE_DIR}" == "${INSTALL_DIR}" ]]; then
    echo "==> Running from ${INSTALL_DIR}; no repository sync needed"
    return
  fi

  echo "==> Syncing repository from ${SOURCE_DIR} to ${INSTALL_DIR}"
  install -d -m 0755 "${INSTALL_DIR}"

  # Copy the deployable repository contents, but never copy local runtime state.
  # This keeps development convenient from ~/ while preserving /opt/lab-server
  # as the canonical runtime path used by systemd and JupyterHub.
  tar \
    --exclude=".git" \
    --exclude=".agents" \
    --exclude=".codex" \
    --exclude="venv" \
    --exclude="logs/*" \
    --exclude="state/*" \
    --exclude="config/jupyterhub.env" \
    --exclude="config/*.local.toml" \
    --exclude="__pycache__" \
    --exclude="*/__pycache__" \
    --exclude="*.pyc" \
    -C "${SOURCE_DIR}" \
    -cf - . | tar --no-same-owner -C "${INSTALL_DIR}" -xf -
}

if [[ ! -f "${SOURCE_DIR}/requirements.txt" || ! -f "${SOURCE_DIR}/config/jupyterhub_config.py" ]]; then
  echo "ERROR: setup.sh must be run from this repository." >&2
  exit 1
fi

sync_to_install_dir

export DEBIAN_FRONTEND=noninteractive

echo "==> Updating apt package index"
apt update

echo "==> Installing OS packages"
apt install -y \
  python3 \
  python3-venv \
  python3-pip \
  nodejs \
  git \
  curl

if command -v npm >/dev/null 2>&1; then
  echo "==> npm is already available: $(command -v npm) ($(npm --version))"
else
  echo "==> npm command not found; installing Ubuntu npm package"
  if ! apt install -y npm; then
    echo "ERROR: npm is not available and the Ubuntu npm package could not be installed." >&2
    echo "If Node.js was installed from NodeSource, reinstall that nodejs package or provide npm before rerunning setup.sh." >&2
    exit 1
  fi
fi

echo "==> Installing configurable-http-proxy"
npm install -g configurable-http-proxy

echo "==> Creating Python virtual environment"
python3 -m venv "${INSTALL_DIR}/venv"

echo "==> Installing Python packages into ${INSTALL_DIR}/venv"
"${INSTALL_DIR}/venv/bin/python" -m pip install --upgrade pip wheel
"${INSTALL_DIR}/venv/bin/pip" install -r "${INSTALL_DIR}/requirements.txt"

echo "==> Creating runtime directories"
install -d -m 0755 "${INSTALL_DIR}/state"
install -d -m 0755 "${INSTALL_DIR}/logs"
if [[ -f "${INSTALL_DIR}/bin/nvidia-smi" ]]; then
  chmod 0755 "${INSTALL_DIR}/bin/nvidia-smi"
  if command -v nvidia-smi >/dev/null 2>&1; then
    echo "==> nvidia-smi is already available: $(command -v nvidia-smi)"
  elif [[ -e /usr/local/bin/nvidia-smi && ! -L /usr/local/bin/nvidia-smi ]]; then
    echo "==> /usr/local/bin/nvidia-smi already exists; leaving it unchanged"
  else
    echo "==> Installing nvidia-smi convenience symlink in /usr/local/bin"
    ln -sfn "${INSTALL_DIR}/bin/nvidia-smi" /usr/local/bin/nvidia-smi
  fi
fi
if [[ -f "${INSTALL_DIR}/bin/ensure-user-venv" ]]; then
  chmod 0755 "${INSTALL_DIR}/bin/ensure-user-venv"
fi
if [[ -f "${INSTALL_DIR}/bin/jupyter-terminal-shell" ]]; then
  chmod 0755 "${INSTALL_DIR}/bin/jupyter-terminal-shell"
fi
if [[ -f "${INSTALL_DIR}/scripts/setup-nginx-https.sh" ]]; then
  chmod 0755 "${INSTALL_DIR}/scripts/setup-nginx-https.sh"
fi
if [[ -f "${INSTALL_DIR}/scripts/bind-lan-http.sh" ]]; then
  chmod 0755 "${INSTALL_DIR}/scripts/bind-lan-http.sh"
fi

echo "==> Installing systemd unit symlink"
if [[ -e "${SERVICE_LINK}" && ! -L "${SERVICE_LINK}" ]]; then
  echo "ERROR: ${SERVICE_LINK} already exists and is not a symlink." >&2
  echo "Move it away manually before installing this service." >&2
  exit 1
fi
ln -sfn "${INSTALL_DIR}/systemd/jupyterhub.service" "${SERVICE_LINK}"

echo "==> Reloading systemd and enabling jupyterhub"
systemctl daemon-reload
systemctl enable jupyterhub

if systemctl is-active --quiet jupyterhub; then
  NEXT_SERVICE_COMMAND="sudo systemctl restart jupyterhub"
  SERVICE_NOTE="JupyterHub is already running. Restart it to apply config changes."
else
  NEXT_SERVICE_COMMAND="sudo systemctl start jupyterhub"
  SERVICE_NOTE="JupyterHub is not running yet. Start it when you are ready."
fi

cat <<EOF

Setup completed.

${SERVICE_NOTE}

Next command:
  ${NEXT_SERVICE_COMMAND}

Check logs with:
  sudo journalctl -u jupyterhub -f

Before production use, edit:
  /opt/lab-server/config/lab-server.toml

At minimum, replace YOUR_ADMIN_USER and confirm Slurm partition/GRES settings.

For production HTTPS access through Nginx:
  sudo LAB_SERVER_NAME=<hostname> bash /opt/lab-server/scripts/setup-nginx-https.sh
EOF
