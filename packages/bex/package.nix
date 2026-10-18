{
  esbuild,
  lib,
  nodejs_24,
  stdenvNoCC,
}:

# src/cdp reuses pi-chrome-use's CDP transport layer and protocol definitions (MIT, see src/cdp/LICENSE);
# the vendored sources ship with the CLI; neither running nor building depends on the upstream flake.
stdenvNoCC.mkDerivation {
  pname = "bex";
  version = "0.4.0";

  src = ./src;

  nativeBuildInputs = [ esbuild ];

  # The alias bridges the upstream store sources into the bundle; relative imports with a .js suffix are
  # rewritten to .ts by esbuild following TS conventions.
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
