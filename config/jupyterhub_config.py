import os
import shlex
import tomllib

from batchspawner import SlurmSpawner
from wrapspawner import ProfilesSpawner


c = get_config()  # noqa: F821

BASE_DIR = "/opt/lab-server"
STATE_DIR = os.path.join(BASE_DIR, "state")
CONFIG_PATH = os.environ.get(
    "LAB_SERVER_CONFIG",
    os.path.join(BASE_DIR, "config", "lab-server.toml"),
)


def load_lab_config(path):
    with open(path, "rb") as f:
        return tomllib.load(f)


def env_or_config(env_name, config_section, key, default=""):
    value = os.environ.get(env_name)
    if value is not None:
        return value
    return config_section.get(key, default)


def option_lines(value):
    if value is None:
        return ""
    if isinstance(value, str):
        return value
    return "\n#SBATCH ".join(str(item) for item in value if str(item))


def as_str(value, default=""):
    if value is None:
        return default
    return str(value)


def shell_literal(value):
    return shlex.quote(str(value))


def toml_bool(value, default=False):
    if value is None:
        return default
    return bool(value)


LAB_CONFIG = load_lab_config(CONFIG_PATH)
JUPYTERHUB_CONFIG = LAB_CONFIG.get("jupyterhub", {})
RUNTIME_CONFIG = LAB_CONFIG.get("runtime", {})
SLURM_CONFIG = LAB_CONFIG.get("slurm", {})

# JupyterHub's configurable-http-proxy listens on localhost port 8000.
# In production, expose Nginx on HTTPS/443 and proxy to this local HTTP
# endpoint. This keeps JupyterHub itself off the network even inside the
# university VPN.
#
# Use an explicit host instead of http://:8000. Some Node/proxy combinations can
# log or interpret the empty host form incorrectly, for example as
# "http://8000:". For production, keep the default localhost binding and put
# Nginx in front of it.
c.JupyterHub.bind_url = env_or_config(
    "LAB_SERVER_JUPYTERHUB_BIND_URL",
    JUPYTERHUB_CONFIG,
    "bind_url",
    "http://127.0.0.1:8000",
)

# Internal Hub API endpoint. Users must not open this URL in a browser.
# On a single-node Slurm setup, localhost is fine. On a multi-node Slurm
# cluster, single-user servers run on compute nodes, so set these environment
# variables to a private login-node address reachable from compute nodes:
#   LAB_SERVER_JUPYTERHUB_HUB_BIND_URL=http://<login-node-private-ip>:8081
#   LAB_SERVER_JUPYTERHUB_HUB_CONNECT_URL=http://<login-node-private-ip>:8081
c.JupyterHub.hub_bind_url = env_or_config(
    "LAB_SERVER_JUPYTERHUB_HUB_BIND_URL",
    JUPYTERHUB_CONFIG,
    "hub_bind_url",
    "http://127.0.0.1:8081",
)
hub_connect_url = env_or_config(
    "LAB_SERVER_JUPYTERHUB_HUB_CONNECT_URL",
    JUPYTERHUB_CONFIG,
    "hub_connect_url",
)
if hub_connect_url:
    c.JupyterHub.hub_connect_url = hub_connect_url

# Keep runtime state inside the repository directory, but outside Git control.
c.JupyterHub.cookie_secret_file = os.path.join(STATE_DIR, "jupyterhub_cookie_secret")
c.JupyterHub.db_url = f"sqlite:///{os.path.join(STATE_DIR, 'jupyterhub.sqlite')}"

# PAM uses existing Linux users and passwords.
c.JupyterHub.authenticator_class = JUPYTERHUB_CONFIG.get(
    "authenticator_class",
    "jupyterhub.auth.PAMAuthenticator",
)
c.Authenticator.allow_all = toml_bool(JUPYTERHUB_CONFIG.get("allow_all"), True)

# Replace the placeholder in lab-server.toml with real Linux usernames before
# production use.
c.Authenticator.admin_users = set(JUPYTERHUB_CONFIG.get("admin_users", []))

# Open JupyterLab instead of the classic notebook UI.
c.Spawner.default_url = JUPYTERHUB_CONFIG.get("default_url", "/lab")

# Make the venv the canonical Python/Jupyter runtime for user servers too.
# This avoids falling back to any OS-global jupyterhub-singleuser command.
c.Spawner.cmd = [os.path.join(BASE_DIR, "venv", "bin", "jupyterhub-singleuser")]
c.SlurmSpawner.batchspawner_singleuser_cmd = os.path.join(
    BASE_DIR,
    "venv",
    "bin",
    "batchspawner-singleuser",
)

# Slurm jobs may spend time waiting in the queue before the single-user server
# is reachable, so the default JupyterHub timeout is often too short.
c.Spawner.start_timeout = int(JUPYTERHUB_CONFIG.get("start_timeout", 600))
c.Spawner.http_timeout = int(JUPYTERHUB_CONFIG.get("http_timeout", 120))

# ProfilesSpawner presents resource choices in the JupyterHub UI.
c.JupyterHub.spawner_class = ProfilesSpawner

PATH_PREFIX = ":".join(RUNTIME_CONFIG.get("path_entries", []))
USER_VENV = RUNTIME_CONFIG.get("user_venv", "{{homedir}}/.venvs/jupyter-default")
USER_VENV_PYTHON = RUNTIME_CONFIG.get("user_venv_python", "/usr/bin/python3")
KERNEL_NAME = RUNTIME_CONFIG.get("kernel_name", "python3")
KERNEL_DISPLAY_NAME = RUNTIME_CONFIG.get("kernel_display_name", "Python 3 (user venv)")
TERMINAL_SHELL = RUNTIME_CONFIG.get(
    "terminal_shell_wrapper",
    "/opt/lab-server/bin/jupyter-terminal-shell",
)
ENSURE_USER_VENV = toml_bool(RUNTIME_CONFIG.get("ensure_user_venv"), True)

USER_VENV_SNIPPET = ""
if ENSURE_USER_VENV:
    USER_VENV_SNIPPET = f"""
# Create a per-user default venv and Jupyter kernel if it does not exist.
# JupyterHub itself still runs from /opt/lab-server/venv, but JupyterLab
# terminals and the default user kernel use {USER_VENV}.
if [[ -z "${{LAB_SERVER_USER_VENV:-}}" ]]; then
  export LAB_SERVER_USER_VENV={shell_literal(USER_VENV)}
else
  export LAB_SERVER_USER_VENV
fi
export LAB_SERVER_USER_VENV_PYTHON={shell_literal(USER_VENV_PYTHON)}
export LAB_SERVER_USER_KERNEL_NAME={shell_literal(KERNEL_NAME)}
export LAB_SERVER_USER_KERNEL_DISPLAY_NAME={shell_literal(KERNEL_DISPLAY_NAME)}
if /opt/lab-server/bin/ensure-user-venv; then
  export PATH="${{LAB_SERVER_USER_VENV}}/bin:${{PATH}}"
else
  echo "WARN: failed to prepare ${{LAB_SERVER_USER_VENV}}; continuing with managed venv" >&2
fi
"""

TERMINAL_SHELL_SNIPPET = ""
if TERMINAL_SHELL:
    TERMINAL_SHELL_SNIPPET = f"""
# JupyterLab terminals may start zsh/bash, whose rc files can reset PATH after
# the server process has started. Use a terminal shell wrapper that sources the
# user's normal rc file and then restores the lab-server/user-venv PATH.
export LAB_SERVER_REAL_SHELL="${{SHELL:-$(getent passwd "${{USER}}" | cut -d: -f7)}}"
export SHELL={shell_literal(TERMINAL_SHELL)}
"""

GET_USER_ENV_LINE = (
    "#SBATCH --get-user-env=L"
    if toml_bool(SLURM_CONFIG.get("get_user_env"), True)
    else ""
)

SLURM_BATCH_SCRIPT = """#!/bin/bash
#SBATCH --job-name=__SLURM_JOB_NAME__
#SBATCH --output=__SLURM_LOG_PATH__
#SBATCH --chdir=__SLURM_WORKING_DIRECTORY__
#SBATCH --nodes=__SLURM_NODES__
#SBATCH --ntasks=__SLURM_NTASKS__
#SBATCH --export=__SLURM_EXPORT__
__SLURM_GET_USER_ENV__
{% if partition %}#SBATCH --partition={{partition}}
{% endif %}{% if nprocs %}#SBATCH --cpus-per-task={{nprocs}}
{% endif %}{% if memory %}#SBATCH --mem={{memory}}
{% endif %}{% if gres %}#SBATCH --gres={{gres}}
{% endif %}{% if options %}#SBATCH {{options}}
{% endif %}

set -euo pipefail

# Slurm jobs often start with a smaller PATH than an interactive login shell.
# Keep common system, CUDA, and WSL NVIDIA utility locations visible in
# JupyterLab terminals without depending on the user's dotfiles.
export LAB_SERVER_PATH_PREFIX=__PATH_PREFIX__
if [[ -n "${LAB_SERVER_PATH_PREFIX}" ]]; then
  export PATH="${LAB_SERVER_PATH_PREFIX}:${PATH:-}"
fi

__USER_VENV_SNIPPET__
__TERMINAL_SHELL_SNIPPET__

{{prologue}}
{% if srun %}{{srun}} {% endif %}{{cmd}}
{{epilogue}}
"""

SLURM_BATCH_SCRIPT = (
    SLURM_BATCH_SCRIPT.replace(
        "__SLURM_JOB_NAME__",
        as_str(SLURM_CONFIG.get("job_name", "jupyterhub-singleuser")),
    )
    .replace(
        "__SLURM_LOG_PATH__",
        as_str(SLURM_CONFIG.get("log_path", "{{homedir}}/.jupyterhub-slurm-%j.log")),
    )
    .replace(
        "__SLURM_WORKING_DIRECTORY__",
        as_str(SLURM_CONFIG.get("working_directory", "{{homedir}}")),
    )
    .replace("__SLURM_NODES__", as_str(SLURM_CONFIG.get("nodes", "1")))
    .replace("__SLURM_NTASKS__", as_str(SLURM_CONFIG.get("ntasks", "1")))
    .replace("__SLURM_EXPORT__", as_str(SLURM_CONFIG.get("export", "{{keepvars}}")))
    .replace("__SLURM_GET_USER_ENV__", GET_USER_ENV_LINE)
    .replace("__PATH_PREFIX__", shell_literal(PATH_PREFIX))
    .replace("__USER_VENV_SNIPPET__", USER_VENV_SNIPPET.strip())
    .replace("__TERMINAL_SHELL_SNIPPET__", TERMINAL_SHELL_SNIPPET.strip())
)

c.ProfilesSpawner.profiles = []
profiles = LAB_CONFIG.get("profiles", [])
if not profiles:
    raise RuntimeError(f"No [[profiles]] are configured in {CONFIG_PATH}")

for profile in profiles:
    for required_key in ("display_name", "key"):
        if required_key not in profile:
            raise RuntimeError(
                f"Profile in {CONFIG_PATH} is missing required key: {required_key}"
            )

    spawner_options = {
        "req_partition": as_str(profile.get("partition", "")),
        "req_nprocs": as_str(profile.get("cpus", "")),
        "req_memory": as_str(profile.get("memory", "")),
        "req_gres": as_str(profile.get("gres", "")),
        "req_options": option_lines(profile.get("options", [])),
        "batch_script": SLURM_BATCH_SCRIPT,
    }
    if "srun" in profile:
        spawner_options["req_srun"] = as_str(profile.get("srun", ""))

    c.ProfilesSpawner.profiles.append(
        (
            profile["display_name"],
            profile["key"],
            SlurmSpawner,
            spawner_options,
        )
    )
