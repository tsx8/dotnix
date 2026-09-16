{ config, inputs, ... }:
{
  dotnix.modules.nixos =
    { pkgs, ... }:
    let
      system = pkgs.stdenv.hostPlatform.system;
      pi = inputs.llm-agents.packages.${system}.pi;
      adapter = config.flake.packages.${system}.pi-mcp-adapter;
    in
    {
      environment.systemPackages = [
        (pkgs.writeShellScriptBin "pi" ''
          export PATH="${pkgs.bash}/bin:$PATH"
          export BASH_ENV=/etc/direnv/bash-env
          exec ${pi}/bin/pi --extension ${adapter}/node_modules/pi-mcp-adapter/index.ts "$@"
        '')
      ];
    };

  perSystem = { pkgs, ... }: {
    packages.pi-mcp-adapter = pkgs.callPackage ../../../packages/pi-mcp-adapter/package.nix { };
  };

  dotnix.modules.home =
    { lib, pkgs, ... }:
    let
      # 仅声明与上游默认不同的键；与默认相同的不入模板。
      # lastChangelogVersion 等运行时键由深合并保留，声明键在每次激活时重申。
      declaredSettings = (pkgs.formats.json { }).generate "pi-declared-settings.json" {
        defaultProvider = "zai-coding-cn";
        defaultModel = "glm-5.3";
        showCacheMissNotices = true;
        collapseChangelog = true;
        enableInstallTelemetry = false;
        quietStartup = true;
        defaultProjectTrust = "always";
        tuiMode = "fullscreen";
      };
    in
    {
      home.file.".pi/agent/skills/obelisk".source = "${inputs.obelisk-skill}/skills/obelisk";

      # settings.json 必须保持真实可写文件（pi /settings 原地写入），
      # 故不用 home.file symlink，而在激活时按声明键深合并（zed/vscode mutableUserSettings 模式）。
      home.activation.piSettings = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        (
          set -euo pipefail
          settings_path="$HOME/.pi/agent/settings.json"
          static_path='${declaredSettings}'
          snapshot_path=
          candidate_path=
          trap '[[ -z "$snapshot_path" ]] || rm -f -- "$snapshot_path"; [[ -z "$candidate_path" ]] || rm -f -- "$candidate_path"' EXIT

          if [[ -v DRY_RUN ]]; then
            echo "Would merge declared settings into $settings_path"
            exit 0
          fi

          ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$settings_path")"
          dynamic='{}'
          if [[ -e "$settings_path" ]]; then
            snapshot_path="$(${pkgs.coreutils}/bin/mktemp "$settings_path.snapshot.XXXXXX")"
            ${pkgs.coreutils}/bin/cp -p -- "$settings_path" "$snapshot_path"
            if ! dynamic="$(${pkgs.jq}/bin/jq . "$snapshot_path" 2>/dev/null)"; then
              echo "pi settings at '$settings_path' is not valid JSON; leaving the file unchanged" >&2
              exit 1
            fi
          fi

          if ! merged="$(${pkgs.jq}/bin/jq -n '$dynamic * $static' --argjson dynamic "$dynamic" --argjson static "$(${pkgs.coreutils}/bin/cat "$static_path")")"; then
            echo "Merging pi settings for '$settings_path' failed" >&2
            exit 1
          fi

          candidate_path="$(${pkgs.coreutils}/bin/mktemp "$settings_path.candidate.XXXXXX")"
          printf '%s\n' "$merged" > "$candidate_path"
          if [[ -n "$snapshot_path" ]]; then
            ${pkgs.coreutils}/bin/chmod --reference="$snapshot_path" -- "$candidate_path"
            if ! ${pkgs.diffutils}/bin/cmp -s -- "$snapshot_path" "$settings_path"; then
              echo "pi settings at '$settings_path' changed during activation; keeping the newer file" >&2
              exit 1
            fi
          fi
          ${pkgs.coreutils}/bin/mv -f -- "$candidate_path" "$settings_path"
          candidate_path=
        ) || exit 1
      '';
    };
}
