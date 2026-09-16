{
  adapterSrc,
  importNpmLock,
  lib,
  nodejs,
  stdenvNoCC,
}:

let
  # 上游 lock 缺以下嵌套依赖的 integrity 字段，逐项预取补齐；上游修复后可删。
  integrityFixups = {
    "node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-agent-core" =
      "sha256-qq0hg7Xsl66lQgE6/quhNlM4lLCWADwnXBm6Y85V7j8=";
    "node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai" =
      "sha256-araJGJ58s95c2xJjEqPmDorDX+XuXxtj0A9xHIpDDHM=";
    "node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-client" =
      "sha256-iK/HOxkwWCcQ2DYPT6k6XYHwUu4fX7aDkCH3xPfYBSo=";
    "node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-protocol" =
      "sha256-Ldxtomn/+a36btSLk5OjoViWCLzdNbvT3sp4KNENlYo=";
    "node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-telemetry" =
      "sha256-o57d7wAXG7ZRAVklvrirF2LksRJyAqOOaKny4Ry1PqU=";
    "node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-tui" =
      "sha256-meHzu/jZ8DdT/KxmODHfYc+VssRfskkUJvlc8o2Coi0=";
  };
  # 上游 lock 是依赖闭包的唯一来源；扩展由 Pi 加载，不执行安装脚本。
  upstreamLock = lib.importJSON "${adapterSrc}/package-lock.json";
  packageLock = upstreamLock // {
    packages =
      upstreamLock.packages
      // (builtins.mapAttrs (
        path: integrity: upstreamLock.packages.${path} // { inherit integrity; }
      ) integrityFixups);
  };
  # 扩展运行时只需要生产依赖；上游 dev 树（vitest、pi-coding-agent 等）不参与安装。
  package = (lib.importJSON "${adapterSrc}/package.json") // {
    devDependencies = { };
  };
  nodeModules = importNpmLock.buildNodeModules {
    inherit package packageLock;
    npmRoot = adapterSrc;
    inherit nodejs;
    derivationArgs.npmFlags = [ "--ignore-scripts" ];
  };
in
stdenvNoCC.mkDerivation {
  pname = "pi-mcp-adapter";
  # 版本随 flake input 晋进，与上游 package.json 保持一致。
  inherit ((lib.importJSON "${adapterSrc}/package.json")) version;

  src = adapterSrc;

  dontBuild = true;

  # 入口与其同仓源文件须与 node_modules 同级，供 Pi 的模块解析向上查找。
  installPhase = ''
    runHook preInstall

    install -d "$out"
    cp -R "$src"/. "$out"/
    chmod -R u+w "$out"
    ln -s "${nodeModules}/node_modules" "$out/node_modules"

    runHook postInstall
  '';

  meta = {
    description = "MCP adapter extension for the Pi coding agent";
    homepage = "https://github.com/nicobailon/pi-mcp-adapter";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
