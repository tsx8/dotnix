# 日常开发与验证

## 项目环境

系统启用 nix-direnv 后（声明已在 `configuration.nix` 中配置）：

```bash
direnv allow
```

系统尚未应用 nix-direnv 时，使用显式入口：

```bash
nix develop --no-update-lock-file --no-write-lock-file --command just --list
```

环境加载失败时不会回退到其他工具来源；先修正 `.envrc`、flake 或 Nix 环境。`nix develop` 不隐式更新 `flake.lock`，需要更新输入时执行 `just repo update`。

## 常用命令

```bash
just repo fmt     # 格式化 Nix 文件（nixfmt-tree）
just repo lint    # nixfmt 检查、nixf-diagnose、statix、ShellCheck、Git 空白检查
just repo test    # nix flake check（含已声明 checks，不使用 --no-build）
just repo update  # 更新全部或指定 flake 输入，然后同步模型目录并运行 lint、test

just os build     # 构建配置，不激活
just os test      # 构建并激活当前代，不改变默认启动项；需要确认
just os switch    # 构建并切换默认启动项；需要确认
```

`os build`、`os test`、`os switch` 先执行 repo lint 和 repo test，再调用项目 nh，目标显式为 `.#maco`，并禁止更新/写入 lock。构建至少预留 10 分钟。`test` 不等于 `build`，`build` 不证明系统运行正常。

## Codex 模型目录

`just repo update` 在 flake 输入更新成功后同步当前 ChatGPT 账号的远端模型目录；传入指定输入名时也会同步。同步失败则停止后续检查，已经完成的 flake 输入更新不会回滚。也可单独运行 `scripts/sync-models.sh`。脚本使用系统 Codex 和 bubblewrap，在独立挂载视图中屏蔽普通配置并使用临时缓存；脚本不直接读取凭据内容，不修改现有 Codex 配置或缓存。需已有 ChatGPT 登录和模型缓存文件。

同步保留 Astra、Sol、Terra、Luna、GPT-5.5 的长上下文覆盖，其他模型采用上游值。刷新失败、目标模型缺失或目录校验失败时保留原文件。成功后审阅 `git diff HEAD -- codex/models.json`，按系统配置变更流程检查、构建和应用；脚本不自动暂存或应用系统。

## 工作树 label

`just os switch` 未传入非空 label 时，用 `scripts/worktree-label.sh` 计算当前工作树 Git tree hash 前 12 位。该结果包含已跟踪文件的当前内容、删除、模式与符号链接变化以及未忽略的新文件，忽略的未跟踪文件不参与。脚本使用临时 index，不改变真实暂存区和工作树。操作期间不要并行修改仓库。

## 临时验证与清理

配置行为修改按改动面创建临时测试：使用临时目录、独立测试仓库或命令替身，执行成功路径和必要失败路径，验证后删除临时产物并在交付说明中报告证据。不保留固定行为测试套件、临时测试框架或报告目录。仓库只保留服务自身需要的源代码。

## 执行环境

- Codex sandbox 可能阻止 Nix daemon socket；按审批在 sandbox 外运行受影响的 just 命令，不全局开放网络。
- 重定向 Nix cache 目录时，先更新 Codex writable root，再运行验证命令。

## MCP

- 首次使用前预构建：

```bash
nix build --no-link .#mcp-dotnix .#mcp-nixos
```

- Codex 首次打开项目时确认项目信任；项目配置 `.codex/config.toml` 声明两个 MCP，启动命令是仓库根下的 `scripts/mcp.sh`。
- 启动失败时检查：包是否可构建、Nix daemon 是否可用、`scripts/mcp.sh` 是否能解析 Git 根。`required = false`，服务器不可用时 Codex 会报告，Agent 不应编造查询结果。
