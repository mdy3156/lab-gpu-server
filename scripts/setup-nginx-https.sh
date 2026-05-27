#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/opt/lab-server"
NGINX_TEMPLATE="${INSTALL_DIR}/nginx/jupyterhub.conf"
NGINX_CONFIG="/etc/nginx/conf.d/lab-server-jupyterhub.conf"

LAB_SERVER_NAME="${LAB_SERVER_NAME:-_}"
LAB_SERVER_TLS_CERT="${LAB_SERVER_TLS_CERT:-/etc/ssl/certs/lab-server.crt}"
LAB_SERVER_TLS_KEY="${LAB_SERVER_TLS_KEY:-/etc/ssl/private/lab-server.key}"
LAB_SERVER_CREATE_SELF_SIGNED="${LAB_SERVER_CREATE_SELF_SIGNED:-0}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: setup-nginx-https.sh must be run as root." >&2
  exit 1
fi

if [[ ! -f "${NGINX_TEMPLATE}" ]]; then
  echo "ERROR: missing Nginx template: ${NGINX_TEMPLATE}" >&2
  echo "Run sudo bash setup.sh first so the repository is synced to ${INSTALL_DIR}." >&2
  exit 1
fi

echo "==> Installing Nginx"
apt update
apt install -y nginx openssl

if [[ "${LAB_SERVER_CREATE_SELF_SIGNED}" == "1" ]]; then
  echo "==> Creating self-signed TLS certificate for ${LAB_SERVER_NAME}"
  install -d -m 0755 "$(dirname "${LAB_SERVER_TLS_CERT}")"
  install -d -m 0700 "$(dirname "${LAB_SERVER_TLS_KEY}")"
  openssl req -x509 -nodes -newkey rsa:4096 -days 365 \
    -subj "/CN=${LAB_SERVER_NAME}" \
    -keyout "${LAB_SERVER_TLS_KEY}" \
    -out "${LAB_SERVER_TLS_CERT}"
  chmod 0600 "${LAB_SERVER_TLS_KEY}"
fi

if [[ ! -f "${LAB_SERVER_TLS_CERT}" || ! -f "${LAB_SERVER_TLS_KEY}" ]]; then
  cat >&2 <<EOF
ERROR: TLS certificate/key not found.

Set the certificate paths and rerun:
  sudo LAB_SERVER_NAME=<hostname> \\
       LAB_SERVER_TLS_CERT=/path/to/fullchain.pem \\
       LAB_SERVER_TLS_KEY=/path/to/privkey.pem \\
       bash ${INSTALL_DIR}/scripts/setup-nginx-https.sh

For temporary testing only, create a self-signed certificate:
  sudo LAB_SERVER_NAME=<hostname> \\
       LAB_SERVER_CREATE_SELF_SIGNED=1 \\
       bash ${INSTALL_DIR}/scripts/setup-nginx-https.sh
EOF
  exit 1
fi

echo "==> Installing Nginx config: ${NGINX_CONFIG}"
install -d -m 0755 "$(dirname "${NGINX_CONFIG}")"
sed \
  -e "s#__LAB_SERVER_NAME__#${LAB_SERVER_NAME}#g" \
  -e "s#__LAB_SERVER_TLS_CERT__#${LAB_SERVER_TLS_CERT}#g" \
  -e "s#__LAB_SERVER_TLS_KEY__#${LAB_SERVER_TLS_KEY}#g" \
  "${NGINX_TEMPLATE}" > "${NGINX_CONFIG}"

echo "==> Testing and reloading Nginx"
nginx -t
systemctl enable nginx
systemctl reload nginx || systemctl restart nginx

cat <<EOF

Nginx HTTPS reverse proxy is configured.

JupyterHub should run locally on:
  http://127.0.0.1:8000

Users should access:
  https://${LAB_SERVER_NAME}/

If you used a self-signed certificate, browsers will warn until the certificate
is trusted by clients.
EOF
