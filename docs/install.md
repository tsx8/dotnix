# 安装

从官方 x86_64 NixOS 图形安装 ISO 以 UEFI 模式启动，连接互联网。在 Live 桌面用 `nixos` 用户运行脚本。脚本自行取得 flake 工具并在必要时调用 sudo，不用先进入 devShell，也不要用 sudo 包住整个脚本。

**擦盘前**先备份要保留的数据。把恢复口令保存在目标盘和仓库之外，并准备好 `tsxb` 现有的账户密码。让代理执行时，[明确批准](../AGENTS.md#操作边界)须覆盖操作及目标。系统盘的擦除许可不包含数据盘、秘密操作、重启或推送。

## 1. 获取配置并生成硬件报告

```bash
git clone https://github.com/tsx8/dotnix.git
cd dotnix
./scripts/sh/facter.sh
```

## 2. 选择磁盘并挂载

```bash
lsblk -o NAME,PATH,SIZE,MODEL,SERIAL,MOUNTPOINTS
ls -l /dev/disk/by-id/
```

把实物磁盘与[布局文件](../modules/machine/storage/layout.data.nix)中的 by-id 对上。`disk.system` 必需。长期单盘使用时移除整个 `disk.data`，这样不生成数据盘挂载、用户链接或跨盘备份。数据盘只是暂时不在场则保留声明，不把数据改存到系统盘。

**下一条命令会清空整个系统盘。** 核对型号、序列号和完整 by-id，确认目标获批后再运行。它把系统挂到 `/mnt`，不要求数据盘在场，不改写布局文件。

```bash
./scripts/sh/disk.sh system
```

只有要**清空并初始化数据盘**且已单独获批时，才运行 `./scripts/sh/disk.sh data`。要保留已有数据就跳过。该命令使用独立的 `/mnt-data`。每次擦盘都要输入完整 by-id 并通过 disko 自身的确认。操作根下若有其他磁盘或非块设备的挂载，脚本会停止。先查明原因。不要改用完整的 `nixosConfigurations.maco` 执行 disko 的 `destroy,format,mount`。

## 3. 核对挂载并初始化机器密钥

```bash
findmnt --submounts --mountpoint /mnt --output TARGET,SOURCE,FSTYPE
```

确认 `/mnt`、`/mnt/home`、`/mnt/nix` 和 `/mnt/boot` 都属于刚选的系统盘，前三者分别使用 `@root`、`@home` 和 `@nix`。不符就停止。

下一步会生成或复用 `/mnt/var/lib/sops-nix/key.txt`，并重写仓库的 SOPS 接收者配置和密文。接收者为恢复身份和当前机器。确认这两项变更已获批准后，在脚本提示时输入恢复口令：

```bash
./scripts/sh/secrets.sh
```

脚本验证两份身份都能解密，不修改账户密码。仓库只保存密文，系统按权限使用解密后的明文。不要把机器私钥或恢复口令复制到仓库。

## 4. 安装系统并保存工作树

获准向目标系统盘安装系统和引导程序后运行。安装脚本会再次校验设备、挂载、子卷和机器密钥。

```bash
./scripts/sh/nixos-install.sh
```

安装成功后，仍在 Live 仓库根目录，将整个工作树及 Git 历史复制到目标系统。先确认 `/mnt/home/tsxb` 已是目标用户的主目录。若目标仓库已存在，先核对，不覆盖。

```bash
sudo mkdir -- /mnt/home/tsxb/dotnix &&
  sudo cp -a -- "$PWD/." /mnt/home/tsxb/dotnix/ &&
  sudo chown -R --reference=/mnt/home/tsxb /mnt/home/tsxb/dotnix
```

复制及所有权设置成功后，获准重启时再运行 `sudo reboot`。否则 Live 环境中的硬件报告和重新加密的文件可能随关机丢失。

## 首次启动后

从目标盘启动，用原有密码登录 `tsxb`。安装器不提示设置新 root 密码。在 `~/dotnix` 运行 `git status --short`，核对硬件报告、手动调整的磁盘布局以及 `modules/machine/identity/` 下的 `.sops.yaml` 和 `secrets.yaml`。

审阅 `.envrc` 后运行 `direnv allow`，按[项目环境](development.md#项目环境)加载工具。确需编辑密文时，先获批再运行 `just secrets edit`。如有本次新增的 flake 文件，先精确 `git add`，然后验证最终内容：

```bash
just repo fmt
just os build
```

只提交本次安装产生且已核对的修改。需要推送时，先确认远端、分支、写入权限及用户批准。若安装后没有新的系统配置改动，无需再次激活；否则按[常用命令](development.md#常用命令)选择经批准的激活方式。
