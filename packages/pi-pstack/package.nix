{
  lib,
  stdenvNoCC,
  fetchurl,
  nodejs,
  cursorPlugins,
  agentProfileNames,
  agentProfileMap,
}:

let
  # pstack's helper scripts import commander as a production dependency. Pi never installs
  # dependencies for local packages, so vendor it and record the bootstrap install key instead.
  commander = stdenvNoCC.mkDerivation {
    pname = "commander";
    version = "14.0.0";

    src = fetchurl {
      url = "https://registry.npmjs.org/commander/-/commander-14.0.0.tgz";
      hash = "sha256-6u86aX5xc8c0fKTB5g3SvB04IU0qrszonXCIGlHX/ec=";
    };

    dontBuild = true;

    installPhase = ''
      runHook preInstall
      install -d "$out"
      cp -R . "$out/package"
      runHook postInstall
    '';
  };
in
stdenvNoCC.mkDerivation {
  pname = "pi-pstack";
  inherit (lib.importJSON "${cursorPlugins}/harness/pstack/claude-code/plugin.json") version;

  src = cursorPlugins;

  nativeBuildInputs = [ nodejs ];
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    dest="$out/share/pi/packages/pstack"
    install -d "$dest"
    PSTACK_ROOT="$dest" \
      PSTACK_AGENT_TYPES="${lib.concatStringsSep "," agentProfileNames}" \
      PSTACK_PROFILE_MAP='${builtins.toJSON agentProfileMap}' \
      node ${./prepare.mjs} "$src" "$dest"

    install -d "$dest/skills/poteto-mode/scripts/node_modules"
    cp -R ${commander}/package "$dest/skills/poteto-mode/scripts/node_modules/commander"
    install -m 0644 ${./pi.md} "$dest/pi.md"

    runHook postInstall
  '';

  meta = {
    description = "pstack agent workflow ported to Pi";
    homepage = "https://github.com/cursor/plugins";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
