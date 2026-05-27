import os

from batchspawner import SlurmSpawner
from wrapspawner import ProfilesSpawner


c = get_config()  # noqa: F821

BASE_DIR = "/opt/lab-server"
STATE_DIR = os.path.join(BASE_DIR, "state")

# JupyterHub listens on port 8000.
# Do not expose this directly to the public internet. Use the university
# GlobalProtect VPN as the external access boundary, and add a reverse proxy
# only if the production network design requires one.
c.JupyterHub.bind_url = "http://:8000"

# Keep runtime state inside the repository directory, but outside Git control.
c.JupyterHub.cookie_secret_file = os.path.join(STATE_DIR, "jupyterhub_cookie_secret")
c.JupyterHub.db_url = f"sqlite:///{os.path.join(STATE_DIR, 'jupyterhub.sqlite')}"

# PAM uses existing Linux users and passwords.
c.JupyterHub.authenticator_class = "jupyterhub.auth.PAMAuthenticator"
c.Authenticator.allow_all = True

# Replace this placeholder with a real Linux username before production use.
c.Authenticator.admin_users = {"YOUR_ADMIN_USER"}

# Open JupyterLab instead of the classic notebook UI.
c.Spawner.default_url = "/lab"

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
c.Spawner.start_timeout = 600
c.Spawner.http_timeout = 120

# ProfilesSpawner presents resource choices in the JupyterHub UI.
c.JupyterHub.spawner_class = ProfilesSpawner

# This batch script intentionally does not set #SBATCH --time.
# If the cluster has DefaultTime or MaxTime configured in Slurm, those limits
# may still apply. Adjust Slurm partition settings if the production policy is
# truly "no user-facing runtime limit".
SLURM_BATCH_SCRIPT = """#!/bin/bash
#SBATCH --job-name=jupyterhub-singleuser
#SBATCH --output={{homedir}}/.jupyterhub-slurm-%j.log
#SBATCH --chdir={{homedir}}
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --export={{keepvars}}
{% if partition %}#SBATCH --partition={{partition}}
{% endif %}{% if nprocs %}#SBATCH --cpus-per-task={{nprocs}}
{% endif %}{% if memory %}#SBATCH --mem={{memory}}
{% endif %}{% if gres %}#SBATCH --gres={{gres}}
{% endif %}{% if options %}#SBATCH {{options}}
{% endif %}

set -euo pipefail

{{prologue}}
{% if srun %}{{srun}} {% endif %}{{cmd}}
{{epilogue}}
"""

c.ProfilesSpawner.profiles = [
    (
        "CPU: 4 cores, 8 GB memory",
        "cpu-4c-8g",
        SlurmSpawner,
        {
            # TODO: replace "cpu" with the production CPU partition name.
            "req_partition": "cpu",
            "req_nprocs": "4",
            "req_memory": "8G",
            "req_gres": "",
            # Add site-specific Slurm options here if needed, for example:
            # "--account=<account>" or "--qos=<qos>".
            "req_options": "",
            "batch_script": SLURM_BATCH_SCRIPT,
        },
    ),
    (
        "GPU: 1 GPU, 4 cores, 16 GB memory",
        "gpu-1-4c-16g",
        SlurmSpawner,
        {
            # TODO: replace "gpu" with the production GPU partition name.
            "req_partition": "gpu",
            "req_nprocs": "4",
            "req_memory": "16G",
            # TODO: change this if the cluster uses a different GRES name,
            # for example "gpu:a100:1" or "gpu:rtx6000:1".
            "req_gres": "gpu:1",
            # Add site-specific Slurm options here if needed, for example:
            # "--account=<account>" or "--qos=<qos>".
            "req_options": "",
            "batch_script": SLURM_BATCH_SCRIPT,
        },
    ),
]
