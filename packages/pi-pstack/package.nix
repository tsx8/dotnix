{
  lib,
  stdenvNoCC,
  fetchurl,
  fetchFromGitHub,
  nodejs,
  agentProfileNames,
  agentProfileMap,
}:

let
  # Pinned snapshot of cursor/plugins. A bump moves upstream prose, and the transform below holds
  # exact literals from it, so it moves only when a user asks for the update, per docs/pstack-port.md.
  src = fetchFromGitHub {
    owner = "cursor";
    repo = "plugins";
    rev = "8b3326d99fd4b993cb33a24dad8af03175c642c5";
    hash = "sha256-p2cKFbYKwv3QwcIU0Gg8iLiyI+nZCsdYQuT8bkXL2nU=";
  };

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
  inherit (lib.importJSON "${src}/harness/pstack/claude-code/plugin.json") version;

  inherit src;

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
