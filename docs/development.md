# 日常开发与验证

## 项目环境

交互终端进入仓库时由 direnv 加载环境。首次使用或 `.envrc` 变更后，先审阅文件，再运行 `direnv allow`。系统安装的 Pi 在默认 Bash 工具启动时按工作目录加载环境。确认加载成功、项目工具可用后直接运行命令，不只凭 `IN_NIX_SHELL` 判断。

如果 `.envrc` 未授权、被拒绝或加载失败，先修复问题。若 `BASH_ENV` 阻塞了 Bash 启动，可用非登录 `/bin/sh` 诊断或修复，不在其中继续项目命令。本项目的 devShell 求值失败时不会退回旧缓存。加载环境不改写 `flake.lock`，也不自动检查或应用系统。只有会话未配置自动入口时，才为每条命令显式进入 devShell：

```bash
nix develop --no-update-lock-file --no-write-lock-file --command just repo lint
```

`--command` 的环境不延续到下一条独立命令。非登录 Bash 启动后再跨项目 `cd` 不会重载环境，请直接指定命令的工作目录，或使用 `direnv exec <目录> <命令>`。新 Bash 在项目外启动时会卸载继承的项目环境。改用其他 `shellPath` 不保证加载 Pi 的 Bash 入口；修改该入口后须先获批应用系统并重启对应代理。

新增 devShell 的本地源码依赖时，同步更新 [.envrc](../.envrc) 的监视范围，包括目录中文件的增删。fmt、lint、test 都会拒绝未忽略的未跟踪文件。只对要交付的文件精确 `git add`，临时产物放到仓库外。

## 常用命令

| 命令 | 用途与副作用 |
| --- | --- |
| `just repo fmt` | 格式化 Nix 文件，修改工作树。 |
| `just repo lint` | 检查模块布局、注释、格式、Nix 和 Shell 源码及 Git 空白错误。最后可能给出 [overlay 提醒](#overlay-impact)。 |
| `just repo test` | 运行 `nix flake check` 并构建已声明的 checks，不逐个构建包。 |
| `just os build` | 先运行 lint 和 test，再构建系统，不激活。 |
| `just os test` | 先运行 lint 和 test。经授权和确认后在**宿主**上激活，不更改默认启动项。 |
| `just os switch [label]` | 经授权和确认后激活并更改默认启动项。**不自动运行 lint 或 test**，切换前须有适用于当前内容的检查结果。 |
| `just repo update [输入名…]` | 更新指定的 flake 输入，不指定则更新全部。两种情况都会继续检查所有登记包、同步 PiliPlus 依赖锁并运行 lint 和 test。 |
| `just repo pkg-update` | 只走包更新和 PiliPlus 依赖锁同步，不运行 flake 输入更新或最后的 lint 和 test。 |

三个 `os` 命令使用项目的 nh，目标为 `.#maco`，不更新或写入 lock。构建至少预留 10 分钟。未指定非空 label 时，`switch` 取工作树 Git tree hash 的前 12 位，包括未暂存的改动和未忽略的新文件。计算期间不要并行修改仓库。[操作边界](../AGENTS.md#操作边界)同样适用于临时激活。

### 更新依赖

需要随 `repo update` 更新、但源码不由 flake 输入跟踪的远端包，登记到 [packages/update.list](../packages/update.list)。每行一个包属性，可附加 nix-update 参数。若碰到 GitHub 匿名限额，检查更新进程是否使用了 sops 为该用户渲染的 `nix.conf`。令牌对应 `gh-auth-token`，不要把明文加到更新命令。

更新步骤失败后仍会执行后续步骤。网络更新步骤失败会重试一次，最终失败时打印日志目录，不撤销已成功的改动。T3 nightly 的更新单独验证候选版本，只有构建、版本和服务检查通过才替换 `packages/t3code-nightly/release.nix`。这不表示整次 `repo update` 可以回滚。

## 验证要求

按行为影响选检查。模型数据、配置或程序读取的文本，即使不是程序代码也可能改变行为。

| 改动 | 必需验证 |
| --- | --- |
| 讨论或只读调查 | 给出支持结论的证据，不要求格式化或构建。 |
| 说明文档或常驻指令 | 核对[内容归属](../AGENTS.md#文档边界)、授权、路径、链接和命令调用链。运行 `git diff --check HEAD`。必要时做语法检查或 dry-run，不执行破坏性示例。 |
| 开发环境、脚本、工具或包的可执行行为 | 运行 `just repo fmt`、`just repo lint` 和 `just repo test`。验证成功路径和必要的失败路径；改包还要验证该包确实能构建。 |
| 系统配置或影响系统的依赖 | 运行 `just repo fmt` 和 `just os build`，复用构建中的 lint 和 test。补验构建未覆盖的行为或包。 |

同一内容、相同条件下的结果可以复用。构建成功不能证明运行正常。交接时区分仓库声明、已激活系统、启动系统和当前会话的观测，不凭 store 链接不同推断必须重启。清理临时目录、测试仓库和命令替身，不提交验证报告或固定行为测试套件。

**注释检查。** lint 核对 Git 跟踪源码中的独占行、行尾和块注释，也检查补丁新增行及可识别的内嵌代码。Markdown、工具描述、shebang、ShellCheck 指令和密文不计入。新增或改写的注释报出路径和行号；删除时从 [comments.allow](../modules/maintenance/development/comments.allow) 移除报出的失效指纹。新文件没有额度。确须就地记录的理由逐条审阅，不整批刷新基线。

## 验证分层

先选能证明目标行为的最小范围。只在缺少宿主证据时考虑激活。

| 要回答的问题 | 取证方法 |
| --- | --- |
| 包能否启动、MCP 工具能否调用？ | `nix build` 对应包，运行实际产物或用 FastMCP Client 调用。 |
| 配置生成是否正确？ | 用 `nix eval` 或 `just os build` 检查生成文件、desktop entry 和 unit，必要时用 `systemd-analyze verify`。 |
| Pi 和服务能否在用户会话协作？ | 用[项目 MCP 覆盖](#mcp)或 `systemd-run --user --collect` 加产物的绝对路径。瞬态单元不能验证声明的单元依赖。 |
| 安装布局、激活脚本、网络或 systemd 行为是否正确？ | 构建并启动 VM，或使用一次性 `nixosTest`。构建 VM 的命令为 `nh os build-vm --hostname maco --no-update-lock-file --no-write-lock-file .#maco`。 |
| 需要验证真实 GPU、登录会话或启动项吗？ | VM 不能替代这些观察。经批准后选择 `just os test` 临时激活；需要更改默认启动项才用 `just os switch`。 |

<a id="overlay-impact"></a>

## Overlay 影响检查

lint 提醒的是相对 HEAD 改动过、且当前仍提供非空全局 overlay 的模块。它不比较依赖图，不触发 IFD 构建。输入单独更新、导入文件单独变更或已删除的 overlay 都可能不在提示中。查询失败或超时只报检查不可用，不阻断其他检查。

要隔离一个 overlay 的影响，准备两个只差该 overlay 的工作树，使用相同的 `flake.lock`。不要把旧 HEAD 强配新 lock。在两侧仓库根目录分别运行：

```bash
nix eval --raw --no-update-lock-file --no-write-lock-file \
  --max-jobs 0 --builders '' --option substitute false \
  .#nixosConfigurations.maco.config.system.build.toplevel.drvPath
```

任一侧求值失败都表示无法比较。若缺少已有构建产物，停止诊断，不放开构建或替代下载。将成功输出的两个路径分别赋给同一 Bash 会话中的 `before_drv` 和 `after_drv`，再比较构建配方的引用闭包：

```bash
(
  set -euo pipefail
  export LC_ALL=C
  tmp="$(mktemp -d)"
  trap 'rm -rf -- "$tmp"' EXIT
  nix-store -qR "$before_drv" | grep '\.drv$' | sort >"$tmp/before"
  nix-store -qR "$after_drv" | grep '\.drv$' | sort >"$tmp/after"
  printf 'Added derivations: '; comm -13 "$tmp/before" "$tmp/after" | wc -l
  printf 'Removed derivations: '; comm -23 "$tmp/before" "$tmp/after" | wc -l
)
```

这是配方数量，不是需要编译的软件包数。若要看具体差异，可运行以下命令。它可能下载或构建诊断工具，不构建被比较的系统。

```bash
nix run --inputs-from . --no-update-lock-file --no-write-lock-file \
  nixpkgs#nix-diff -- "$before_drv" "$after_drv"
```

## MCP

项目环境提供 `mcp-dotnix` 和 `mcp-nixos`。需要单独验证构建时运行 `nix build --no-link --no-update-lock-file --no-write-lock-file .#mcp-dotnix .#mcp-nixos`。在 Pi 中用 `/mcp` 查看或重连，也可用 `pi mcp list` 诊断。列表包括隐藏工具，能否调用要看暴露状态。仓库声明的工具和超时见 [Pi 配置](../modules/agents/pi/default.nix)。连接失败先检查配置的可执行路径。

要在激活前试用新产物，在项目 `.pi/mcp.json` 以同名服务器覆盖全局配置，使用产物的绝对路径。验证后撤销本次覆盖，保留项目原有配置。不要提交临时覆盖，也不要带入仓库检查。Pi 可回写全局 `~/.pi/agent/mcp.json`。应用 MCP 配置前先备份该文件。激活会合并受管字段，保留额外服务器和未声明字段；回滚系统 generation 不会还原已合并的用户文件。

`mcp-deepseek-search` 使用独立的 sops 密钥 `deepseek-search`，不使用模型凭据或浏览器登录态。获准后用 `just secrets edit` 配置或轮换，应用系统后重连服务，不把明文写入 `mcp.json`。搜索词、可选的原始问题和定位 IP、抓取的目标 URL 会发送给 DeepSeek。连接成功不证明远端认证有效，调用失败不自动重试。计费见 [Search & Fetch 官方指南](https://api-docs.deepseek.com/guides/search)。
