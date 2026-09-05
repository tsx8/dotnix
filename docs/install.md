# 安装

使用官方 NixOS 图形安装 ISO 启动，并连接可正常访问互联网的网络。

## 1. 获取配置

```bash
git clone https://github.com/tsx8/dotnix.git
cd dotnix
```

## 2. 生成硬件报告

```bash
./scripts/facter.sh
```

## 3. 分区并挂载

先确认目标磁盘：

```bash
lsblk
ls -l /dev/disk/by-id/
```

然后执行：

```bash
./scripts/disk.sh /dev/disk/by-id/<target-disk>
```

> 此操作会清空目标磁盘。

## 4. 初始化机器密钥

```bash
./scripts/secrets.sh
```

按提示输入恢复口令。脚本会为当前机器生成独立的 age identity，并更新 SOPS recipients。

## 5. 安装系统

```bash
./scripts/nixos-install.sh
```

## 6. 保存安装期产生的仓库修改

不要立即重启。

```bash
sudo cp -a "$(pwd)" /mnt/home/tsxb/dotnix
sudo chown -R --reference=/mnt/home/tsxb /mnt/home/tsxb/dotnix
```

然后：

```bash
sudo reboot
```

## 首次启动后

```bash
cd ~/dotnix
git status
```

确认以下机器相关文件的修改：

```text
facter.json
disk-device.nix
.sops.yaml
secrets.yaml
```

此时系统尚未部署本次仓库声明中的 direnv/nix-direnv 与项目工具（若有），用显式项目环境验证配置：

```bash
nix develop --no-update-lock-file --no-write-lock-file --command bash -lc 'just repo test && just secrets edit'
```

确认无误后提交：

```bash
git add facter.json disk-device.nix .sops.yaml secrets.yaml
git commit -m "configure maco"
git push
```

机器私钥只保存在 `/var/lib/sops-nix/key.txt`，不要提交到仓库。之后用显式项目环境应用系统配置：

```bash
nix develop --no-update-lock-file --no-write-lock-file --command just os test
```

或把 `os test` 换成 `os switch`。系统启用 nix-direnv 后，执行 `direnv allow` 进入项目环境。
