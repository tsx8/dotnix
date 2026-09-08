# AGENTS.md

本文件是给 AI 编码代理与贡献者的常驻指令。安装步骤见 [docs/install.md](docs/install.md)，开发与验证见 [docs/development.md](docs/development.md)，设计决策见 [docs/design.md](docs/design.md)。

## 仓库定位

- 单机 NixOS 配置，flake 管理；`nixosConfigurations` 是系统的唯一入口，所有配置最终由 `flake.nix` 组织。
- 仓库处于活跃开发状态：允许破坏性变更，无需兼容历史版本；破坏性变更（重构、删除、改名、行为变化）必须在提交信息中说明动机与影响。

## 配置原则

- 软件来源优先级：默认 `官方 flake > nixpkgs-unstable > 第三方/自建 flake`。例外——当 nixpkgs-unstable 已满足版本与配置需求、且软件无官方集成诉求时（典型：简单 CLI 工具，如 just），取 `nixpkgs-unstable > 官方 flake > 第三方/自建 flake`。
- 注释极简：只写该配置项基于需求背景所做的决策及原因；非常规、易被误改的配置必须注明原因。
- 应用层级：应用只有系统级与项目级两级——系统级由 NixOS 管理（`modules/` 中的系统配置），项目级由项目 flake/devShell 管理，不存在用户级应用；用户级配置（dotfiles、编辑器设置、凭据等）由 Home Manager 管理，Home Manager 不管理应用。
- flake 输入的 nixpkgs 跟随：默认 `inputs.X.nixpkgs.follows = "nixpkgs"`；当上游明确要求不 follow、或需要其锁定 nixpkgs 的构建产物与二进制缓存时才例外，并在 `flake.nix` 注明原因。

## 项目环境

- Codex 使用非登录 Bash，通过 `BASH_ENV` 按每次命令的工作目录加载 direnv 环境；`.envrc` 必须已授权，当前及父目录都没有 `.envrc` 时使用普通环境，未授权或加载失败时停止执行。
- 已成功加载项目环境时直接运行项目命令；未配置自动入口的会话使用 [显式 devShell 入口](docs/development.md#项目环境)。检测到未授权或加载失败时先解决环境问题，不改用其他入口绕过。
- 项目环境供应 just、nh、Nix 格式与静态检查工具和两个 MCP 包；不复制系统通用工具。
- 环境加载不自动 fmt、lint、test、update 或应用系统。初始化失败时可用非登录 `/bin/sh` 执行环境诊断；不静默跳过项目环境继续验证。

## 标准流程

1. 阅读本文件和 docs 中与改动相关的部分。
2. 修改相关文件，保留无关工作区和暂存内容；执行项目工具时使用上述环境入口。新增 flake 可见文件先精确 `git add`，不能全量暂存无关变更。
3. 按 [验证要求](docs/development.md#验证要求) 选择检查：仅文档核对内容、命令、链接及差异；可执行行为修改运行 fmt、lint、test 并补足行为验证；影响系统时运行 fmt、os build，复用 build 内置的 lint/test。变更包须验证其构建，不能用 flake check 代替。
4. 复用内容及条件仍适用的验证结果；新修改、失败或证据缺口才补充检查。清理本次不再需要的临时产物，在交接中报告修改、实际验证和未验证项。
5. 输出交接报告后停止。系统应用、回滚、重启、安装、秘密操作和 push 由用户执行。

讨论和只读调查不要求格式化或构建。验证按实际影响选择，不能只按文件扩展名判断；常驻指令和命令示例须检查执行流程是否自洽。构建成功不证明系统运行正常。

## MCP

- `mcp-dotnix`：只读 NixOS 诊断，固定工具、严格参数、不执行 shell、不提权，日志尽力脱敏；失败如实报告。
- `mcp-nixos`：需要查询 Nix 软件包、版本、选项、flake 输入或相关文档时，先使用该 MCP。核对本仓库锁定版本时，使用 `nix` 工具的 `flake-inputs` 操作指定本仓库目录，定位并读取输入源码；已知 store 路径时使用 `store` 操作读取。在线渠道结果不能替代锁定源码证据。已有充分且适用的证据可复用；上述查询仅在工具不可用、查询失败或能力不覆盖时，改用其他途径补充，并说明缺口。本地配置读取、求值、测试与构建仍按项目流程执行。
- MCP 调用遵守工具配置、当前权限和有效批准；逐工具审批有例外，不要求对已有批准重复确认。
- Agent 不读取、解密或修改 secrets；不伪造通过状态。

## 执行环境

- Codex sandbox 可能阻止 Nix daemon Unix socket；需要时按审批在 sandbox 外运行 just 标准命令，不得开启全局网络绕过。
- Nix cache 环境变量重定向缓存目录时，先更新 Codex writable root，再运行验证命令。
- 约束由流程和授权约束行为；AGENTS.md 和 just 本身不能阻止绕过流程的任意终端命令。
