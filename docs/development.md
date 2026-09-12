# 日常开发与验证

## 项目环境

交互终端进入项目后，direnv 加载已授权的 `.envrc`。首次使用或修改 `.envrc` 后，先审阅内容再执行 `direnv allow`。项目环境成功加载后可直接运行 `just` 等项目命令。

Codex 使用非登录 Bash；`BASH_ENV` 指向系统生成的 `/etc/codex/bash-env`，每次命令按工作目录检查 direnv 授权、校验 `.envrc` 语法并加载环境。初始化不会自动授权 `.envrc`，未授权、已拒绝或 direnv 报告加载失败时，项目命令不会执行。当前目录及其父目录都没有 `.envrc` 时，普通命令正常执行；新的 Bash 启动于项目之外时，会卸载继承的 direnv 环境。

以环境加载结果和项目工具是否可用判断入口是否生效，不只看 `BASH_ENV` 或 `IN_NIX_SHELL` 变量；已有成功结果无需每次重复探测。自动入口配置变更需应用系统并重启 Codex。未配置自动入口的会话中，每次项目命令使用显式入口，例如：

```bash
nix develop --no-update-lock-file --no-write-lock-file --command just repo lint
```

检测到 `.envrc` 未授权或加载失败时，先解决该状态，不用显式入口绕过。非登录 `/bin/sh` 不读取 `BASH_ENV`，可用于诊断和修复初始化，不应据此跳过项目环境继续检查。

`--command` 只影响本次子进程，不会为下一次独立命令保留环境。Bash 启动后在同一条命令中跨项目 `cd` 不会重新加载环境，应直接指定目标工作目录，或使用 `direnv exec <目录> <命令>`。

本项目 `.envrc` 启用 `strict_env`，并在 `use flake` 前禁止 nix-direnv 回退；环境求值失败时停止，加载不更新或写入 `flake.lock`。其他项目的 `.envrc` 若自行忽略错误，初始化入口无法将其识别为失败。需要更新输入时执行 `just repo update`。

环境缓存失效时由 direnv 重新求值；加载环境不自动 fmt、lint、test、update 或应用系统。仓库为 Codex 声明 `sandbox_mode = "danger-full-access"`、`approval_policy = "never"`，配置需应用系统并重启 Codex 后生效。执行以当前会话实际权限为准；完全访问权限不取消 `.envrc` 授权、MCP 工具审批和项目操作边界。权限受阻时按当前环境允许的方式处理，不假定可以申请提权。

`modules/maintenance/` 是项目开发环境的模块边界；影响 devShell 的模块定义放在此目录。`.envrc` 监视该目录及开发环境依赖的本地工具源码 `packages/mcp-dotnix/` 下所有文件和目录，覆盖内容修改及文件增删；nix-direnv 同时监视 flake 入口与锁文件。其他项目内容的修改不触发环境刷新。新增开发环境的本地源码依赖时同步更新监视范围。新增 flake 可见文件先精确 `git add`，避免 Nix 与基于 Git 文件清单的检查漏掉文件。

## 常用命令

| 命令 | 执行内容与副作用 |
| --- | --- |
| `just repo fmt` | 用 nixfmt-tree 格式化 Nix 文件，修改工作树 |
| `just repo lint` | 依次运行 nixfmt 检查、nixf-diagnose、statix、ShellCheck 和 Git 空白检查 |
| `just repo test` | 运行 `nix flake check`，构建已声明 checks，不使用 `--no-build`，不激活系统 |
| `just os build` | 先运行 repo lint、repo test，再构建系统，不激活 |
| `just os test` | 先运行 repo lint、repo test，再构建并经确认激活系统，不改变默认启动项；由用户执行 |
| `just os switch [label]` | 经 `scripts/sh/os.sh` 构建并经确认激活系统、切换默认启动项，不自动运行 lint/test；由用户执行 |
| `just repo update [输入名…]` | 依次更新 flake 输入、同步模型目录、运行 lint、test；不传输入名则更新全部输入 |

`os switch` 切换前须有当前内容的适用检查结果；已通过 `os build` 且相关内容未变化时复用。`repo update` 指定单个输入时也会同步模型目录；任一步失败会停止后续步骤，已经完成的输入更新或模型目录修改不会回滚，详见 [Codex 模型目录](#codex-模型目录)。

三个 os 命令均调用项目 nh，目标显式为 `.#maco`，并禁止更新/写入 lock。构建至少预留 10 分钟。`just repo test` 不构建每个 package；`test` 不等于 `build`，`build` 不证明系统运行正常。

## 验证要求

按实际影响选择验证，不能只按文件扩展名判断。被程序读取的文本、模型数据和环境配置属于行为修改；仅文档中的常驻指令和命令示例也须检查执行流程是否自洽。

| 改动影响 | 必需验证 |
| --- | --- |
| 讨论、设计、只读调查 | 取得支持结论的证据，不要求格式化或构建 |
| 仅文档和常驻指令 | 核对内容、授权边界、命令调用链、路径及链接，运行 `git diff --check HEAD`；需要时做命令静态检查或 dry-run，不执行破坏性示例 |
| 开发环境、脚本、工具、本地包等可执行行为 | `just repo fmt`、`just repo lint`、`just repo test`，并验证成功及必要失败路径；变更包须定向构建，不能用 flake check 代替 |
| 系统配置或影响系统的依赖 | `just repo fmt` 后运行 `just os build`，复用其内置 lint/test，并补足构建未覆盖的必要行为验证 |

同时影响系统的开发工具、脚本或包走系统验证流程，并补足该对象的定向验证；已被系统构建覆盖的包无需重复构建。相同内容且条件仍适用的结果可复用，新修改、失败或证据缺口才补充检查。

系统安装、激活、回滚、重启、秘密操作和 push 由用户执行。运行结论需要实际观察，Agent 可用只读诊断取证；仓库声明、当前激活系统、启动系统和会话工具可用性不能互相替代。系统链接不同本身不足以判断必须重启。按任务所需取证，已有适用证据无需重复全量诊断；报告须区分已完成检查、构建结果和未验证的运行行为。

## Codex 模型目录

`just repo update` 在 flake 输入更新成功后同步当前 ChatGPT 账号的远端模型目录；传入指定输入名时也会同步。同步失败则停止后续检查，已经完成的 flake 输入更新不会回滚。也可单独运行 `scripts/sh/sync-models.sh`。脚本优先使用 PATH 中的 Codex，找不到时使用已安装 ChatGPT 桌面包内置的 CLI；通过 bubblewrap 在独立挂载视图中屏蔽普通配置并使用临时缓存。脚本不直接读取凭据内容，不修改现有 Codex 配置或缓存。需已有 ChatGPT 登录和模型缓存文件。

同步保留 Astra、Sol、Terra、Luna、GPT-5.5 的长上下文覆盖，其他模型采用上游值。刷新失败、目标模型缺失或目录校验失败时保留原文件。成功后审阅 `git diff HEAD -- modules/personal/applications/codex/models.json`，按系统配置变更流程检查、构建和应用；脚本不自动暂存或应用系统。

## Codex 子代理 PoC

系统配置由 `modules/personal/applications/codex/default.nix` 生成 `/etc/codex/config.toml` 和 `/etc/codex/models.json`。Home Manager 将 `modules/personal/applications/codex/agents/` 整个目录链接到 `~/.codex/agents/`；其中的角色文件设置模型、推理强度和职责，provider 与模型目录继承主代理配置。

更新模块后由用户应用系统配置并重启 Codex；新会话才读取新的配置和角色文件。需验证原生派发中的角色选择、模型与推理强度及结果回传，系统构建成功不能替代这项运行验证。

## 工作树 label

`just os switch` 未传入非空 label 时，用 `scripts/sh/worktree-label.sh` 计算当前工作树 Git tree hash 前 12 位。该结果包含已跟踪文件的当前内容、删除、模式与符号链接变化以及未忽略的新文件，忽略的未跟踪文件不参与。脚本使用临时 index，不改变真实暂存区和工作树。操作期间不要并行修改仓库。

## 临时验证与清理

配置行为修改按改动面和证据缺口选择临时验证，可使用临时目录、独立测试仓库、命令替身或协议调用，执行成功路径和必要失败路径。审查结果后清理本次不再需要的临时产物，在交付说明中报告证据和未验证项。不保留固定行为测试套件、临时测试框架或报告目录。仓库只保留服务自身需要的源代码。

## MCP

- 项目环境提供两个独立的 MCP 命令，各自使用包内的 Python 依赖；命令包装避免将应用依赖传播到整个 shell，并清除继承的 `PYTHONPATH`。

- 首次使用前可预构建；服务已可用时无需重复：

```bash
nix build --no-link --no-update-lock-file --no-write-lock-file .#mcp-dotnix .#mcp-nixos
```

- Codex 首次打开项目时确认项目信任；项目配置 `.codex/config.toml` 声明两个 MCP，启动命令是仓库根下的 `scripts/sh/mcp.sh`。
- 调用审批以工具配置、当前权限和有效批准为准。诊断摘要等工具配置为 auto，日志和 mcp-nixos 默认 prompt；不要把默认值当作所有工具都需重新确认。
- 启动失败时检查：包是否可构建、Nix daemon 是否可用、`scripts/sh/mcp.sh` 是否能解析 Git 根。`required = false`，服务器不可用时 Codex 会报告，Agent 不应编造查询结果。
