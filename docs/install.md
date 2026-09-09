# 安装

使用官方 NixOS x86_64 图形安装 ISO，以 UEFI 模式启动。进入 Live 桌面后连接可正常访问互联网的网络，打开终端执行下列步骤。

安装前准备好恢复口令和现有 `tsxb` 账户密码，并确保恢复口令不只保存在即将清空的目标磁盘上。恢复口令用于初始化机器密钥，账户密码用于安装后的首次登录。

Live 阶段以默认的 `nixos` 用户克隆仓库并运行脚本。该用户可免密使用 `sudo`，脚本内部会对必要操作提权，无需在脚本外层加 `sudo`。安装介质已提供 Git 和 Nix；脚本自行通过 flake 获取安装工具，无需先加载项目 devShell。安装、秘密操作和系统激活由用户执行。

## 1. 获取配置

```bash
git clone https://github.com/tsx8/dotnix.git
cd dotnix
```

## 2. 生成硬件报告

```bash
./scripts/sh/facter.sh
```

## 3. 分区并挂载

先确认目标磁盘：

```bash
lsblk
ls -l /dev/disk/by-id/
```

将 `<target-disk>` 替换为目标磁盘的实际标识。以下操作会清空该磁盘，并将目标系统挂载到 `/mnt`：

```bash
./scripts/sh/disk.sh /dev/disk/by-id/<target-disk>
```

## 4. 初始化机器密钥

```bash
./scripts/sh/secrets.sh
```

按提示输入恢复口令。脚本会为当前机器生成独立的 age identity，并更新 SOPS recipients。新机器私钥写入 `/mnt/var/lib/sops-nix/key.txt`；此步骤不会更改账户密码。

## 5. 安装系统

```bash
./scripts/sh/nixos-install.sh
```

## 6. 保存安装期产生的仓库修改

安装成功后仍在 Live 环境中操作，保持当前目录为仓库根目录。将仓库及安装期间的修改复制到目标系统，并将所有权交给已创建的 `tsxb` 用户。完成后再重启，以免丢失 Live 环境中的修改。

```bash
sudo mkdir -p /mnt/home/tsxb/dotnix
sudo cp -a "$(pwd)/." /mnt/home/tsxb/dotnix/
sudo chown -R --reference=/mnt/home/tsxb /mnt/home/tsxb/dotnix
```

然后：

```bash
sudo reboot
```

## 首次启动后

从目标磁盘启动，以 `tsxb` 登录，使用加密配置中 `user-passwd-hash` 对应的现有密码。安装脚本不会提示设置新的 root 密码。

```bash
cd ~/dotnix
git status
```

确认以下机器相关文件的修改：

```text
modules/machine/host/facter.json
modules/machine/storage/disk-device.data.nix
modules/machine/identity/.sops.yaml
modules/machine/identity/secrets.yaml
```

安装脚本已从本仓库 flake 安装系统，其中声明了 direnv/nix-direnv。首次进入项目时，审阅 `.envrc` 后授权并加载项目工具：

```bash
direnv allow
```

未配置自动入口的会话使用 [显式 devShell 入口](development.md#项目环境)，每次将所需命令放在 `--command` 后；检测到未授权或加载失败时先解决环境问题。无需为取得项目工具再次应用系统。

如需编辑秘密，由用户执行：

```bash
just secrets edit
```

机器私钥只保存在 `/var/lib/sops-nix/key.txt`，不要提交到仓库。完成必要编辑后，按 [验证要求](development.md#验证要求) 检查最终内容。系统配置修改执行：

```bash
just repo fmt
just os build
```

`os build` 包含 lint/test，不激活系统。确认最终内容和适用检查无误后，由用户提交安装生成的修改：

```bash
git add modules/machine/host/facter.json modules/machine/storage/disk-device.data.nix modules/machine/identity/.sops.yaml modules/machine/identity/secrets.yaml
git commit -m "configure maco"
```

推送前需完成 GitHub 身份验证，并具有仓库写入权限。首次使用可运行：

```bash
gh auth login
```

已登录后推送：

```bash
git push
```

若相对已安装系统还有需要生效的配置修改，再由用户激活：

```bash
just os test
```

需要更改默认启动项时使用 `just os switch`。它不自动运行 lint/test，可复用当前内容已通过的 `os build` 检查结果；相关内容变化后须重新验证。没有需要生效的修改时，无需再次应用系统。
