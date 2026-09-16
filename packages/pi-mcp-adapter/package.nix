{
  adapterSrc,
  fetchurl,
  lib,
  stdenvNoCC,
  writeText,
}:

let
  # 上游 lock 缺以下嵌套依赖的 integrity 字段，逐项预取补齐；上游修复后可删。
  integrityFixups = {
    "node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-agent-core" =
      "sha256-qq0hg7Xsl66lQgE6/quhNlM4lLCWADwnXBm6Y85V7j8=";
    "node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai" =
      "sha256-araJGJ58s95c2xJjEqPmDorDX+XuXxtj0A9xHIpDDHM=";
    "node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-client" =
      "sha256-iK/HOxkwWCcQ2DYPT6k6XYHwUu4fX7A7DkCH3xPfYBSo=";
    "node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-protocol" =
      "sha256-Ldxtomn/+a36btSLk5OjoViWCLzdNbvT3sp4KNENlYo=";
    "node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-telemetry" =
      "sha256-o57d7wAXG7ZRAVklvrirF2LksRJyAqOOaKny4Ry1PqU=";
    "node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-tui" =
      "sha256-meHzu/jZ8DdT/KxmODHfYc+VssRfskkUJvlc8o2Coi0=";
  };
  upstreamLock = lib.importJSON "${adapterSrc}/package-lock.json";
  lock = upstreamLock // {
    packages =
      upstreamLock.packages
      // (builtins.mapAttrs (
        path: integrity: upstreamLock.packages.${path} // { inherit integrity; }
      ) integrityFixups);
  };
  # node_modules 按 lock 记录的树直接解包物化：npm 离线安装会在理想树与 lock
  # 分歧时回源 registry（ENOTCACHED），且不可复现；解包与 --ignore-scripts 等价。
  # 上游 lock 含 devDependencies 闭包，仅安装生产可达条目。
  compatible =
    v:
    (!(v ? os) || builtins.elem "linux" v.os || builtins.elem "any" v.os)
    && (!(v ? cpu) || builtins.elem "x64" v.cpu || builtins.elem "any" v.cpu);
  wanted = lib.filterAttrs (
    path: v: path != "" && v ? resolved && !(v.dev or false) && compatible v
  ) lock.packages;
  sources = lib.mapAttrs (
    _: v:
    fetchurl {
      url = v.resolved;
      hash = v.integrity;
    }
  ) wanted;
  manifest = writeText "pi-mcp-adapter-node-modules-manifest" (
    lib.concatStrings (lib.mapAttrsToList (path: source: "${path}\t${source}\n") sources)
  );
in
stdenvNoCC.mkDerivation {
  pname = "pi-mcp-adapter";
  # 版本随 flake input 更新，与上游 package.json 保持一致。
  inherit ((lib.importJSON "${adapterSrc}/package.json")) version;

  src = adapterSrc;

  dontBuild = true;

  # 入口 index.ts 与其依赖须与 node_modules 同级，供 Pi 的模块解析向上查找。
  installPhase = ''
    runHook preInstall

    install -d "$out"
    cp -R "$src"/. "$out"/
    chmod -R u+w "$out"

    while IFS=$'\t' read -r rel source; do
      target="$out/$rel"
      install -d "$(dirname "$target")"
      unpack="$(mktemp -d)"
      tar -xf "$source" -C "$unpack"
      if [ -d "$unpack/package" ]; then
        content="$unpack/package"
      else
        content="$unpack"
      fi
      rm -rf -- "$target"
      mv "$content" "$target"
      rm -rf -- "$unpack"
    done < "${manifest}"

    runHook postInstall
  '';

  meta = {
    description = "MCP adapter extension for the Pi coding agent";
    homepage = "https://github.com/nicobailon/pi-mcp-adapter";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
