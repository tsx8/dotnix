# 开发 Harness 架构设计

安装步骤见[安装指南](install.md)，命令和检查方法见[日常开发与验证](development.md)。

## 配置组织

[flake.nix](../flake.nix) 用 flake-parts 组织输出，用 import-tree 导入 `modules/` 下的功能模块。简单功能用单个 Nix 文件。有专属数据或脚本时，使用同名目录和 `default.nix`，不再从别处重复导入。以 `.data.nix` 结尾的数据文件由使用方显式导入。

同一功能可以同时向 `dotnix.modules.nixos` 和 `dotnix.modules.home` 提供配置。[装配模块](../modules/maintenance/assembly.nix) 用 `deferredModule` 合并贡献，再把 Home Manager 接入系统。共享的主机、平台和账户来自 `dotnix.host`，不另建一份用户目录或系统路径表。包的构建定义放在 `packages/`，由使用它的功能发布，不参加模块扫描。

安装和运行共用[磁盘布局](../modules/machine/storage/layout.data.nix)。系统和备份需要知道盘之间的关系，擦盘却只能针对用户选中的设备。因此 `diskoConfigurations` 为每个角色暴露单盘配置，安装脚本不改写完整布局，也不要求另一块盘在场。共享密文归身份模块，哪些秘密要部署、由谁读取，归各自的使用方。

## 工具边界

NixOS 提供跨项目的应用、Nix 和 direnv。Home Manager 只管理用户配置，保留生成会话变量所需的包。[devShell](../modules/maintenance/development/default.nix) 单独导入 nixpkgs，为项目命令锁定依赖，不继承系统的包许可策略。direnv 只监视开发环境及其本地依赖，修改桌面配置不应触发环境重建。

交互式 fish 有 direnv 钩子，代理启动的非登录 Bash 没有。因此 [Pi 的启动脚本](../modules/agents/pi/default.nix) 为子进程设置 `BASH_ENV`，复用相同的 direnv 授权和缓存，不改变其他程序的 shell 环境。[加载脚本](../modules/agents/bash-env.sh) 隐去状态日志，保留错误。外部共享技能放在 `~/.agents/skills/`，不依赖某个代理安装扩展。

## 文档与约束

[AGENTS.md](../AGENTS.md#文档边界) 是常驻规则的入口。安装和开发指南按读者要完成的工作组织，跨组件的取舍记在本文。这样新增检查只需更新使用契约，不必在几份文档里同步检查器的实现。

### ADR：注释默认不增加

单纯限制总行数会允许用十条新注释替换十条旧注释。lint 改为按文件核对已审阅的注释及其出现次数。删除旧注释不会留下可复用的额度。工具指令和面向调用方的说明不算维护注释。

## 验证分工

整机是部署单位，不是每个改动的测试环境。包能否构建、生成配置是否正确、服务在真实会话中是否可用，需要不同证据。按[验证分层](development.md#验证分层)就近取证，剩余问题确实依赖宿主时才考虑激活。本仓库用本地检查和一次性验证，不引入 CI、常驻验证服务或固定的配置行为测试套件。

全局 overlay 可能影响远多于一个包。日常 lint 只提示哪些来源模块改动过，不把使用 overlay 判为错误。[比较构建配方](development.md#overlay-impact)留给需要判断影响范围时执行，避免每次 lint 都求值两套系统。

## 项目 MCP

`mcp-dotnix` 提供本机只读诊断。`mcp-nixos` 使用官方 flake 锁定的源码，由本仓库打包，使查询 flake 输入时不更新或写入 lock。两者可共用 FastMCP，但独立构建、独立启动，不替换全局 Python 包集，也不向 devShell 导出服务的 `PYTHONPATH`。

Pi 直接引用构建产物，不要求从 dotnix 目录启动。服务保留会话工作目录，便于查询当前项目。Pi 默认隐藏受管服务器的工具，只将选定工具设为 `deferred`，避免上游新增工具后自动暴露。工具筛选不限制 Bash 权限。

## ADR：共享代理环境与可写状态

桌面和手机需要接回同一组线程，因此桌面客户端连接同一个 T3 用户服务，不另起本地服务器。该服务在 KDE 登录前也要找到系统的 Pi、Git 和 shell，不能依赖登录会话提供的 PATH。

服务同时监听所有接口，热点下的手机不装 VPN 也能配对；防火墙关闭，校园网侧同样可达，入口只由配对鉴权保护，这是有意接受的暴露面。

Pi 的模型目录可以直接链接到 Nix store。Pi 设置、MCP 配置和 T3 桌面设置会由程序写回，所以激活时合并受管字段，不用只读链接替换整份文件。Pi 的 `enabledModels` 是例外，激活会移除它，使模型目录不受白名单限制。

## ADR：包更新以候选产物为准

flake 输入由 lock 跟踪。需要独立更新的远端包共用登记入口。更新脚本复用调用者的 Nix 凭据。只改版本号可能仍取到旧源码，所以普通包更新要检查源依赖是否随版本改变。T3 nightly 还要验证 CLI、桌面端和服务是否出自同一版本。更新器复用上游配方，在可写副本中构建和验证，成功后才回写固定输入。Git 对比用的仓库留在副本外，以免 Nix 将正在编辑的路径当成 Git 快照。

## 配置 label

只用 HEAD 不能区分尚未提交的系统配置。`os switch` 用临时 Git 索引计算工作树的 tree hash，通过 `NIXOS_LABEL` 传给构建，不改动用户的暂存区。这个标记描述工作树，不是系统闭包的哈希。
