{
  lib,
  stdenvNoCC,
  piPackagesSrc,
}:

stdenvNoCC.mkDerivation {
  pname = "pi-subagents";
  inherit (lib.importJSON "${piPackagesSrc}/packages/pi-subagents/package.json") version;

  src = piPackagesSrc;

  # A qualified provider/model must resolve exactly; upstream fuzzy matching could silently
  # substitute a different available model when the configured role is stale.
  patches = [
    ./fail-closed-qualified-model.patch
    ./fail-closed-workspace.patch
  ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    dest="$out/share/pi/packages/subagents"
    install -d "$dest"
    cp -R packages/pi-subagents/src packages/pi-subagents/package.json \
      packages/pi-subagents/README.md packages/pi-subagents/LICENSE \
      packages/pi-subagents/CHANGELOG.md "$dest"/

    runHook postInstall
  '';

  meta = {
    description = "In-process sub-agent core for Pi";
    homepage = "https://github.com/gotgenes/pi-packages";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
