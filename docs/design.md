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
- `modules/maintenance/` 是项目开发环境的模块边界，影响 devShell 的模块定义集中于此。direnv 监视此目录和环境依赖的本地工具源码，普通系统配置与应用数据不触发环境刷新。
- Home Manager 只管理用户级配置，不管理应用。
- Codex 的项目环境由非登录 Bash 的 `BASH_ENV` 入口加载，复用 direnv 授权和 nix-direnv 缓存。关闭登录模式避免命令恢复旧 shell 快照；`BASH_ENV` 仅写入 Codex 的子进程环境配置，不导出到启动 Codex 的父进程，避免快照生成阶段执行项目环境。环境加载不改变 sandbox 权限。

## 文档与约束

- 安装操作在 `docs/install.md`，环境入口、命令和验证步骤在 `docs/development.md`，长期设计理由在本文；README 保留仓库概览、简短命令和文档入口。
- 根 `AGENTS.md` 保留稳定项目约束、授权边界和必读文档入口，操作细节由引用文档维护；不使用额外 rules 文件。这些文档约束流程与授权，不能在技术上阻止绕过流程的命令。临时系统状态留在交接记录中，不写入常驻文档。
- 不引入 CI、常驻后台服务或永久配置行为测试体系；验证由本地命令和临时验证承担。

## 验证分工

- 验证按实际影响和证据缺口选择，具体要求见 [development.md](development.md#验证要求)。纯文档检查内容和流程一致性；可执行行为仍需实际验证。已有结果在内容和条件仍适用时复用，避免重复检查。
- `just repo lint` 覆盖 Nix 格式、nixf 诊断、statix 反模式检查、Shell 脚本 ShellCheck 和 Git 空白错误；`just repo test` 运行 `nix flake check`，不能代替变更包的定向构建或行为验证。
- 配置行为的临时验证按需创建、执行、审查并清理，不保留固定套件。
- `os build` 验证系统配置可构建；安装和激活由用户执行，运行结论需相应实际观察。Agent 可通过只读诊断取证，安装或激活命令成功本身不代表所有功能已验证。

## 项目 MCP

- `mcp-dotnix` 是本仓库自有只读诊断服务，包与入口名为 `mcp-dotnix`；能力不随改名扩展。
- `mcp-nixos` 使用官方 utensils/mcp-nixos flake 输入；其 flake 输入查询在本地包中补上 lock 保护参数。
- 两个服务都通过 `scripts/sh/mcp.sh` 用系统 Nix 从项目锁启动，stdio 直接传递，配置在项目 `.codex/config.toml`，不写入全局 AGENTS。

## 配置 label

`os switch` 的默认 label 来自当前工作树 Git tree hash，使启动项能区分未提交修改；显式 label 仍然可用。它不是 HEAD 提交 hash，也不是系统闭包 hash。
