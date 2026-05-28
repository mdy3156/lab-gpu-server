# Ubuntu 単一ノード GPU サーバー向け Slurm セットアップ

この手順は、NVIDIA GPU を載せた Ubuntu サーバー 1 台に Slurm を追加するためのものです。
JupyterHub は既存の `setup.sh` で構築し、Slurm 本体の導入は明示的に
`scripts/install-slurm-single-node.sh` で行います。

目標はまず小さく、`--gres=gpu:1` で GPU を 1 枚だけ割り当て、cgroup で
CPU、メモリ、device の制限を効かせることです。A100 専用にはせず、
GPU 枚数は `nvidia-smi -L` から検出します。

## Slurm の役割

この構成では、Slurm は JupyterHub ユーザーと共有 GPU サーバーの間に入る
リソース管理役です。JupyterHub は各ユーザーの JupyterLab を Slurm job として
起動し、Slurm が CPU、メモリ、GPU の空き状況を見て job を開始します。

主な構成要素は次です。

- MUNGE: Slurm daemon と Slurm command の認証に使う仕組みです。
- `slurmctld`: Slurm controller です。単一ノード構成では同じサーバー上で動きます。
- `slurmd`: job を実際に起動、監視する worker daemon です。
- GRES: Slurm の Generic Resource です。GPU を `Name=gpu` として登録し、
  `--gres=gpu:1` で要求できるようにします。
- cgroup: Linux のリソース制限機構です。Slurm から CPU core、RAM、device
  visibility を制限します。GPU の見え方を制限するには `ConstrainDevices=yes`
  が重要です。

## パッケージ導入

リポジトリの checkout 上で実行します。このスクリプトは `/etc/slurm/*.conf` を
変更しません。

```bash
sudo bash scripts/install-slurm-single-node.sh
```

このスクリプトが行うこと:

- root 実行を確認
- `apt update`
- `munge`, `slurm-wlm` のインストール
- `munge` の enable/start
- 既存 `/etc/slurm/*.conf` があれば警告
- `nvidia-smi`, `nvidia-smi -L` の表示
- `hostname -s`, `lscpu`, `free -m` の表示
- 最後に設定生成コマンドを案内

## Slurm 設定生成

ハードウェア表示を確認してから、単一ノード用の設定を生成します。

```bash
sudo bash scripts/generate-slurm-config-single-node.sh
```

生成対象:

- `/etc/slurm/slurm.conf`
- `/etc/slurm/gres.conf`
- `/etc/slurm/cgroup.conf`

既存ファイルがある場合は、上書き前にタイムスタンプ付き backup を作ります。

```text
/etc/slurm/slurm.conf.bak-YYYYmmdd-HHMMSS
```

自動検出する値:

- `NodeName`: `hostname -s`
- CPU 数: `nproc --all`
- メモリ MB: `/proc/meminfo` の `MemTotal` の 95%
- GPU 枚数: `nvidia-smi -L`

生成される partition 名は `gpu` です。

```text
PartitionName=gpu Nodes=<hostname> Default=YES MaxTime=INFINITE State=UP
```

node 行には検出した CPU、メモリ、GPU 枚数が入ります。

```text
NodeName=<hostname> CPUs=<detected> RealMemory=<detected> Gres=gpu:<detected_gpu_count> State=UNKNOWN
```

`gres.conf` は GPU ごとに明示的な行を生成します。GPU 3 枚なら次の形です。

```text
NodeName=<hostname> Name=gpu File=/dev/nvidia0
NodeName=<hostname> Name=gpu File=/dev/nvidia1
NodeName=<hostname> Name=gpu File=/dev/nvidia2
```

cgroup 設定では次を有効にします。

```text
ConstrainCores=yes
ConstrainRAMSpace=yes
ConstrainDevices=yes
```

設定生成後、スクリプトは次を実行します。

```bash
systemctl restart munge slurmctld slurmd
sinfo
scontrol show node
```

## 動作確認

基本確認:

```bash
sinfo
sinfo -o "%P %G %c %m %D %N"
scontrol show node
```

GPU isolation の smoke test:

```bash
bash scripts/check-slurm-gpu-isolation.sh
```

この中で実行する主なコマンドは次です。

```bash
srun --gres=gpu:1 --cpus-per-task=4 --mem=8G --pty bash -lc 'hostname; echo $CUDA_VISIBLE_DEVICES; nvidia-smi'
```

job の中で確認する点:

- `CUDA_VISIBLE_DEVICES` が 1 つの device だけを示していること
- cgroup device isolation が効いている場合、job 内の `nvidia-smi` で GPU が
  1 枚だけ見えること

もし job 内から全 GPU が見える場合、GRES の割り当ては動いていても cgroup の
device 制限が効いていない可能性があります。

## JupyterHub 側の設定

Slurm 側で `gpu` partition と `gpu:1` GRES が動くことを確認したら、
`config/lab-server.toml` の GPU profile を合わせます。

```toml
[[profiles]]
display_name = "GPU: 1 GPU, 4 cores, 8 GB memory"
key = "gpu-1-4c-8g"
partition = "gpu"
cpus = "4"
memory = "8G"
gres = "gpu:1"
options = []
```

変更後は `/opt/lab-server` に同期し、JupyterHub を再起動します。

```bash
sudo bash setup.sh
sudo systemctl restart jupyterhub
```

Slurm の package install は `setup.sh` に混ぜないでください。Slurm を明示的な手順に
分けておくことで、既存の Slurm 設定を誤って壊しにくくなります。

## よくあるエラー

### `sinfo` で node が `down`, `drain`, `INVAL` になる

daemon log を確認します。

```bash
sudo journalctl -u slurmctld -u slurmd --no-pager -n 200
sudo systemctl status slurmctld slurmd --no-pager
```

生成時点で `RealMemory` は `MemTotal` の 95% にしています。それでも
`RealMemory` が実際より大きいと node が invalid になることがあります。その場合は
`/etc/slurm/slurm.conf` の `RealMemory` をさらに少し小さくしてから再起動します。

```bash
sudo systemctl restart slurmctld slurmd
```

### `Invalid generic resource`

次を確認してください。

- `/etc/slurm/slurm.conf` に `GresTypes=gpu` がある
- node 行に `Gres=gpu:<count>` がある
- `/etc/slurm/gres.conf` に `Name=gpu` がある

修正後に再起動します。

```bash
sudo systemctl restart slurmctld slurmd
```

### `CUDA_VISIBLE_DEVICES` は設定されるが `nvidia-smi` で全 GPU が見える

cgroup 設定を確認します。

```bash
grep -E 'TaskPlugin|ProctrackType' /etc/slurm/slurm.conf
cat /etc/slurm/cgroup.conf
sudo journalctl -u slurmd --no-pager -n 200
```

`TaskPlugin=task/cgroup`, `ConstrainDevices=yes` があり、cgroup plugin の load error が
出ていないことを確認してください。

### MUNGE authentication error が出る

MUNGE の状態と key を確認します。

```bash
sudo systemctl status munge --no-pager
sudo journalctl -u munge --no-pager -n 100
sudo ls -l /etc/munge/munge.key
```

Ubuntu package では通常 key が作成されますが、サーバー image によっては権限修復が
必要なことがあります。

### Slurm command が見つからない

`slurm-wlm` を明示的に入れてください。

```bash
sudo apt update
sudo apt install -y munge slurm-wlm
```
