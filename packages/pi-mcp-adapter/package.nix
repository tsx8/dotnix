{
  importNpmLock,
  nodejs,
}:
importNpmLock.buildNodeModules {
  npmRoot = ./.;
  inherit nodejs;
  derivationArgs = {
    pname = "pi-mcp-adapter";
    # 扩展由 Pi 加载；依赖使用发布包中的产物，不执行安装脚本。
    npmFlags = [ "--ignore-scripts" ];
  };
}
