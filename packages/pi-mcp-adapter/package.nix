{
  adapterSrc,
  fetchurl,
  lib,
  stdenvNoCC,
  writeText,
}:

let
  upstreamLock = lib.importJSON "${adapterSrc}/package-lock.json";
  # node_modules 按 lock 记录的树直接解包物化：npm 离线安装会在理想树与 lock
  # 分歧时回源 registry（ENOTCACHED），且不可复现；解包与 --ignore-scripts 等价。
  # 上游 lock 含 devDependencies 闭包，仅安装生产可达条目。
  compatible =
    v:
    (!(v ? os) || builtins.elem "linux" v.os || builtins.elem "any" v.os)
    && (!(v ? cpu) || builtins.elem "x64" v.cpu || builtins.elem "any" v.cpu);
  wanted = lib.filterAttrs (
    path: v: path != "" && v ? resolved && !(v.dev or false) && compatible v
  ) upstreamLock.packages;
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
