# AGENTS.md

本文件是给 AI 编码代理与贡献者的常驻指令。安装步骤见 [docs/install.md](docs/install.md)，开发与验证见 [docs/development.md](docs/development.md)，设计决策见 [docs/design.md](docs/design.md)。

## 仓库定位

- 单机 NixOS 配置，flake 管理；`nixosConfigurations` 是系统的唯一入口，所有配置最终由 `flake.nix` 组织。
- 仓库处于活跃开发状态：允许破坏性变更，无需兼容历史版本；破坏性变更（重构、删除、改名、行为变化）必须在提交信息中说明动机与影响。

## 配置原则

- 软件来源优先级：默认 `官方 flake > nixpkgs-unstable > 第三方/自建 flake`。例外——当 nixpkgs-unstable 已满足版本与配置需求、且软件无官方集成诉求时（典型：简单 CLI 工具，如 just），取 `nixpkgs-unstable > 官方 flake > 第三方/自建 flake`。
- 注释极简：只写该配置项基于需求背景所做的决策及原因；非常规、易被误改的配置必须注明原因。
- 应用层级：应用只有系统级与项目级两级——系统级由 NixOS 管理（`configuration.nix`），项目级由项目 flake/devShell 管理，不存在用户级应用；用户级配置（dotfiles、编辑器设置、凭据等）由 Home Manager 管理，Home Manager 不管理应用。
- flake 输入的 nixpkgs 跟随：默认 `inputs.X.nixpkgs.follows = "nixpkgs"`；当上游明确要求不 follow、或需要其锁定 nixpkgs 的构建产物与二进制缓存时才例外，并在 `flake.nix` 注明原因。

## 项目环境

- 进入方式：在仓库目录 `direnv allow` 后自动加载 `.envrc`；未启用 nix-direnv 时使用 `nix develop --no-update-lock-file --no-write-lock-file --command just --list`。
- 项目环境供应 just、nh、Nix 格式与静态检查工具和两个 MCP 包；不复制系统通用工具。
- 进入环境不自动 fmt、lint、test、update 或应用系统。

## 标准流程

1. 阅读本文件和 docs 中与改动相关的部分。
2. 进入项目环境后修改；新增 flake 可见文件先 `git add` 该文件，不能全量暂存无关变更。
3. 运行 `just repo fmt`，然后 `just repo lint`、`just repo test`。
4. 按改动面创建临时验证（含临时测试仓库、命令替身或协议调用），执行成功路径和必要失败路径，审查结果后清理临时产物，并在交付说明中报告证据。
5. 系统级变更运行 `just os build`；build 入口已内置 lint/test，同一未变化工作树不重复手工执行。
6. 输出交接报告后停止。系统应用、回滚、重启、安装、秘密操作和 push 由用户执行。

`just os switch` 的默认 label 取当前工作树 Git tree hash 前 12 位，包含未暂存修改、删除和新未忽略文件；构建至少预留 10 分钟。`just repo test` 检查 flake 声明并执行已声明 checks，不构建每个 package；`test` 不等于 `build`，`build` 不证明系统运行正常。

## MCP

- `mcp-dotnix`：只读 NixOS 诊断，固定工具、严格参数、不执行 shell、不提权，日志尽力脱敏；失败如实报告。
- `mcp-nixos`：查询 NixOS/nix-darwin 选项与文档；查询会联网或读取 store，两个工具默认询问。不可用或查询失败时不编造结果。
- Agent 不读取、解密或修改 secrets；不伪造通过状态。

## 执行环境

- Codex sandbox 可能阻止 Nix daemon Unix socket；需要时按审批在 sandbox 外运行 just 标准命令，不得开启全局网络绕过。
- Nix cache 环境变量重定向缓存目录时，先更新 Codex writable root，再运行验证命令。
- 约束由流程和授权约束行为；AGENTS.md 和 just 本身不能阻止绕过流程的任意终端命令。
