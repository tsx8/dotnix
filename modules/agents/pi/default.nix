{
  config,
  inputs,
  ...
}:

let
  # Runtime locations of the package resources. The same strings are the Pi package sources and the
  # subagent child exclusion list, so the two cannot drift apart.
  resourceNames = [
    "subagents"
    "subagents-worktrees"
    "todo"
  ];
  runtimePath = name: "/run/current-system/sw/share/pi/packages/${name}";

  # Paths managed by earlier generations. Activation removes them from writable user config instead of
  # leaving them looking like packages the user added.
  legacyPackagePaths = [
    (runtimePath "ask-user")
    (runtimePath "pstack")
  ];
  legacyWorktreeAgents = [
    "pstack-general-purpose-worktree"
    "poteto-agent-worktree"
  ];
in
{
  dotnix.modules.nixos =
    { pkgs, ... }:
    let
      system = pkgs.stdenv.hostPlatform.system;
      pi = inputs.llm-agents.packages.${system}.pi;
      packages = config.flake.packages.${system};
      resources = map (name: packages.${"pi-${name}"}) resourceNames;
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
          # Upstream dispatches subcommands by the first argument only; extension arguments cannot go before it.
          case "''${1-}" in
            install|remove|uninstall|update|list|config|auth|mcp)
              exec ${pi}/bin/pi "$@"
              ;;
          esac
          exec ${pi}/bin/pi "$@"
        '')
        config.flake.packages.${system}.mcp-dotnix
        config.flake.packages.${system}.mcp-nixos
      ]
      ++ resources;
    };

  perSystem =
    { pkgs, self', ... }:
    {
      packages = {
        pi-subagents = pkgs.callPackage ../../../packages/pi-subagents/package.nix {
          piPackagesSrc = inputs.pi-packages;
        };
        pi-subagents-worktrees = pkgs.callPackage ../../../packages/pi-subagents-worktrees/package.nix {
          piPackagesSrc = inputs.pi-packages;
          piSubagents = self'.packages.pi-subagents;
        };
        pi-todo = pkgs.callPackage ../../../packages/pi-todo/package.nix { };
      };
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
      packagePaths = map runtimePath resourceNames;

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
        mcp-bex = {
          command = "${pkgs.coreutils}/bin/env";
          args = [
            "-u"
            "PYTHONPATH"
            (lib.getExe mcpPackages.mcp-bex)
          ];
          env.BEX_BIN = "/run/current-system/sw/bin/bex";
          description = "Real logged-in Helium browser through hidden CDP tabs and persistent jobs.";
          exposure = "hidden";
          # Above the 600 s bex tool maximum plus the adapter backstop.
          timeout = 650;
          toolExposure = {
            run = "deferred";
            job_start = "deferred";
            job_run = "deferred";
            job_status = "deferred";
            job_stop = "deferred";
            job_action = "deferred";
            job_handoff = "deferred";
            job_release = "deferred";
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
        packages = packagePaths;
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
      # Hand-edited subagent state: children must not load the parent-only delegation and todo extensions.
      declaredSubagents = (pkgs.formats.json { }).generate "pi-declared-subagents.json" {
        excludedExtensionPackages = packagePaths;
      };
      declaredWorktrees = (pkgs.formats.json { }).generate "pi-declared-worktrees.json" { };

      # Merge programs shared by several writable files. Local sources are compared by Pi-resolved
      # identity so an object filter on a managed package keeps matching its source after a move.
      identityHelpers = ''
        def source_of: if type == "string" then . elif type == "object" then .source else . end;
        def local_identity($base; $home):
          source_of
          | if type != "string" then .
            elif test("^[A-Za-z][A-Za-z0-9+.-]*:") then .
            elif startswith("/") or startswith("~/") or startswith("./") or startswith("../") or test("^[^:]+$") then
              (if startswith("~/") then ($home + "/" + .[2:])
               elif . == "~" then $home
               elif startswith("/") then .
               else ($base + "/" + .) end)
              | split("/")
              | reduce .[] as $part ([];
                  if $part == "" or $part == "." then .
                  elif $part == ".." then (if length > 0 then .[:-1] else . end)
                  else . + [$part] end)
              | "/" + join("/")
            else . end;
      '';
      mergeObject = pkgs.writeText "pi-merge-object.jq" "$dynamic * $static";
      mergeSettings = pkgs.writeText "pi-merge-settings.jq" ''
        ${identityHelpers}
        ($dynamic * $static)
        | del(.enabledModels)
        | if ($dynamic.packages | type) == "array" then
            ($dynamic.packages
              | map(select((local_identity($base; $home)) as $id | any($legacy[]; . == $id) | not))) as $user
            | ($static.packages // []) as $system
            # Keep object filters on the declared system source so excludedExtensionPackages still matches it.
            | ([ $system[] as $src
                 | (($user
                     | map(select(local_identity($base; $home) == ($src | local_identity($base; $home))))
                     | first) // $src)
                 | if type == "object" then .source = $src else $src end ]) as $system_block
            # Preserve non-system user extras in first-occurrence order after the system block.
            | ($user
                | reduce .[] as $item ([];
                    ($item | local_identity($base; $home)) as $id
                    | if any(.[]; local_identity($base; $home) == $id) then .
                    elif any($system[]; local_identity($base; $home) == $id) then .
                    else . + [$item] end)) as $extras
            | .packages = ($system_block + $extras)
          else .
          end
      '';
      mergeSubagents = pkgs.writeText "pi-merge-subagents.jq" ''
        ${identityHelpers}
        ($dynamic * $static)
        | if ($dynamic.excludedExtensionPackages | type) == "array" then
            ($dynamic.excludedExtensionPackages
              | map(select((local_identity($base; $home)) as $id | any($legacy[]; . == $id) | not))) as $kept
            | ($static.excludedExtensionPackages // []) as $declared
            | .excludedExtensionPackages = (
                $kept
                + [ $declared[] as $src
                    | select(any($kept[]; local_identity($base; $home) == ($src | local_identity($base; $home))) | not)
                    | $src ]
              )
          else .
          end
      '';
      mergeWorktrees = pkgs.writeText "pi-merge-worktrees.jq" ''
        ($dynamic * $static)
        | if (.worktreeAgents | type) == "array" then
            .worktreeAgents = [
              .worktreeAgents[]
              | select(. as $name | any($legacyWorktrees[]; . == $name) | not)
            ]
          else .
          end
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
        {
          name = "subagents.json";
          static = declaredSubagents;
          filter = mergeSubagents;
        }
        {
          name = "subagents-worktrees.json";
          static = declaredWorktrees;
          filter = mergeWorktrees;
          create = false;
        }
      ];
    in
    {
      # Pi does not write back model catalogs.
      # models.json: uses GPT long-context windows, not limited to the catalog's 272k pricing tier; unknown ids are ignored.
      home.file.".pi/agent/models.json".source = ./models.json;

      # /settings, /mcp, and /subagents:settings write back, so real writable files are kept; activation
      # reasserts declared keys and preserves other user settings.
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

            config_dir="$(${pkgs.coreutils}/bin/dirname "$config_path")"
            if ! merged="$(${pkgs.jq}/bin/jq -n -f "$filter_path" \
              --arg base "$config_dir" --arg home "$HOME" \
              --argjson dynamic "$dynamic" \
              --argjson static "$(${pkgs.coreutils}/bin/cat "$static_path")" \
              --argjson legacy '${builtins.toJSON legacyPackagePaths}' \
              --argjson legacyWorktrees '${builtins.toJSON legacyWorktreeAgents}')"; then
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
