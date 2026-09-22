{
  esbuild,
  lib,
  nodejs_24,
  piChromeUseSrc,
  stdenvNoCC,
}:

# 复用 pi-chrome-use 的 src/cdp 库（零运行时依赖，原生 WebSocket），bex 只加
# CLI 入口；协议 JSON 随包内联，供 `bex api` 离线发现。
stdenvNoCC.mkDerivation {
  pname = "bex";
  version = "0.2.0";

  src = ./src;

  nativeBuildInputs = [ esbuild ];

  # alias 把上游 store 源码桥接进 bundle；.js 后缀的相对导入由 esbuild 按
  # TS 惯例重写到 .ts。
  buildPhase = ''
    runHook preBuild

    esbuild "$src/bex.ts" \
      --bundle --platform=node --format=esm --target=node24 \
      --legal-comments=none \
      --alias:@cdp/session=${piChromeUseSrc}/src/cdp/session.ts \
      --alias:@cdp/browser-protocol=${piChromeUseSrc}/src/cdp/browser_protocol.json \
      --alias:@cdp/js-protocol=${piChromeUseSrc}/src/cdp/js_protocol.json \
      --outfile="bex.mjs"

    runHook postBuild
  '';

  installPhase = ''
        runHook preInstall

        install -Dm644 bex.mjs "$out/lib/bex/bex.mjs"
        mkdir -p "$out/bin"
        cat > "$out/bin/bex" <<EOF
    #!/bin/sh
    exec ${nodejs_24}/bin/node "$out/lib/bex/bex.mjs" "\$@"
    EOF
        chmod +x "$out/bin/bex"

        runHook postInstall
  '';

  meta = {
    description = "CDP-generic browser snippet runner (runtime of the helium-use skill)";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
