# 设计决策

本文只记录需要长期维护的 Harness 决策；操作步骤见 [development.md](development.md)。

## 工具边界

- 系统级工具保持最小集：Git、gh、rg、fd、jq、curl、wget、基础 shell 工具、Nix、direnv/nix-direnv。
- just、nh、Nix 格式化与静态检查工具、项目 MCP 属于项目环境，由 `shell.nix` 供应；不在系统与项目之间复制。
- Home Manager 只管理用户级配置，不管理应用。

## 文档与约束

- 安装操作在 `docs/install.md`，开发与验证在 `docs/development.md`；README 只保留仓库概览和入口。
- 行为约束集中在根 `AGENTS.md` 及其引用文档；不使用额外 rules 文件。这些文档约束流程与授权，不能在技术上阻止绕过流程的命令。
- 不引入 CI、常驻后台服务或永久配置行为测试体系；验证由本地命令和临时验证承担。

## 验证分工

- `just repo lint` 覆盖 Nix 格式、nixf 诊断、statix 反模式检查、维护脚本 ShellCheck 和 Git 空白错误；`just repo test` 运行 `nix flake check`。
- 配置行为验证按改动面临时创建、执行、审查并清理，不保留固定套件。
- `test` 验证 flake 声明，`os build` 验证配置可构建，运行状态由用户通过 `os test`/`os switch` 验证。

## 项目 MCP

- `mcp-dotnix` 是本仓库自有只读诊断服务，包与入口名为 `mcp-dotnix`；能力不随改名扩展。
- `mcp-nixos` 使用官方 utensils/mcp-nixos flake 输入；其 flake 输入查询在本地包中补上 lock 保护参数。
- 两个服务都通过 `scripts/mcp.sh` 用系统 Nix 从项目锁启动，stdio 直接传递，配置在项目 `.codex/config.toml`，不写入全局 AGENTS。

## 配置 label

`os switch` 的默认 label 来自当前工作树 Git tree hash，使启动项能区分未提交修改；显式 label 仍然可用。它不是 HEAD 提交 hash，也不是系统闭包 hash。
