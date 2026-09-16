# 开发 Harness 架构设计

本文记录支撑仓库开发与维护的 Harness 架构设计决策，包括模块装配、开发环境、工具职责和验证分工；操作步骤见 [development.md](development.md)。

## 配置组织

- flake-parts 提供顶层模块系统，import-tree 递归导入 `modules/` 中的功能模块，排除 `*.data.nix` 数据文件。功能目录中的 `default.nix` 本身就是顶层模块，不重复导入已经扫描到的文件。
- 功能按机器运行、个人使用、配置维护组织；系统配置与 Home Manager 配置共同归属功能，专属数据与配置放在同一目录。简单功能保留单文件。
- `dotnix.modules.nixos` 和 `dotnix.modules.home` 以 `deferredModule` 合并各功能的贡献；`assembly.nix` 将它们装配为唯一的 `nixosConfigurations.maco`。
- `dotnix.host` 保存当前单机的名称、平台和账户绑定，供功能共享；路径等派生信息仍从系统与用户配置读取，避免形成第二份配置来源。
- 本地包的构建定义与源码归 `packages/<name>/`，由所属功能发布 flake 包输出，不参加模块自动导入。
- Just 模块与 Shell 实现分别位于 `scripts/just/` 和 `scripts/sh/`，配方从仓库根执行。安装生成的硬件报告、磁盘设备输入归主机和存储功能；共享加密文件归身份功能，具体秘密声明归消费者。

## 工具边界

- 系统提供跨项目通用工具和加载项目环境所需的 Nix、direnv；仓库专属命令、检查工具与 MCP 由 [项目环境模块](../modules/maintenance/development/default.nix) 供应。项目工具随仓库锁定版本，避免依赖宿主机上的另一套版本。
- `modules/maintenance/` 是项目开发环境的模块边界，影响 devShell 的模块定义集中于此。direnv 监视此目录和环境依赖的本地工具源码，普通系统配置与应用数据不触发环境刷新。
- Home Manager 只管理用户级配置，不管理应用。
- [终端模块](../modules/personal/terminal/default.nix) 管理 direnv，并提供非交互 Bash 的环境加载入口 [bash-env.sh](../modules/personal/terminal/bash-env.sh)。Codex 与 Pi 分别设置 `BASH_ENV` 使用此入口，复用 direnv 授权和 nix-direnv 缓存，使每次命令按工作目录取得环境；不设置全局 `BASH_ENV`。Codex 通过命令环境配置接入，不参与其父进程和快照生成；Pi 通过启动包装传递给子进程。环境加载不改变代理权限，两个入口分别在 [Codex 模块](../modules/personal/applications/codex/default.nix) 与 [Pi 模块](../modules/personal/applications/pi.nix)。

## 文档与约束

- 安装操作在 `docs/install.md`，环境入口、命令和验证步骤在 `docs/development.md`，开发 Harness 的架构设计理由在本文；README 保留仓库概览、简短命令和文档入口。内容归属遵循 [AGENTS.md 的文档边界](../AGENTS.md#文档边界)。
- 可执行约束由代码落实，局部理由紧邻实现，文档连接使用入口与跨组件设计。这样局部实现变化无需维护一份源码解说，使用者仍能在不读源码的情况下理解操作的前提、后果与限制；对外行为或架构取舍变化时，才同步相应文档。
- 根 `AGENTS.md` 保留稳定项目约束、授权边界和必读文档入口，操作细节由引用文档维护；不使用额外 rules 文件。这些文档约束流程与授权，不能在技术上阻止绕过流程的命令。临时系统状态留在交接记录中，不写入常驻文档。
- 不引入 CI、常驻后台服务或永久配置行为测试体系；验证由本地命令和临时验证承担。

## 验证分工

- 验证按实际影响和证据缺口选择，具体要求见 [development.md](development.md#验证要求)。纯文档检查内容和流程一致性；可执行行为仍需实际验证。已有结果在内容和条件仍适用时复用，避免重复检查。
- flake 检查、包构建和运行观察覆盖不同问题，不能互相替代；命令覆盖范围见 [常用命令](development.md#常用命令)。
- 配置行为的临时验证按需创建、执行、审查并清理，不保留固定套件。
- `os build` 验证系统配置可构建；安装和激活由用户执行，运行结论需相应实际观察。Agent 可通过只读诊断取证，安装或激活命令成功本身不代表所有功能已验证。

## 项目 MCP

- `mcp-dotnix` 将只读诊断与 `run_privileged` 分开，后者由客户端在执行前取得用户批准。系统授权仅覆盖本机用户调用固定的 Nix store 入口，执行入口与 sudo 规则由 [同一个包输出](../modules/maintenance/mcp.nix) 连接。同账户其他程序也可调用该入口，操作系统不验证客户端审批；不能把客户端审批视为系统级隔离。调用契约与故障处理见 [开发文档](development.md#mcp)。
- `mcp-dotnix` 由本仓库维护；`mcp-nixos` 复用官方 flake，查询也须遵守仓库的 lock 保护约束。两个服务独立构建和运行，避免应用依赖相互污染，底层依赖由 Nix 复用。
- 两个服务都通过 `scripts/sh/mcp.sh` 用系统 Nix 从项目锁启动，stdio 直接传递。Codex 的项目配置在 `.codex/config.toml`；Pi 通过固定版本的 `pi-mcp-adapter` 加载 `.pi/mcp.json`。客户端分别维护工具筛选与超时，不引入配置同步脚本。
- Pi 的 MCP 入口只暴露只读诊断和 Nix 查询，适配器使用工具白名单过滤，不注册 `run_privileged`。这不改变系统 sudo 规则，也不是对 Bash 工具的权限隔离。适配器由 Nix 打包，通过 Pi 启动参数加载，不依赖用户目录中的 npm 安装或 `settings.json`。

## 配置 label

`os switch` 的默认 label 来自当前工作树 Git tree hash，使启动项能区分未提交修改；显式 label 仍然可用。它不是 HEAD 提交 hash，也不是系统闭包 hash。
