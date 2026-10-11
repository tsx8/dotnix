# 安装

使用官方 NixOS x86_64 图形安装 ISO，以 UEFI 模式启动。进入 Live 桌面后连接可正常访问互联网的网络，打开终端执行下列步骤。

安装前准备好恢复口令和现有 `tsxb` 账户密码，并确保恢复口令不只保存在即将清空的目标磁盘上。恢复口令用于初始化机器密钥，账户密码用于安装后的首次登录。

Live 阶段以默认的 `nixos` 用户克隆仓库并运行脚本。该用户可免密使用 `sudo`，脚本内部会对必要操作提权，无需在脚本外层加 `sudo`。安装介质已提供 Git 和 Nix；脚本自行通过 flake 获取安装工具，无需先加载项目 devShell。安装、秘密操作和系统激活须经用户明确批准，获批后可由 Agent 执行；授权范围及其他操作遵循 [操作边界](../AGENTS.md#操作边界)。

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

在 `modules/machine/storage/layout.data.nix` 中核对设备的 by-id 路径和布局：`disk.system` 必需，`disk.data` 可选。长期单盘系统移除整个 `disk.data` 声明，不生成冷盘挂载、Home 链接或跨盘备份；已声明的数据盘暂时未连接时，保留原配置，不自动把资料改存到系统盘。

以下操作只清空声明的系统盘，并将目标系统挂载到 `/mnt`；不要求数据盘在场，也不会修改布局文件：

```bash
./scripts/sh/disk.sh system
```

只有需要清空并初始化数据盘时，才单独批准并运行 `./scripts/sh/disk.sh data`。已有数据盘不要执行此命令。数据盘操作使用独立的 `/mnt-data` 挂载根，不卸载 `/mnt` 下的系统安装树；操作根下若混入其他磁盘或非块设备挂载，脚本拒绝继续。每次操作都要求输入所选设备的完整 by-id 路径，并保留 disko 自身的确认。

破坏性操作只能使用上述按角色隔离的入口，不要对完整的 `nixosConfigurations.maco` 运行 disko 的 `destroy,format,mount`。系统安装脚本会核对 `/mnt`、`/mnt/boot`、`/mnt/home`、`/mnt/nix` 的设备与子卷归属，不以“目录已挂载”代替校验。

## 4. 初始化机器密钥

```bash
./scripts/sh/secrets.sh
```

按提示输入恢复口令。脚本会为当前机器生成独立的 age identity，已有机器密钥时复用，并更新 SOPS recipients。新机器私钥写入 `/mnt/var/lib/sops-nix/key.txt`；此步骤不会更改账户密码。

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

这里沿用纯 Git 安装引导，检查基线由检查入口内部取 HEAD，提交后自动前进。确认以下机器相关文件的修改；磁盘布局由安装前明确编辑，不由分区脚本改写：

```text
modules/machine/host/facter.json
modules/machine/storage/layout.data.nix
modules/machine/identity/.sops.yaml
modules/machine/identity/secrets.yaml
```

安装脚本已从本仓库 flake 安装系统，其中声明了 direnv/nix-direnv。首次进入项目时，审阅 `.envrc` 后授权并加载项目工具：

```bash
direnv allow
```

未配置自动入口的会话使用 [显式 devShell 入口](development.md#项目环境)，每次将所需命令放在 `--command` 后；检测到未授权或加载失败时先解决环境问题。无需为取得项目工具再次应用系统。

如需编辑秘密，先取得用户明确批准：

```bash
just secrets edit
```

机器私钥只保存在 `/var/lib/sops-nix/key.txt`，不要提交到仓库。完成必要编辑后，先让安装生成的新文件进入 Git 文件清单，再按 [验证要求](development.md#验证要求) 检查最终内容：

```bash
git add -N modules/machine/host/facter.json modules/machine/storage/layout.data.nix modules/machine/identity/.sops.yaml modules/machine/identity/secrets.yaml
just repo fmt
just os build
```

`os build` 包含 lint/test，不激活系统。确认最终内容和适用检查无误后，提交安装生成的修改：

```bash
git add modules/machine/host/facter.json modules/machine/storage/layout.data.nix modules/machine/identity/.sops.yaml modules/machine/identity/secrets.yaml
git commit -m "configure maco"
```

推送前需完成 GitHub 身份验证，并具有仓库写入权限。首次使用可运行：

```bash
gh auth login
```

已登录且推送操作获得用户明确批准后：

```bash
git push
```

若相对已安装系统还有需要生效的配置修改，取得用户明确批准后激活：

```bash
just os test
```

需要更改默认启动项时使用 `just os switch`。它不自动运行 lint/test，可复用当前内容已通过的 `os build` 检查结果；相关内容变化后须重新验证。没有需要生效的修改时，无需再次应用系统。安装修改保存且工作树、暂存区干净后，按 [版本管理](development.md#版本管理) 初始化 jj 共存工作区。
