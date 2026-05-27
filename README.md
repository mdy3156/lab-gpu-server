# lab-gpu-server

研究室サーバーで JupyterHub + JupyterLab を Slurm 経由で使うための最小構成リポジトリです。

最終的な実行環境は Ubuntu サーバー上の `/opt/lab-server` に作成します。開発用 checkout は `~/lab-gpu-server` など任意の場所に置けます。`sudo bash setup.sh` が現在のリポジトリ内容を `/opt/lab-server` に同期し、Python パッケージは OS のグローバル環境ではなく `/opt/lab-server/venv` に入れます。外部アクセスは大学既存の GlobalProtect VPN 経由を前提にし、JupyterHub 自体を直接インターネットへ公開しない設計です。

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
git clone <REPOSITORY_URL> ~/lab-gpu-server
cd ~/lab-gpu-server

bash scripts/check-env.sh
bash scripts/check-slurm.sh

sudo bash setup.sh
sudo systemctl start jupyterhub
```

開発・ローカル確認では、起動後に次へアクセスします。

```text
http://127.0.0.1:8000
```

`127.0.0.1:8081` は JupyterHub の内部 API 用 port です。ブラウザでは開かないでください。

本番では JupyterHub を直接外へ公開せず、Nginx の HTTPS reverse proxy から `http://127.0.0.1:8000` へ中継します。GlobalProtect VPN 内からのアクセスでも、ブラウザとサーバー間は HTTPS にしてください。

ログインにはサーバー上の Linux ユーザー名とパスワードを使います。ログイン後は JupyterLab が開き、プロファイル選択画面で CPU/GPU 資源を選びます。

## HTTPS / Nginx

実運用の推奨構成は次です。

```text
GlobalProtect VPN -> Nginx HTTPS :443 -> JupyterHub local proxy :8000 -> Slurm
```

JupyterHub の configurable-http-proxy は `127.0.0.1:8000` にだけ bind します。外部からは 8000 番ではなく、Nginx の 443 番へアクセスします。

大学・研究室で発行された証明書を使う場合:

```bash
sudo LAB_SERVER_NAME=<server-hostname> \
     LAB_SERVER_TLS_CERT=/path/to/fullchain.pem \
     LAB_SERVER_TLS_KEY=/path/to/privkey.pem \
     bash /opt/lab-server/scripts/setup-nginx-https.sh
```

一時的な動作確認だけ self-signed certificate で行う場合:

```bash
sudo LAB_SERVER_NAME=<server-hostname-or-ip> \
     LAB_SERVER_CREATE_SELF_SIGNED=1 \
     bash /opt/lab-server/scripts/setup-nginx-https.sh
```

self-signed certificate は通信を暗号化しますが、ブラウザには警告が出ます。本番では大学・研究室の正式証明書、またはクライアントに信頼させた内部 CA の証明書を使ってください。

Nginx 設定テンプレートは [nginx/jupyterhub.conf](nginx/jupyterhub.conf) です。インストール後は `/etc/nginx/conf.d/lab-server-jupyterhub.conf` に配置されます。

## LAN 内からの一時HTTP確認

同じ Wi-Fi / LAN 内の別PCから一時的に動作確認したい場合だけ、JupyterHub をサーバーのLAN IPで待ち受けさせられます。

```bash
sudo bash /opt/lab-server/scripts/bind-lan-http.sh
```

このスクリプトは `hostname -I` から最初のIPv4アドレスを選び、`/opt/lab-server/config/jupyterhub.env` に `LAB_SERVER_JUPYTERHUB_BIND_URL=http://<server-ip>:8000` を設定して JupyterHub を再起動します。IPを明示したい場合は次のように指定します。

```bash
sudo LAB_SERVER_BIND_IP=<server-ip> bash /opt/lab-server/scripts/bind-lan-http.sh
```

確認が終わったら localhost bind に戻してください。

```bash
sudo LAB_SERVER_JUPYTERHUB_BIND_URL=http://127.0.0.1:8000 \
     bash /opt/lab-server/scripts/bind-lan-http.sh
```

これはHTTPの一時確認用です。本番では Nginx HTTPS を使ってください。

## 設定ファイル

研究室ごとに変わりやすい設定は [config/lab-server.toml](config/lab-server.toml) にまとめています。通常は [config/jupyterhub_config.py](config/jupyterhub_config.py) を直接編集せず、TOML 側を変更してください。

- `[jupyterhub]`: bind URL、Hub 内部 URL、管理ユーザー、timeout
- `[runtime]`: JupyterLab server 内の PATH、ユーザーごとの venv、kernel 名
- `[slurm]`: Slurm job 名、ログ出力先、作業ディレクトリ、共通 `#SBATCH` 設定
- `[[profiles]]`: JupyterHub の CPU/GPU profile、partition、CPU 数、メモリ、GRES、追加 Slurm option

変更後は `/opt/lab-server` に同期して JupyterHub を再起動します。

```bash
sudo bash setup.sh
sudo systemctl restart jupyterhub
```

本番サーバーだけの上書き設定を Git 管理から外したい場合は、`/opt/lab-server/config/jupyterhub.env` で `LAB_SERVER_CONFIG=/opt/lab-server/config/lab-server.local.toml` のように指定できます。`config/*.local.toml` と `config/jupyterhub.env` は Git 管理しません。

## Slurm 設定の修正場所

Slurm の partition 名や GPU の GRES 名は環境ごとに異なります。必ず [config/lab-server.toml](config/lab-server.toml) の `[[profiles]]` を本番環境に合わせて修正してください。

- `partition`: CPU/GPU 用 partition 名。空文字 `""` の場合は Slurm の default partition を使う
- `gres`: GPU の GRES 指定。例: `gpu:1`
- `options`: account や QoS など、追加で必要な Slurm オプション。例: `["--account=<account>", "--qos=<qos>"]`
- `cpus`: 割り当てる CPU 数
- `memory`: 割り当てるメモリ量

このリポジトリではユーザーが実行時間を選ぶプロファイルは用意していません。Slurm 側に `DefaultTime` や `MaxTime` が設定されている場合は、その制限が適用されます。実行時間制限を設けない方針にする場合は、JupyterHub ではなく Slurm の partition 設定も確認してください。

## 単一ノードと複数ノード

1台の GPU サーバー上で Slurm job も JupyterHub も動く単一ノード構成なら、このリポジトリの初期設定に近い形で動きます。

複数ノードの Slurm クラスタでは追加確認が必要です。

- compute node から `/opt/lab-server/venv/bin/jupyterhub-singleuser` が見えること
- compute node から user home と `~/.venvs/jupyter-default` が見えること
- JupyterHub/Nginx が動く login node から compute node 上の single-user server port へ接続できること
- compute node から JupyterHub internal API へ接続できること

複数ノードで Hub API を localhost のままにすると、compute node から `127.0.0.1:8081` を見に行って失敗します。その場合は `/opt/lab-server/config/jupyterhub.env` を作り、login node の private IP を設定してください。

```bash
sudo cp /opt/lab-server/config/jupyterhub.env.example /opt/lab-server/config/jupyterhub.env
sudo editor /opt/lab-server/config/jupyterhub.env
sudo systemctl restart jupyterhub
```

例:

```text
LAB_SERVER_JUPYTERHUB_HUB_BIND_URL=http://10.0.0.10:8081
LAB_SERVER_JUPYTERHUB_HUB_CONNECT_URL=http://10.0.0.10:8081
```

この `8081` は外部ユーザー向けではなく、compute node から Hub API へ戻るための内部通信です。大学 VPN の外へ公開せず、可能ならクラスタ内部ネットワークだけに制限してください。

## Python 環境

JupyterHub 本体と JupyterLab server は、管理用の `/opt/lab-server/venv` で動かします。この venv は全ユーザーに影響するため、研究用パッケージを直接追加する場所ではありません。

各ユーザーの Notebook kernel と Terminal 用には、初回起動時に次の venv を自動作成します。

```text
~/.venvs/jupyter-default
```

JupyterLab Terminal ではこの venv の `bin/` を PATH の先頭に追加するため、通常は次のようになります。

```bash
which python
# /home/<user>/.venvs/jupyter-default/bin/python
```

ユーザーの `.zshrc` や `.bashrc` が PATH を上書きしても user venv が先頭に戻るように、JupyterLab Terminal は `/opt/lab-server/bin/jupyter-terminal-shell` 経由で起動します。この wrapper は通常の shell 設定を読んだ後、`~/.venvs/jupyter-default/bin` を PATH の先頭へ戻します。

zsh を使っている場合、この wrapper は Powerlevel10k の instant prompt warning を quiet にし、completion cache を `~/.config/lab-server/zsh/` 配下の lab 専用ファイルに分けます。通常のログイン shell の設定ファイルは変更しません。

標準の `python3` kernelspec もこの user venv を指すように登録します。そのため、Notebook から実際の Python を確認すると、通常は user venv が表示されます。

```python
import sys
print(sys.executable)
```

この user venv は軽量に作成し、`ipykernel` など Jupyter kernel の起動に必要な共通パッケージは `/opt/lab-server/venv` を fallback として参照します。研究ごとに完全に分けたい場合は、各プロジェクトで別の venv を作って kernel 登録してください。

```bash
cd ~/my-project
python3 -m venv .venv
source .venv/bin/activate
pip install ipykernel
python -m ipykernel install --user --name my-project --display-name "Python (my-project)"
```

## 管理ユーザー

[config/lab-server.toml](config/lab-server.toml) の `YOUR_ADMIN_USER` は placeholder です。本番環境では管理者の Linux ユーザー名に置き換えてください。

```toml
admin_users = ["YOUR_ADMIN_USER"]
```

## 起動・停止・ログ

```bash
sudo systemctl start jupyterhub
sudo systemctl status jupyterhub --no-pager
sudo systemctl status nginx --no-pager
sudo bash scripts/restart.sh
sudo bash scripts/stop.sh
sudo bash scripts/logs.sh
```

`setup.sh` は、実行元が `/opt/lab-server` でない場合でも、現在のリポジトリ内容を `/opt/lab-server` に同期してからセットアップします。`venv/`, `logs/`, `state/`, `.git/`, `__pycache__/` は同期対象から外します。

その後、`systemd/jupyterhub.service` を `/etc/systemd/system/jupyterhub.service` に symlink し、`systemctl enable jupyterhub` を実行します。再起動後も自動起動させたい場合は、この状態で問題ありません。

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

### HTTPS で開けない

```bash
sudo nginx -t
sudo systemctl status nginx --no-pager
sudo journalctl -u nginx -n 100 --no-pager
curl -k https://<server-hostname-or-ip>/
```

Nginx は `https://<server-hostname>/` を受け、内部で `http://127.0.0.1:8000` へ proxy します。`http://<server-hostname>:8000` を外部から開ける構成にする必要はありません。

### ログインできない

- サーバー上に対象ユーザーが存在するか確認してください。
- PAM 認証でログインできるパスワードが設定されているか確認してください。
- 必要に応じて `/etc/pam.d/` 側の設定を確認してください。

### JupyterLab サーバーが起動待ちのままになる

- `squeue` で Slurm ジョブが待機していないか確認してください。
- `sinfo` で partition が利用可能か確認してください。
- `sbatch: error: invalid partition specified: cpu` のようなエラーが出る場合は、`config/lab-server.toml` の `partition` が実環境に存在しない名前です。空文字 `""` にするか、`sinfo` に出る実際の partition 名へ変更してください。
- GPU profile の `gres = "gpu:1"` が実環境の GRES 名と一致しているか確認してください。
- `sbatch: error: Memory specification can not be satisfied` が出る場合は、GPU profile の `memory` が対象ノードで満たせない値です。`sinfo -o "%P %G %c %m %D %N"` で node memory を確認し、`memory` を下げてください。

### Redirect loop detected が出る

`journalctl` の request header に `"Host": "127.0.0.1:8081"` が出ている場合は、JupyterHub の内部 port を直接開いています。`8081` は Hub 内部 API 用で、single-user server への routing は configurable-http-proxy が担当します。

ブラウザの URL を次に変更してください。

```text
https://<server-hostname>/
```

ローカルで JupyterHub だけを試す場合は `http://127.0.0.1:8000` を使い、`http://127.0.0.1:8081` は使わないでください。

### GPU が見えない

```bash
nvidia-smi
sinfo
srun --gres=gpu:1 --cpus-per-task=4 --mem=8G --pty bash -lc 'hostname; echo $CUDA_VISIBLE_DEVICES; nvidia-smi'
```

partition が必要な場合は `srun` に `-p <partition>` を追加してください。Slurm の GRES 設定が `gpu` 以外の名前を使っている場合は、`--gres=<name>:1` に修正してください。

JupyterLab Terminal で `nvidia-smi: command not found` になる場合は、Slurm job 内の PATH に NVIDIA utility の場所が入っていません。WSL では `nvidia-smi` が `/usr/lib/wsl/lib/nvidia-smi` にあることがあります。通常の Ubuntu サーバーでは NVIDIA driver / utility package が compute node 側に入っているか確認してください。

このリポジトリは `/opt/lab-server/bin/nvidia-smi` に wrapper を置き、`/usr/bin`, `/usr/local/cuda/bin`, `/usr/lib/wsl/lib` などを順に探します。`setup.sh` は、本物の `nvidia-smi` が PATH 上にない場合だけ `/usr/local/bin/nvidia-smi` からこの wrapper への symlink も作成します。設定変更後は既存の JupyterLab server を止めてから GPU profile で起動し直してください。JupyterHub 本体を restart しても、既に起動済みの Slurm job は古い環境のまま残ることがあります。

ログイン shell の `mdy` で `nvidia-smi` が使えても、JupyterLab Terminal で同じとは限りません。JupyterLab は systemd の JupyterHub から Slurm job として起動されるため、SSH/VS Code/zsh のログイン時に作られる環境とは PATH が異なります。この設定では `#SBATCH --get-user-env=L` と明示的な PATH 追加で、できるだけログイン環境に近づけています。

`code .` は VS Code が提供するローカル開発用 CLI です。JupyterHub の Slurm job 内や headless サーバー上で使えるとは限りません。JupyterLab では左側の file browser を使うか、VS Code を使う場合は自分の開発端末または Remote SSH 接続側で `code .` を実行してください。

### データベースや secret を Git 管理したくない

`state/`, `logs/`, `venv/`, cookie secret、SQLite DB は `.gitignore` で除外しています。`state/.gitkeep` と `logs/.gitkeep` だけを Git に残します。
