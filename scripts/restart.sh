#!/usr/bin/env bash
set -euo pipefail

systemctl daemon-reload
systemctl restart jupyterhub
systemctl status jupyterhub --no-pager
