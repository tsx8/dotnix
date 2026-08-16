# AGENTS.md

本文件是给 AI 编码代理与贡献者的常驻指令，说明本 NixOS 配置仓库的维护规范。先读 [README.md](README.md) 了解安装流程与仓库全貌。

## 仓库定位

- 单机 NixOS 配置，flake 管理；`nixosConfigurations` 是系统的唯一入口，所有配置最终由 `flake.nix` 组织。
- 仓库处于活跃开发状态：允许破坏性变更，无需兼容历史版本；但破坏性变更（重构、删除、改名、行为变化）必须在提交信息中说明动机与影响。
- 本文件只收录通用的维护规范，不预先固化具体配置决策；具体决策的理由记录在代码注释与提交信息中。

## 常用命令

仓库使用 just 管理日常运维命令，使用 `just --list` 查看所有常用命令。

## 验证规则

- 提交前必须通过 `just repo check`。
- 系统级变更先 `just os build` 验证可构建，再 `switch` 应用。
- `nixos-rebuild` 构建可能耗时很长，执行时使用不少于 10 分钟的超时。
- **flake 只看到 VCS 跟踪的文件**：新增文件后直接 eval/build 会报 `Path ... is not tracked by Git`，先 `git add`（或提交）再验证。
- 提交前运行 `just repo fmt` 统一格式。

## Secrets 与敏感文件

- 私钥与解密后的 secret 绝不提交到仓库，也不写入任何仓库内文件；仓库只保存密文（`secrets.yaml`、`recovery-key.age`）。
- 修改 secret 一律通过 `just secrets edit`，不要手工编辑密文。
- 机器私钥只存在于系统本地（`/var/lib/sops-nix/key.txt`），不要复制进仓库目录。
- 机器相关文件（`facter.json`、`disk-device.nix`、`.sops.yaml`、`secrets.yaml`）由安装脚本生成或按 README 流程维护；改动它们时在提交信息中说明原因。
- `scripts/` 中的安装脚本有破坏性副作用（清盘、重装），仅用于全新安装流程，日常维护不要运行。

## Nix 代码风格

- 统一使用 `nix fmt`（nixfmt-tree）格式化，不手工对齐。
- 包列表沿用 `with pkgs; [...]`。
- 层次职责保持清晰：应用与服务归 NixOS（`configuration.nix`），用户级配置归 home-manager（`home.nix`），项目工具归各自 devShell。
- 模块沿用现有扁平组织；新增较大子系统时拆成独立 `.nix` 模块再 import。
- 新增 flake 输入前确认必要性，并保持 `inputs.nixpkgs.follows = "nixpkgs"` 一致。

## 维护本文件

- 只收录几乎每个会话都需要的通用规范；不重复代码已表达的内容，指向权威文件（README、脚本、justfile）。
- 优先改写、精简旧条目，而不是追加新条目。
- 学到新的维护教训（新工具、新坑）时，把它追加进来。
