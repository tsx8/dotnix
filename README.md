# dotnix

`maco` 的 NixOS 配置。仓库以 flake 管理，`nixosConfigurations.maco` 是系统的唯一入口。

## 配置

- 桌面：KDE Plasma 6、SDDM、Fcitx5 + Rime、keyd 键位映射、PipeWire 音频。
- 网络：dae（通过 daeuniverse flake 模块接入）。
- 维护：sops-nix secrets、disko 分区、nix-direnv 开发环境。
- Agent 工具：Codex、项目级 MCP（`mcp-dotnix`、`mcp-nixos`）。

声明式配置只有在执行 `just os test` 或 `just os switch` 后才进入运行系统；在此之前，文档描述的是目标配置。

## 文档

- [安装](docs/install.md)
- [日常开发与验证](docs/development.md)
- [设计决策](docs/design.md)
- [Agent 常驻指令](AGENTS.md)

## 日常命令

```bash
just repo fmt
just repo lint
just repo test
just repo update

just os build
just os test
just os switch
```

`just os test`、`just os switch`、回滚、重启、secrets 操作和 push 由用户执行。
