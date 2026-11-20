{
  config,
  inputs,
  ...
}:
{
  dotnix.modules.nixos =
    { pkgs, ... }:
    let
      system = pkgs.stdenv.hostPlatform.system;
      pi = inputs.llm-agents.packages.${system}.pi;
    in
    {
      environment.systemPackages = [
        (pkgs.writeShellScriptBin "pi" ''
          export PATH="${
            pkgs.lib.makeBinPath [
              pkgs.bash
              pkgs.bun
            ]
          }:$PATH"
          export BASH_ENV=/etc/direnv/bash-env
          exec ${pi}/bin/pi "$@"
        '')
        config.flake.packages.${system}.mcp-dotnix
        config.flake.packages.${system}.mcp-nixos
      ];
    };

  dotnix.modules.home =
    {
      lib,
      osConfig,
      pkgs,
      ...
    }:
    let
      mcpPackages = config.flake.packages.${pkgs.stdenv.hostPlatform.system};

      mcpServers = {
        mcp-deepseek-search = {
          command = "${pkgs.coreutils}/bin/env";
          args = [
            "-u"
            "PYTHONPATH"
            (lib.getExe mcpPackages.mcp-deepseek-search)
          ];
          description = "Web search and webpage fetching through the DeepSeek Search & Fetch APIs.";
          # Resolve at MCP startup so plaintext stays out of the store and mcp.json.
          env.DEEPSEEK_SEARCH_API_KEY = "!${pkgs.coreutils}/bin/cat ${lib.escapeShellArg osConfig.sops.secrets.deepseek-search.path}";
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
          # Upstream never disables FastMCP's banner, which triggers a PyPI version check at startup.
          env.FASTMCP_SHOW_SERVER_BANNER = "false";
          description = "Query Nix packages, options, documentation, and flake inputs.";
          exposure = "hidden";
          timeout = 120;
          toolExposure = {
            nix = "deferred";
            nix_versions = "deferred";
          };
        };
      };

      # Only keys that differ from upstream defaults are declared; keys equal to the defaults stay out of the template.
      # Runtime keys such as lastChangelogVersion survive via the deep merge; declared keys are reasserted on every activation.
      declaredSettings = (pkgs.formats.json { }).generate "pi-declared-settings.json" {
        showCacheMissNotices = true;
        collapseChangelog = true;
        enableInstallTelemetry = false;
        quietStartup = "header";
        defaultProjectTrust = "always";
        defaultProvider = "zai-coding-cn";
        defaultModel = "glm-5.3-flash";
        defaultTools = [
          "+codemode"
          "+grep"
          "+find"
        ];
        # Proactive compaction threshold at contextWindow/e (ChatGPT/Codex auto_compact semantics):
        # reserveTokens = contextWindow − floor(contextWindow/e);
        # codex-family windows take 1,050,000 as overridden by models.json.
        compaction.modelOverrides = {
          "deepseek/deepseek-flash".reserveTokens = 632121;
          "zai-coding-cn/glm-5.3".reserveTokens = 632121;
          "zai-coding-cn/glm-5.3-flash".reserveTokens = 632121;
          "openai/gpt-6.2-sol".reserveTokens = 663727;
          "openai/gpt-6.2-astra".reserveTokens = 663727;
          "google/gemini-3.8-flash".reserveTokens = 662827;
        };
      };
      declaredMcp = (pkgs.formats.json { }).generate "pi-declared-mcp.json" { inherit mcpServers; };

      mergeObject = pkgs.writeText "pi-merge-object.jq" "$dynamic * $static";
      mergeSettings = pkgs.writeText "pi-merge-settings.jq" ''
        ($dynamic * $static)
        | del(.enabledModels)
      '';
      managedConfigs = [
        {
          name = "settings.json";
          static = declaredSettings;
          filter = mergeSettings;
        }
        {
          name = "mcp.json";
          static = declaredMcp;
          filter = mergeObject;
        }
      ];
    in
    {
      # Pi does not write back model catalogs.
      # models.json: uses GPT long-context windows, not limited to the catalog's 272k pricing tier; unknown ids are ignored.
      home.file.".pi/agent/models.json".source = ./models.json;

      # /settings and /mcp write back, so real writable files are kept; activation reasserts declared
      # keys and preserves other user settings.
      home.activation.piSettings = lib.hm.dag.entryAfter [ "linkGeneration" ] (
        ''
          merge_pi_config() (
            set -euo pipefail
            config_path="$1"
            static_path="$2"
            filter_path="$3"
            create="$4"
            snapshot_path=
            candidate_path=
            trap '[[ -z "$snapshot_path" ]] || rm -f -- "$snapshot_path"; [[ -z "$candidate_path" ]] || rm -f -- "$candidate_path"' EXIT

            if [[ -v DRY_RUN ]]; then
              echo "Would merge declared Pi config into $config_path"
              exit 0
            fi
            if [[ ! -e "$config_path" && ! -L "$config_path" ]] && (( ! create )); then
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

            if ! merged="$(${pkgs.jq}/bin/jq -n -f "$filter_path" \
              --argjson dynamic "$dynamic" \
              --argjson static "$(${pkgs.coreutils}/bin/cat "$static_path")")"; then
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
        ''
        + lib.concatMapStrings (cfg: ''
          merge_pi_config "$HOME/.pi/agent/${cfg.name}" '${cfg.static}' '${cfg.filter}' ${
            if cfg.create or true then "1" else "0"
          } || exit 1
        '') managedConfigs
      );
    };
}
