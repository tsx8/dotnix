{
  esbuild,
  lib,
  nodejs_24,
  stdenvNoCC,
}:

# src/cdp 复用 pi-chrome-use 的 CDP 传输层与协议定义（MIT，见 src/cdp/LICENSE）；
# vendored 源码与 CLI 一起打包，运行及构建均不依赖上游 flake。
stdenvNoCC.mkDerivation {
  pname = "bex";
  version = "0.4.0";

  src = ./src;

  nativeBuildInputs = [ esbuild ];

  # alias 把上游 store 源码桥接进 bundle；.js 后缀的相对导入由 esbuild 按
  # TS 惯例重写到 .ts。
  buildPhase = ''
    runHook preBuild

    esbuild "$src/bex.ts" \
      --bundle --platform=node --format=esm --target=node24 \
      --legal-comments=none \
      --outfile="bex.mjs"

    runHook postBuild
  '';

  installPhase = ''
        runHook preInstall

        install -Dm644 bex.mjs "$out/lib/bex/bex.mjs"
        install -Dm644 "$src/cdp/LICENSE" "$out/share/licenses/bex/pi-chrome-use-LICENSE"
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
