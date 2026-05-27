#!/usr/bin/env bash
set -euo pipefail

journalctl -u jupyterhub -f
