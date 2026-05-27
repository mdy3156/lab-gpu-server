#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/opt/lab-server"
SERVICE_LINK="/etc/systemd/system/jupyterhub.service"

if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: setup.sh must be run as root. Use: sudo bash setup.sh" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
if [[ "${SCRIPT_DIR}" != "${INSTALL_DIR}" ]]; then
  echo "ERROR: this repository must be located at ${INSTALL_DIR}." >&2
  echo "Clone it with: sudo git clone <REPOSITORY_URL> ${INSTALL_DIR}" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "==> Updating apt package index"
apt update

echo "==> Installing OS packages"
apt install -y \
  python3 \
  python3-venv \
  python3-pip \
  nodejs \
  npm \
  git \
  curl

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

cat <<'EOF'

Setup completed.

Start JupyterHub with:
  sudo systemctl start jupyterhub

Check logs with:
  sudo journalctl -u jupyterhub -f

Before production use, edit:
  /opt/lab-server/config/jupyterhub_config.py

At minimum, replace YOUR_ADMIN_USER and confirm Slurm partition/GRES settings.
EOF
