{
  fetchurl,
  lib,
  stdenvNoCC,
  writeText,
}:

let
  # 上游 lock 缺以下嵌套依赖的 integrity 字段，逐项预取补齐；上游修复后可删。
  integrityFixups = {
    "node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/chord" =
      "sha256-w7mDujFVdptIZ/I3AgWj79jaig8pLitvZf70DQhhwx8=";
    "node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-agent-core" =
      "sha256-SlecSco0Pc9zQXiRGRrMqNsIXP+5hZz9x5TYyyikrf4=";
    "node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai" =
      "sha256-r30RmGF5RFzm/oizfVfeIvgjwP/TplyuMcVVt/XpklM=";
    "node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-telemetry" =
      "sha256-IhA6MsZXqx8MqN0LOtq0iSTFZjalqauLiaQ1WfsgExA=";
    "node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-tui" =
      "sha256-APAHyOdh5OVKNT6PgE57KVv+tRHMoha4c7y87j+6xB4=";
  };
  # git 源不含 dist，故锁 npm 发布物；package.json 为合成清单，只含主入口
  # dist/pi/extension.js 的运行时闭包（pi-subagents/jiti 仅供未注入的可选入口）。
  # version/hash 由 update.list 的 nix-update 更新；依赖 lock 由
  # scripts/sh/sync-pi-plugins-lock.sh 再生成；上游 lock 若再出现缺 integrity
  # 的生产条目，构建会失败并需要扩充下方 fixups。
  upstreamLock = lib.importJSON ./package-lock.json;
  lock = upstreamLock // {
    packages =
      upstreamLock.packages
      // (builtins.mapAttrs (
        path: integrity: upstreamLock.packages.${path} // { inherit integrity; }
      ) integrityFixups);
  };
  # node_modules 按 lock 记录的树直接解包物化：npm 离线安装会在理想树与 lock
  # 分歧时回源 registry（ENOTCACHED），且不可复现；解包与 --ignore-scripts 等价。
  compatible =
    v:
    (!(v ? os) || builtins.elem "linux" v.os || builtins.elem "any" v.os)
    && (!(v ? cpu) || builtins.elem "x64" v.cpu || builtins.elem "any" v.cpu);
  wanted = lib.filterAttrs (path: v: path != "" && v ? resolved && compatible v) lock.packages;
  sources = lib.mapAttrs (
    _: v:
    fetchurl {
      url = v.resolved;
      hash = v.integrity;
    }
  ) wanted;
  manifest = writeText "pi-plugins-node-modules-manifest" (
    lib.concatStrings (lib.mapAttrsToList (path: source: "${path}\t${source}\n") sources)
  );
in
stdenvNoCC.mkDerivation {
  pname = "pi-plugins";
  version = "0.8.4";

  src = fetchurl {
    url = "https://registry.npmjs.org/@nklisch/pi-plugins/-/pi-plugins-0.8.4.tgz";
    hash = "sha256-BE7hO23XpDPjjwSGOV3UQ0lRsMVp1jaSspJunHmKGrk=";
  };

  dontUnpack = true;
  dontBuild = true;

  # 入口 dist/pi/extension.js 静态导入 @nklisch/pi-mcp-adapter，须与 node_modules
  # 同级供 Pi 的模块解析向上查找；tarball 内捆绑的 node_modules 属未注入的可选入口，弃用。
  installPhase = ''
    runHook preInstall

    install -d "$out"
    upstream="$(mktemp -d)"
    tar -xf "$src" -C "$upstream"
    cp -R "$upstream/package"/. "$out"/
    rm -rf -- "$upstream"
    chmod -R u+w "$out"
    rm -rf "$out/node_modules"
    install -d "$out/node_modules"

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
    description = "Plugin host extension for the Pi coding agent";
    homepage = "https://github.com/nklisch/pi-extensions";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
