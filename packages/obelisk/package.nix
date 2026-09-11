{
  lib,
  fetchurl,
  makeBinaryWrapper,
  nodejs_24,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation {
  pname = "obelisk";
  version = "0.2.6-rc.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/@obelisk-apps/cli/-/cli-0.2.6-rc.0.tgz";
    hash = "sha256-XsPRoYR4c/62M8fGazDlXh81HUaJj+SJwxBBwfGwGhw=";
  };

  sourceRoot = "package";

  nativeBuildInputs = [ makeBinaryWrapper ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -d "$out/lib/obelisk" "$out/bin" "$out/share/doc/obelisk"
    cp -R dist "$out/lib/obelisk/"
    install -Dm644 package.json "$out/lib/obelisk/package.json"
    install -Dm644 README.md "$out/share/doc/obelisk/README.md"

    # Keep npx available for the optional skill-install subcommand without exposing Node globally.
    makeBinaryWrapper "${nodejs_24}/bin/node" "$out/bin/obelisk" \
      --add-flags "$out/lib/obelisk/dist/cli/src/obelisk.js" \
      --prefix PATH : "${nodejs_24}/bin"

    runHook postInstall
  '';

  meta = {
    description = "Local Obelisk runtime for coding agents";
    homepage = "https://github.com/tommy0103/obelisk";
    license = lib.licenses.agpl3Only;
    mainProgram = "obelisk";
    platforms = lib.platforms.linux;
  };
}
