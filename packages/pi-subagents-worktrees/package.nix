{
  lib,
  stdenvNoCC,
  piPackagesSrc,
  piSubagents,
}:

stdenvNoCC.mkDerivation {
  pname = "pi-subagents-worktrees";
  inherit (lib.importJSON "${piPackagesSrc}/packages/pi-subagents-worktrees/package.json") version;

  src = piPackagesSrc;

  # Upstream 0.3.3 treats a clean worktree as having no work. A worker that commits
  # its changes leaves a clean tree with HEAD ahead of the base, so the cleanup would
  # remove the worktree and lose the detached commits. Preserve that HEAD on a rescue
  # branch before removal; the patch is pinned to this source and fails on drift.
  patches = [ ./committed-worktree.patch ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    dest="$out/share/pi/packages/subagents-worktrees"
    install -d "$dest"
    cp -R packages/pi-subagents-worktrees/src packages/pi-subagents-worktrees/package.json \
      packages/pi-subagents-worktrees/README.md packages/pi-subagents-worktrees/LICENSE \
      packages/pi-subagents-worktrees/CHANGELOG.md "$dest"/

    # The extension imports the core through its peer dependency. Pi loads local directories without
    # installing dependencies, so satisfy the peer with a link to the single core output.
    install -d "$dest/node_modules/@gotgenes"
    ln -s ${piSubagents}/share/pi/packages/subagents "$dest/node_modules/@gotgenes/pi-subagents"

    runHook postInstall
  '';

  meta = {
    description = "Git worktree isolation for @gotgenes/pi-subagents";
    homepage = "https://github.com/gotgenes/pi-packages";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
