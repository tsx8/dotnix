{ config, inputs, ... }:
{
  dotnix.modules.nixos =
    { pkgs, ... }:
    let
      system = pkgs.stdenv.hostPlatform.system;
      pi = inputs.llm-agents.packages.${system}.pi;
      # Only the main entry is injected: the kami/waza plugins have no agents/MCP/hooks components,
      # and pi-subagents/jiti serve only the non-injected optional entries, so they stay out of the node_modules closure.
      piPlugins = config.flake.packages.${system}.pi-plugins;
    in
    {
      environment.systemPackages = [
        (pkgs.writeShellScriptBin "pi" ''
          export PATH="${pkgs.bash}/bin:$PATH"
          export BASH_ENV=/etc/direnv/bash-env
          # Upstream dispatches subcommands by the first argument only; extension arguments cannot go before it.
          case "''${1-}" in
            install|remove|uninstall|update|list|config|auth|mcp)
              exec ${pi}/bin/pi "$@"
              ;;
          esac
          exec ${pi}/bin/pi \
            --extension ${piPlugins}/dist/pi/extension.js \
            --extension ${./slash-enter.ts} \
            "$@"
        '')
        config.flake.packages.${system}.mcp-dotnix
        config.flake.packages.${system}.mcp-nixos
      ];
    };

  perSystem = { pkgs, ... }: {
    packages.pi-plugins = pkgs.callPackage ../../../packages/pi-plugins/package.nix { };
  };

  dotnix.modules.home =
    { lib, pkgs, ... }:
    let
      mcpPackages = config.flake.packages.${pkgs.stdenv.hostPlatform.system};
      # Only keys that differ from upstream defaults are declared; keys equal to the defaults stay out of the template.
      # Runtime keys such as lastChangelogVersion survive via the deep merge; declared keys are reasserted on every activation.
      declaredSettings = (pkgs.formats.json { }).generate "pi-declared-settings.json" {
        showCacheMissNotices = true;
        collapseChangelog = true;
        enableInstallTelemetry = false;
        quietStartup = "header";
        defaultProjectTrust = "always";
        defaultTools = [ "+codemode" ];
        # Proactive compaction threshold at contextWindow/e (ChatGPT/Codex auto_compact semantics):
        # reserveTokens = contextWindow − floor(contextWindow/e);
        # codex-family windows take 1,050,000 as overridden by models.json.
        compaction.modelOverrides = {
          "deepseek/deepseek-flash".reserveTokens = 632121;
          "zai-coding-cn/glm-5.3".reserveTokens = 632121;
          "zai-coding-cn/glm-5.3-flash".reserveTokens = 632121;
          "zai-coding-cn/glm-5.3-highspeed".reserveTokens = 632121;
          "openai/gpt-6-astra".reserveTokens = 663727;
          "openai/gpt-6.1-sol".reserveTokens = 663727;
          "openai/gpt-6-sol".reserveTokens = 663727;
          "openai/gpt-6-luna".reserveTokens = 663727;
          "openai/gpt-5.6-luna".reserveTokens = 663727;
          "openai/gpt-5.6-terra".reserveTokens = 663727;
          "openai/gpt-5.6-sol".reserveTokens = 663727;
          "google/gemini-flash-latest".reserveTokens = 662827;
        };
      };
      declaredMcp = (pkgs.formats.json { }).generate "pi-declared-mcp.json" {
        mcpServers = {
          mcp-deepseek-search = {
            command = "${pkgs.coreutils}/bin/env";
            args = [
              "-u"
              "PYTHONPATH"
              (lib.getExe mcpPackages.mcp-deepseek-search)
            ];
            description = "Web search and webpage fetching through the DeepSeek Search & Fetch APIs.";
            exposure = "hidden";
            toolExposure = {
              search = "deferred";
              fetch = "deferred";
            };
          };
          mcp-dotnix = {
            command = "${pkgs.coreutils}/bin/env";
            args = [
              "-u"
              "PYTHONPATH"
              (lib.getExe mcpPackages.mcp-dotnix)
            ];
            description = "Local NixOS diagnostics and root command execution with desktop polkit authentication for each call.";
            exposure = "hidden";
            timeout = 600;
            toolExposure = {
              run_privileged = "deferred";
              system_status = "deferred";
              unit_status = "deferred";
              unit_journal = "deferred";
              kernel_log = "deferred";
              boot_list = "deferred";
              disk_status = "deferred";
              network_status = "deferred";
              nixos_generations = "deferred";
            };
          };
          mcp-nixos = {
            command = "${pkgs.coreutils}/bin/env";
            args = [
              "-u"
              "PYTHONPATH"
              (lib.getExe mcpPackages.mcp-nixos)
            ];
            description = "Query Nix packages, options, documentation, and flake inputs.";
            exposure = "hidden";
            timeout = 120;
            toolExposure = {
              nix = "deferred";
              nix_versions = "deferred";
            };
          };
        };
      };
      # Marketplaces and plugins are fully declared and registered/installed by plugin-ensure.sh on activation;
      # a changed store path across input updates triggers a rebuild and reinstall.
      marketplaceSources = {
        kami = "${inputs.kami}";
        waza = "${inputs.waza}";
      };
      marketplacePlugins = [
        "kami:kami"
        "waza:waza"
      ];
    in
    {
      home.file.".pi/agent/AGENTS.md".source = ../AGENTS-md.txt;

      # pi never writes these two files back, so read-only symlinks suffice.
      # models.json: uses GPT long-context windows, not limited to the catalog's 272k pricing tier; unknown ids are ignored.
      # keybindings.json: Toshy maps Cmd to Ctrl; Ctrl+Enter submits and Enter inserts a newline; new namespace ids
      # avoid triggering the legacy-format migration write-back.
      home.file.".pi/agent/models.json".source = ./models.json;
      home.file.".pi/agent/keybindings.json".source = ./keybindings.json;

      # /settings and /mcp write back, so real writable files are kept; activation reasserts declared keys and preserves other user settings.
      home.activation.piSettings = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        merge_pi_config() (
          set -euo pipefail
          config_path="$1"
          static_path="$2"
          snapshot_path=
          candidate_path=
          trap '[[ -z "$snapshot_path" ]] || rm -f -- "$snapshot_path"; [[ -z "$candidate_path" ]] || rm -f -- "$candidate_path"' EXIT

          if [[ -v DRY_RUN ]]; then
            echo "Would merge declared Pi config into $config_path"
            exit 0
          fi
          if [[ -L "$config_path" || ( -e "$config_path" && ( ! -f "$config_path" || ! -w "$config_path" ) ) ]]; then
            echo "Pi config at '$config_path' must be a regular writable file" >&2
            exit 1
          fi

          ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$config_path")" || exit 1
          dynamic='{}'
          if [[ -e "$config_path" ]]; then
            snapshot_path="$(${pkgs.coreutils}/bin/mktemp "$config_path.snapshot.XXXXXX")" || exit 1
            ${pkgs.coreutils}/bin/cp -p -- "$config_path" "$snapshot_path" || exit 1
            if ! dynamic="$(${pkgs.jq}/bin/jq -e 'select(type == "object")' "$snapshot_path" 2>/dev/null)"; then
              echo "Pi config at '$config_path' is not a JSON object; leaving the file unchanged" >&2
              exit 1
            fi
          fi

          if ! merged="$(${pkgs.jq}/bin/jq -n '$dynamic * $static' --argjson dynamic "$dynamic" --argjson static "$(${pkgs.coreutils}/bin/cat "$static_path")")"; then
            echo "Merging Pi config for '$config_path' failed" >&2
            exit 1
          fi

          candidate_path="$(${pkgs.coreutils}/bin/mktemp "$config_path.candidate.XXXXXX")" || exit 1
          printf '%s\n' "$merged" > "$candidate_path" || exit 1
          if [[ -n "$snapshot_path" ]]; then
            ${pkgs.coreutils}/bin/chmod --reference="$snapshot_path" -- "$candidate_path" || exit 1
            if [[ -L "$config_path" ]] || ! ${pkgs.diffutils}/bin/cmp -s -- "$snapshot_path" "$config_path"; then
              echo "Pi config at '$config_path' changed during activation; keeping the newer file" >&2
              exit 1
            fi
          elif [[ -e "$config_path" || -L "$config_path" ]]; then
            echo "Pi config at '$config_path' was created during activation; keeping the newer file" >&2
            exit 1
          fi
          ${pkgs.coreutils}/bin/mv -f -- "$candidate_path" "$config_path" || exit 1
          candidate_path=
        )
        merge_pi_config "$HOME/.pi/agent/settings.json" '${declaredSettings}' || exit 1
        merge_pi_config "$HOME/.pi/agent/mcp.json" '${declaredMcp}' || exit 1
      '';

      # The script rebuilds a marketplace when it is unregistered or its source path changed; installed plugins are
      # reinstalled only when their marketplace is rebuilt. Reinstallation preserves .disabled/.auto-update marks
      # and leaves other user state untouched.
      home.activation.piPluginMarketplaces = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        if [[ -v DRY_RUN ]]; then
          echo "Would ensure pi plugin marketplaces"
          exit 0
        fi
        PATH="${pkgs.coreutils}/bin:${pkgs.jq}/bin" ${pkgs.bash}/bin/bash ${./plugin-ensure.sh} "$HOME/.pi/agent" \
          ${lib.concatStringsSep " " (lib.mapAttrsToList (n: p: "${n}=${p}") marketplaceSources)} -- \
          ${lib.concatStringsSep " " marketplacePlugins} || exit 1
      '';
    };
}
