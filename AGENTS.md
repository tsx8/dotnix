# AGENTS.md

本文件是给 AI 编码代理与贡献者的常驻指令，说明本 NixOS 配置仓库的维护规范。先读 [README.md](README.md) 了解安装流程与仓库全貌。

## 仓库定位

- 单机 NixOS 配置，flake 管理；`nixosConfigurations` 是系统的唯一入口，所有配置最终由 `flake.nix` 组织。
- 仓库处于活跃开发状态：允许破坏性变更，无需兼容历史版本；但破坏性变更（重构、删除、改名、行为变化）必须在提交信息中说明动机与影响。

## 配置原则

- 软件来源优先级：默认 `官方 flake > nixpkgs-unstable > 第三方/自建 flake`。例外——当 nixpkgs-unstable 已满足版本与配置需求、且软件无官方集成诉求时（典型：简单 CLI 工具，如 just），取 `nixpkgs-unstable > 官方 flake > 第三方/自建 flake`。
- 注释极简：只写该配置项基于需求背景所做的决策及原因，不写代码显而易见的行为；非常规、易被误改的配置必须注明原因。
- 应用层级：应用只有系统级与项目级两级——系统级由 NixOS 管理（`configuration.nix`），项目级由各项目 devShell 管理，不存在用户级应用；用户级配置（dotfiles、编辑器设置、凭据等）由 Home Manager 管理，Home Manager 不管理应用。
- flake 输入的 nixpkgs 跟随：默认 inputs.X.nixpkgs.follows = "nixpkgs"，共享一份 nixpkgs，避免重复实例与重复构建；当上游明确要求不 follow（如 home-manager 发行分支须与 nixpkgs 发行分支配对）、或需要其锁定 nixpkgs 的构建产物与二进制缓存时，不 follow，并在 flake.nix 中注明原因。每次 nix flake update 后复查上游要求。

## 常用命令

仓库使用 just 管理日常运维命令，使用 `just --list` 查看所有常用命令。

For AI Agents：禁止自动使用 `just os switch` 及其对应的 `nixos-rebuild` 命令，除非得到用户提前的明确的许可。禁止自动使用 `just secret edit` 及其对应的 sops 相关命令查看或修改 secrets。

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
- 模块沿用现有扁平组织；新增较大子系统时拆成独立 `.nix` 模块再 import。

## 维护本文件

- 只收录几乎每个会话都需要的通用规范；不重复代码已表达的内容，指向权威文件（README、脚本、justfile）。
- 优先改写、精简旧条目，而不是追加新条目。
- 学到新的维护教训（新工具、新坑）时，把它追加进来。
