# lab-gpu-server

研究室サーバーで JupyterHub + JupyterLab を Slurm 経由で使うための最小構成リポジトリです。

Ubuntu サーバー上の `/opt/lab-server` に clone し、Python パッケージは OS のグローバル環境ではなく `/opt/lab-server/venv` に入れます。外部アクセスは大学既存の GlobalProtect VPN 経由を前提にし、JupyterHub 自体を直接インターネットへ公開しない設計です。

## 前提条件

- Ubuntu サーバーであること
- 管理者が `sudo` を使えること
- Linux ユーザーアカウントが作成済みで、PAM 認証でログインできること
- Slurm が別途セットアップ済みで、`sinfo`, `squeue`, `srun`, `sbatch`, `scontrol` が使えること
- GPU を使う場合は NVIDIA ドライバ、CUDA 実行環境、Slurm の GRES 設定が済んでいること
- 外部からのアクセスは GlobalProtect VPN 内から行うこと

本番環境では、最初に `scripts/check-env.sh` と `scripts/check-slurm.sh` を実行して、OS、Node.js、Python、GPU、Slurm の状態を確認してから `setup.sh` を実行してください。

## セットアップ

```bash
sudo git clone <REPOSITORY_URL> /opt/lab-server
cd /opt/lab-server

bash scripts/check-env.sh
bash scripts/check-slurm.sh

sudo bash setup.sh
sudo systemctl start jupyterhub
```

起動後、GlobalProtect VPN に接続した状態で次へアクセスします。

```text
http://<server-hostname-or-ip>:8000
```

ログインにはサーバー上の Linux ユーザー名とパスワードを使います。ログイン後は JupyterLab が開き、プロファイル選択画面で CPU/GPU 資源を選びます。

## Slurm 設定の修正場所

Slurm の partition 名や GPU の GRES 名は環境ごとに異なります。必ず [config/jupyterhub_config.py](config/jupyterhub_config.py) の次の項目を本番環境に合わせて修正してください。

- `req_partition`: CPU/GPU 用 partition 名
- `req_gres`: GPU の GRES 指定。例: `gpu:1`
- `req_options`: account や QoS など、追加で必要な Slurm オプション
- `req_nprocs`: 割り当てる CPU 数
- `req_memory`: 割り当てるメモリ量

このリポジトリではユーザーが実行時間を選ぶプロファイルは用意していません。Slurm 側に `DefaultTime` や `MaxTime` が設定されている場合は、その制限が適用されます。実行時間制限を設けない方針にする場合は、JupyterHub ではなく Slurm の partition 設定も確認してください。

## 管理ユーザー

[config/jupyterhub_config.py](config/jupyterhub_config.py) の `YOUR_ADMIN_USER` は placeholder です。本番環境では管理者の Linux ユーザー名に置き換えてください。

```python
c.Authenticator.admin_users = {"YOUR_ADMIN_USER"}
```

## 起動・停止・ログ

```bash
sudo systemctl start jupyterhub
sudo systemctl status jupyterhub --no-pager
sudo bash scripts/restart.sh
sudo bash scripts/stop.sh
sudo bash scripts/logs.sh
```

`setup.sh` は `systemd/jupyterhub.service` を `/etc/systemd/system/jupyterhub.service` に symlink し、`systemctl enable jupyterhub` を実行します。再起動後も自動起動させたい場合は、この状態で問題ありません。

## 環境確認

OS、Python、Node.js、GPU、Slurm の状態をまとめて見るには次を実行します。

```bash
bash scripts/check-env.sh
```

Slurm 経由で GPU を取れるか確認するには次を実行します。

```bash
bash scripts/check-slurm.sh
```

partition 指定が必要なクラスタでは、[scripts/check-slurm.sh](scripts/check-slurm.sh) の `srun` に `-p <partition>` を追加してください。

## トラブルシューティング

### JupyterHub が起動しない

```bash
sudo systemctl status jupyterhub --no-pager
sudo journalctl -u jupyterhub -n 200 --no-pager
```

`configurable-http-proxy` が見つからない場合は、`setup.sh` が `npm install -g configurable-http-proxy` に成功しているか確認してください。

### ログインできない

- サーバー上に対象ユーザーが存在するか確認してください。
- PAM 認証でログインできるパスワードが設定されているか確認してください。
- 必要に応じて `/etc/pam.d/` 側の設定を確認してください。

### JupyterLab サーバーが起動待ちのままになる

- `squeue` で Slurm ジョブが待機していないか確認してください。
- `sinfo` で partition が利用可能か確認してください。
- `config/jupyterhub_config.py` の `req_partition` が実環境と一致しているか確認してください。
- GPU profile の `req_gres = "gpu:1"` が実環境の GRES 名と一致しているか確認してください。

### GPU が見えない

```bash
nvidia-smi
sinfo
srun --gres=gpu:1 --cpus-per-task=4 --mem=8G --pty bash -lc 'hostname; echo $CUDA_VISIBLE_DEVICES; nvidia-smi'
```

partition が必要な場合は `srun` に `-p <partition>` を追加してください。Slurm の GRES 設定が `gpu` 以外の名前を使っている場合は、`--gres=<name>:1` に修正してください。

### データベースや secret を Git 管理したくない

`state/`, `logs/`, `venv/`, cookie secret、SQLite DB は `.gitignore` で除外しています。`state/.gitkeep` と `logs/.gitkeep` だけを Git に残します。
