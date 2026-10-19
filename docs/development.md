# 日常开发与验证

## 项目环境

交互终端进入项目后，direnv 加载已授权的 `.envrc`。首次使用或修改 `.envrc` 后，先审阅内容再执行 `direnv allow`。项目环境成功加载后可直接运行 `just` 等项目命令。

Codex 与系统安装的 `pi` 入口使用非登录 Bash，通过 `BASH_ENV` 在每次命令启动时按工作目录加载环境。Pi 使用默认 Bash 工具；改用其他 `shellPath` 时不保证执行此入口。初始化不会自动授权 `.envrc`，未授权、已拒绝、语法错误或 direnv 报告加载失败时，项目命令不会执行。当前目录及其父目录都没有 `.envrc` 时，普通命令正常执行；新的 Bash 启动于项目之外时，会卸载继承的 direnv 环境。

以环境加载结果和项目工具是否可用判断入口是否生效，不只看 `BASH_ENV` 或 `IN_NIX_SHELL` 变量；已有成功结果无需每次重复探测。自动入口配置变更需应用系统并重启对应代理。未配置自动入口的会话中，每次项目命令使用显式入口，例如：

```bash
nix develop --no-update-lock-file --no-write-lock-file --command just repo lint
```

检测到 `.envrc` 未授权或加载失败时，先解决该状态，不用显式入口绕过。非登录 `/bin/sh` 不读取 `BASH_ENV`，可用于诊断和修复初始化，不应据此跳过项目环境继续检查。

`--command` 只影响本次子进程，不会为下一次独立命令保留环境。Bash 启动后在同一条命令中跨项目 `cd` 不会重新加载环境，应直接指定目标工作目录，或使用 `direnv exec <目录> <命令>`。

本项目环境求值失败时停止，不回退到旧缓存，加载不更新或写入 `flake.lock`。其他项目的 `.envrc` 若自行忽略错误，初始化入口无法将其识别为失败。需要更新输入时执行 `just repo update`。

环境缓存失效时由 direnv 重新求值；加载环境不自动 fmt、lint、test、update 或应用系统。仓库为 Codex 声明 `sandbox_mode = "danger-full-access"`、`approval_policy = "on-request"`、`approvals_reviewer = "user"`，配置需应用系统并重启 Codex 后生效。执行以当前会话实际权限为准；完全访问权限不取消 `.envrc` 授权、提权认证和项目操作边界。权限受阻时按当前环境允许的方式处理，不假定可以申请提权。

影响 devShell 的模块定义放在 `modules/maintenance/`。新增开发环境的本地源码依赖时，同步更新 [.envrc](../.envrc) 的监视范围，使内容修改及文件增删都能触发刷新；普通系统配置与应用数据不触发环境刷新。新增 flake 可见文件先精确 `git add`，避免 Nix 与基于 Git 文件清单的检查漏掉文件。模块装配与环境职责见 [架构设计](design.md)。

## 常用命令

| 命令 | 执行内容与副作用 |
| --- | --- |
| `just repo fmt` | 用 nixfmt-tree 格式化 Nix 文件，修改工作树 |
| `just repo lint` | 依次运行 nixfmt 检查、nixf-diagnose、statix、ShellCheck 和 Git 空白检查 |
| `just repo test` | 运行 `nix flake check`，构建已声明 checks，不使用 `--no-build`，不激活系统 |
| `just os build` | 先运行 repo lint、repo test，再构建系统，不激活 |
| `just os test` | 先运行 repo lint、repo test，再构建并经确认激活系统，不改变默认启动项；须经用户明确批准 |
| `just os switch [label]` | 经 `scripts/sh/os.sh` 构建并经确认激活系统、切换默认启动项，不自动运行 lint/test；须经用户明确批准 |
| `just repo update [输入名…]` | 依次更新 flake 输入、经 `packages/update.list` 用 nix-update 检查登记的包（随后重生成 piliplus 依赖 lock）、同步 WeChat 滚动产物、同步模型目录、运行 lint、test；不传输入名则更新全部输入；逐节点显示状态，编排见 [scripts/sh/update.sh](../scripts/sh/update.sh) |

fmt、lint、test 在检查前拒绝未忽略、未跟踪文件，只列路径，不自动跟踪或删除；将应交付的文件精确 `git add`，临时文件放到仓库外，必要的忽略规则维护在 `.gitignore`。

`os switch` 切换前须有当前内容的适用检查结果；已通过 `os build` 且相关内容未变化时复用。`repo update` 指定单个输入时也会同步模型目录，详见 [Codex 模型目录](#codex-模型目录)；单个节点失败不中断后续节点，网络类节点自动重试一次，已经完成的更新不回滚，失败时保留各节点完整日志并在末尾打印目录；GitHub API 令牌由 sops 渲染的用户级 nix.conf 提供（`modules/machine/identity/secrets.yaml` 的 `gh-auth-token`），避免匿名限额。

纳入仓库的上游应尽量保持可随 `repo update` 滚动更新（flake 输入或 `packages/update.list`）。

三个 os 命令均调用项目 nh，目标显式为 `.#maco`，并禁止更新/写入 lock。构建至少预留 10 分钟。`just repo test` 不构建每个 package；`test` 不等于 `build`，`build` 不证明系统运行正常。

## 验证要求

按实际影响选择验证，不能只按文件扩展名判断。被程序读取的文本、模型数据和环境配置属于行为修改；仅文档中的常驻指令和命令示例也须检查执行流程是否自洽。

修改 Harness 时，按 [文档边界](../AGENTS.md#文档边界) 核对代码、注释和文档：可执行约束是否已有实现，局部理由是否紧邻代码，使用契约和架构说明是否与实现一致。仅局部实现变化不要求补写文档；接口、操作后果或跨组件职责变化时，更新对应说明。

| 改动影响 | 必需验证 |
| --- | --- |
| 讨论、设计、只读调查 | 取得支持结论的证据，不要求格式化或构建 |
| 仅文档和常驻指令 | 核对[内容归属](../AGENTS.md#文档边界)、授权边界、命令调用链、路径及链接，运行 `git diff --check HEAD`；需要时做命令静态检查或 dry-run，不执行破坏性示例 |
| 开发环境、脚本、工具、本地包等可执行行为 | `just repo fmt`、`just repo lint`、`just repo test`，并验证成功及必要失败路径；变更包须定向构建，不能用 flake check 代替 |
| 系统配置或影响系统的依赖 | `just repo fmt` 后运行 `just os build`，复用其内置 lint/test，并补足构建未覆盖的必要行为验证 |

同时影响系统的开发工具、脚本或包走系统验证流程，并补足该对象的定向验证；已被系统构建覆盖的包无需重复构建。相同内容且条件仍适用的结果可复用，新修改、失败或证据缺口才补充检查。

系统安装、激活、回滚、重启、秘密操作和 push 按 [操作边界](../AGENTS.md#操作边界) 取得用户明确批准后，可由 Agent 执行。运行结论需要实际观察，Agent 可用只读诊断取证；仓库声明、当前激活系统、启动系统和会话工具可用性不能互相替代。系统链接不同本身不足以判断必须重启。按任务所需取证，已有适用证据无需重复全量诊断；报告须区分已完成检查、构建结果和未验证的运行行为。

## Codex 模型目录

`just repo update` 同步当前 ChatGPT 账号的远端模型目录；传入指定输入名时也会同步。也可单独运行 [scripts/sh/sync-models.sh](../scripts/sh/sync-models.sh)。需已有 ChatGPT 登录和模型缓存文件，以及 PATH 中的 Codex 或 ChatGPT 桌面包。同步过程不修改现有 Codex 配置、缓存或凭据；认证过期时需由用户在 Codex 中重新登录后重试。

刷新失败、目标模型缺失或目录校验失败时保留原文件。成功后审阅 `git diff HEAD -- modules/agents/codex/models.json`，按系统配置变更流程检查、构建和应用；脚本不自动暂存或应用系统。

## WeChat 滚动产物

`just repo update` 在 pkg-update 后运行 [scripts/sh/update-wechat.sh](../scripts/sh/update-wechat.sh)：以官方下载地址的 Last-Modified 头为变更哨兵，无变化即空操作；有变化时经 nix 通道取权威哈希、从官方页取三位版本号，改写 `packages/wechat/package.nix`。腾讯静默覆盖但哨兵未变时，后续构建会因哈希失配失败，手动运行该脚本即可修复。

## 工作树 label

`just os switch` 未传入非空 label 时，用 [scripts/sh/worktree-label.sh](../scripts/sh/worktree-label.sh) 计算当前工作树 Git tree hash 前 12 位。该结果包含已跟踪文件的当前内容、删除、模式与符号链接变化以及未忽略的新文件，忽略的未跟踪文件不参与。计算不改变真实暂存区和工作树；操作期间不要并行修改仓库。

## 临时验证与清理

配置行为修改按改动面和证据缺口选择临时验证，可使用临时目录、独立测试仓库、命令替身或协议调用，执行成功路径和必要失败路径。审查结果后清理本次不再需要的临时产物，在交付说明中报告证据和未验证项。不保留固定行为测试套件、临时测试框架或报告目录。仓库只保留服务自身需要的源代码。

## MCP

- 项目环境提供 `mcp-dotnix` 和 `mcp-nixos` 两个命令，职责和依赖隔离见 [架构设计](design.md#项目-mcp)。

- 首次使用前可预构建；服务已可用时无需重复：

```bash
nix build --no-link --no-update-lock-file --no-write-lock-file .#mcp-dotnix .#mcp-nixos
```

- Codex 读取用户级 `~/.codex/config.toml` 中的 MCP 配置，两个服务使用系统构建的固定可执行路径，在仓库外也可用。Home Manager 激活时合并声明字段，保留未声明的用户设置及额外服务器；配置保持可写，但 TOML 注释、排版和键顺序可能变化。其他项目仍可通过项目配置覆盖用户配置。
- Pi 内建 MCP 读取全局 `~/.pi/agent/mcp.json`，同样使用系统构建的固定可执行路径。对本仓库声明的服务器，指定工具设为 deferred，可由工具搜索加载或从 codemode 调用，其余工具不可达。交互会话中用 `/mcp` 检查、启停或重连，也可用 `pi mcp list` 检查连接与工具暴露状态。列表仍会显示服务器提供的隐藏工具，是否可调用以暴露状态为准。连接失败不影响基础编码工具。
- Pi 额外接入系统安装的 `mcp-deepseek-search`，提供公开网页搜索与抓取，不限定当前模型。联网 Key 由 sops 管理，通过 `just secrets edit` 维护 `deepseek-search`，与模型 provider 的凭据独立。首次配置或轮换后，应用系统并重启 Pi；不要将明文 Key 写入 `mcp.json`。
- `mcp-deepseek-search` 连接成功不证明远端认证有效。查询、原始问题、可选定位 IP 和目标 URL 会发送给 DeepSeek，结果及计费规则见 [Search & Fetch 官方指南](https://api-docs.deepseek.com/guides/search)。调用失败不自动重试；不使用本地浏览器登录态。
- Pi 全局 MCP 文件可由 `/mcp` 回写；系统激活重申声明的启动与暴露配置，保留未声明字段（包括启用状态）及额外服务器。项目 `.pi/mcp.json` 的同名条目可以覆盖全局配置。
- Codex 中两个 MCP 默认采用 `auto`；只读诊断（含日志）和 mcp-nixos 查询直接调用。`run_privileged` 单独配置为 `approve`，由 polkit 认证，不再经过客户端审批；`auto` 仍会依据危险性标注要求审批。执行仍须遵守当前权限和项目操作边界。
- `run_privileged(program, args, cwd, reason, impact)` 在执行 root 命令前要求 KDE 标准 polkit 认证，每次调用独立认证，不保留授权。程序与目录须为绝对路径，参数按数组传递，不展开 shell 语法。`reason` 和 `impact` 说明提权原因、影响对象与预期变化，不另行定制认证窗口。密码由系统认证代理处理，MCP 不接收密码。同账户其他程序也可向固定入口发起认证请求。命令环境由 pkexec 过滤，入口设置系统 PATH，stdin 关闭；输出每路最多返回 32 KiB，并尽力脱敏。
- 取消、拒绝或认证失败时不执行目标命令；没有可用的桌面认证代理时失败，不转入终端认证，也不回退到 sudo。失败按实际退出码和错误输出报告，不自动重试。
- 应用前备份两个客户端的可写 MCP 配置，再运行 `just os switch`，重启或重连客户端。入口内容或其 Bash 依赖变化后，需重新应用系统以更新授权规则中的路径。回退时须同时恢复用户配置，系统 generation 回滚不能撤销已合并的配置。
- `mcp-dotnix` 的调用超时为 600 秒；Pi 的 `mcp-nixos` 请求超时为 120 秒，包含连接初始化。客户端取消或超时不保证 root 命令已停止，重试前须确认实际状态。其他客户端可直接接入提权工具，系统认证不依赖客户端审批。
- 启动失败时检查用户级配置中的可执行路径是否存在；提权失败时检查 pkexec wrapper、polkit 服务和桌面认证代理。`required = false`，服务器不可用时 Codex 会报告，Agent 不应编造查询结果。
