# dotnix

`maco` 的 NixOS 配置。仓库以 flake 管理，`nixosConfigurations.maco` 是系统的唯一入口。

## 配置

- 桌面：KDE Plasma 6、SDDM、Fcitx5 + Rime、keyd 键位映射、PipeWire 音频。
- 网络：dae（通过 daeuniverse flake 模块接入）。
- 维护：sops-nix secrets、disko 分区、nix-direnv 开发环境。
- Agent 工具：Codex、项目级 MCP（`mcp-dotnix`、`mcp-nixos`）。

仓库描述声明配置，运行状态取决于实际安装、激活和启动的配置，不能仅凭仓库内容判断。

## 文档

- [安装](docs/install.md)
- [日常开发与验证](docs/development.md)
- [设计决策](docs/design.md)
- [Agent 常驻指令](AGENTS.md)

## 日常命令

先按 [项目环境](docs/development.md#项目环境) 加载开发工具，再按 [验证要求](docs/development.md#验证要求) 选择检查：

```bash
just repo fmt
just repo lint
just repo test
just os build
```

需要更新输入时运行 `just repo update`，该命令也会同步 Codex 模型目录。应用系统由用户执行：

```bash
just os test
just os switch
```

`os switch` 不自动运行 lint/test，切换前须有当前内容的适用检查结果，详见 [常用命令](docs/development.md#常用命令)。回滚、重启、安装、secrets 操作和 push 也由用户执行。
