# 设计决策

本文记录配置组织与 Harness 中需要长期维护的决策；操作步骤见 [development.md](development.md)。

## 配置组织

- flake-parts 提供顶层模块系统，import-tree 递归导入 `modules/` 中的功能模块，排除 `*.data.nix` 数据文件。功能目录中的 `default.nix` 本身就是顶层模块，不重复导入已经扫描到的文件。
- 功能按机器运行、个人使用、配置维护组织；系统配置与 Home Manager 配置共同归属功能，专属数据与配置放在同一目录。简单功能保留单文件。
- `dotnix.modules.nixos` 和 `dotnix.modules.home` 以 `deferredModule` 合并各功能的贡献；`assembly.nix` 将它们装配为唯一的 `nixosConfigurations.maco`。
- `dotnix.host` 保存当前单机的名称、平台和账户绑定；功能通过顶层作用域读取所需值。已有系统与用户配置仍是其路径等派生信息的来源；两个 `stateVersion` 独立维护。
- 本地包的构建定义与源码归 `packages/<name>/`，由所属功能发布 flake 包输出，不参加模块自动导入。
- Just 模块与 Shell 实现分别位于 `scripts/just/` 和 `scripts/sh/`，配方从仓库根执行。安装生成的硬件报告、磁盘设备输入归主机和存储功能；共享加密文件归身份功能，具体秘密声明归消费者。

## 工具边界

- 系统级工具保持最小集：Git、gh、rg、fd、jq、curl、wget、基础 shell 工具、Nix、direnv/nix-direnv。
- just、nh、Nix 格式化与静态检查工具、项目 MCP 属于项目环境，由 `modules/maintenance/development/default.nix` 供应；不在系统与项目之间复制。
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
- 两个服务都通过 `scripts/sh/mcp.sh` 用系统 Nix 从项目锁启动，stdio 直接传递，配置在项目 `.codex/config.toml`，不写入全局 AGENTS。

## 配置 label

`os switch` 的默认 label 来自当前工作树 Git tree hash，使启动项能区分未提交修改；显式 label 仍然可用。它不是 HEAD 提交 hash，也不是系统闭包 hash。
