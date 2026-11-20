# dotnix

[flake.nix](flake.nix) 声明单机 `maco` 的 NixOS 配置。系统入口是 `nixosConfigurations.maco`。桌面使用 KDE Plasma，T3 Code nightly 使用系统安装的 Pi，手机配对后可与桌面连接同一代理服务。

- [从 Live ISO 安装](docs/install.md)
- [开发命令与验证要求](docs/development.md)
- [开发 Harness 的架构决策](docs/design.md)
- [代理和贡献者的常驻指令](AGENTS.md)

修改系统配置后，在[项目环境](docs/development.md#项目环境)中运行：

```bash
just repo fmt
just os build
```

构建包含 lint 和 flake check，不会激活系统。需要应用配置时，先取得[操作批准](AGENTS.md#操作边界)，再按[常用命令](docs/development.md#常用命令)选择临时激活或更改默认启动项。
