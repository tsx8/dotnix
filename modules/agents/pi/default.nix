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
    "ask-user"
    "todo"
    "pstack"
  ];
  runtimePath = name: "/run/current-system/sw/share/pi/packages/${name}";

  # The single source for agent names, bodies, tool groups, worktree membership, and the upstream
  # Cursor-field combinations. The generated files, worktree list, and build-time call mapping all
  # derive from this table; do not add a second name/mapping table elsewhere.
  agentProfiles = {
    pstack-general-purpose = {
      description = "General-purpose pstack delegate. Inherits the parent identity and keeps ordinary tools and MCP in the current directory.";
      body = null;
      tools = "ordinary";
      cursor = {
        generalPurpose = true;
        local = true;
      };
    };
    pstack-readonly = {
      description = "Read-only pstack investigator with read, grep, find, ls, and Code Mode. No shell, edit, write, or MCP.";
      body = null;
      tools = "readonly";
      cursor = {
        generalPurpose = true;
        readonly = true;
      };
    };
    pstack-general-purpose-worktree = {
      description = "General-purpose pstack delegate that runs in an isolated git worktree and saves its changes to a rescue branch.";
      body = null;
      tools = "ordinary";
      worktree = true;
      cursor = {
        generalPurpose = true;
        cloud = true;
      };
    };
    poteto-agent = {
      description = "pstack code-writing delegate spawned by poteto-mode. Reads the full poteto-mode skill before working.";
      body = "poteto-agent";
      tools = "ordinary";
      background = true;
    };
    poteto-agent-worktree = {
      description = "poteto-agent variant that runs in an isolated git worktree and saves its changes to a rescue branch.";
      body = "poteto-agent";
      tools = "ordinary";
      background = true;
      worktree = true;
    };
    comment-sicko = {
      description = "A deranged comment-hater that deletes narration and workaround comments and flags refactor targets.";
      body = "comment-sicko";
      tools = "ordinary";
    };
  };
  agentProfileNames = builtins.attrNames agentProfiles;
  profileFor =
    field:
    let
      matches = builtins.filter (name: agentProfiles.${name}.cursor.${field} or false) agentProfileNames;
    in
    if matches == [ ] then
      throw "pi agent profile table has no entry for cursor field '${field}'"
    else
      builtins.head matches;
  agentProfileMap = {
    generalPurpose = profileFor "generalPurpose";
    readonly = profileFor "readonly";
    cloud = profileFor "cloud";
    local = profileFor "local";
  };
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
          exec ${pi}/bin/pi \
            --extension ${./slash-enter.ts} \
            "$@"
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
        pi-ask-user = pkgs.callPackage ../../../packages/pi-ask-user/package.nix { };
        pi-todo = pkgs.callPackage ../../../packages/pi-todo/package.nix { };
        pi-pstack = pkgs.callPackage ../../../packages/pi-pstack/package.nix {
          inherit agentProfileNames agentProfileMap;
        };
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
      pstack = config.flake.packages.${pkgs.stdenv.hostPlatform.system}.pi-pstack;
      packagePaths = map runtimePath resourceNames;
      childExcludedPackages = lib.filter (path: !(lib.hasSuffix "/pstack" path)) packagePaths;

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
      # A subagent loads an MCP server only when its tool allowlist names a tool from it. Derive those
      # names from the declarations above instead of keeping a second server or permission list.
      mcpToolNames = lib.concatLists (
        lib.mapAttrsToList (
          server: cfg:
          map (tool: "mcp__${lib.replaceStrings [ "-" ] [ "_" ] server}__${tool}") (
            lib.attrNames (cfg.toolExposure or { })
          )
        ) mcpServers
      );
      # Ordinary delegates keep the parent's engineering surface; readonly delegates get no shell,
      # edit, write, or MCP. Code Mode is present in both because pstack uses it for structured work.
      ordinaryTools = [
        "read"
        "bash"
        "edit"
        "write"
        "grep"
        "find"
        "ls"
        "codemode"
        "tool_search"
      ]
      ++ mcpToolNames;
      readonlyTools = [
        "read"
        "grep"
        "find"
        "ls"
        "codemode"
      ];
      resolveBody =
        body: if body == null then null else "${pstack}/share/pi/packages/pstack/agents/${body}.body.md";
      resolveTools = tools: if tools == "ordinary" then ordinaryTools else readonlyTools;
      agentProfilesResolved = lib.mapAttrs (
        _: profile:
        profile
        // {
          tools = resolveTools profile.tools;
          body = resolveBody profile.body;
        }
      ) agentProfiles;
      # Worktree profiles both opt into this provider list and carry the core-enforced
      # `workspace: required` frontmatter, so a missing provider or unlisted agent type fails the run
      # instead of falling back to the parent checkout.
      worktreeAgents = lib.attrNames (
        lib.filterAttrs (_: profile: profile.worktree or false) agentProfilesResolved
      );
      # Worktree isolation sets the child's cwd. This note states the boundary explicitly because a
      # shell command can still leave that directory; the plugin is not an OS sandbox.
      worktreeNote = pkgs.writeText "pi-worktree-note.md" ''
        ## Pi worktree boundary

        Your working directory is the isolated worktree created for this run. Keep it there, use relative paths, and do not `cd` to the parent checkout, create another worktree, or write into the parent checkout. If the task needs the parent checkout, stop and report it. This is a working-directory rule, not an OS sandbox.
      '';
      agents = pkgs.runCommand "pi-pstack-agents" { } (
        ''
          mkdir -p "$out"
        ''
        + lib.concatStrings (
          lib.mapAttrsToList (
            name: profile:
            ''
              cat > "$out/${name}.md" <<'PI_AGENT_EOF'
              ---
              description: ${profile.description}
              ${lib.optionalString (profile.tools != null) "tools: ${lib.concatStringsSep ", " profile.tools}"}
              prompt_mode: append
              ${lib.optionalString (profile.background or false) "run_in_background: true"}
              ${lib.optionalString (profile.worktree or false) "workspace: required"}
              ---

              PI_AGENT_EOF
            ''
            + lib.optionalString (profile.body != null) ''
              cat ${profile.body} >> "$out/${name}.md"
            ''
            + lib.optionalString (profile.worktree or false) ''
              cat ${worktreeNote} >> "$out/${name}.md"
            ''
          ) agentProfilesResolved
        )
      );

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
        enabledModels = [
          "zai-coding-cn/glm-5.3-flash"
          "zai-coding-cn/glm-5.3"
          "deepseek/deepseek-flash"
          "openai/gpt-5.6-sol"
          "openai/gpt-6.1-terra"
          "openai/gpt-6.1-sol"
          "openai/gpt-6-astra"
          "google/gemini-3.8-flash"
          "google/gemini-4-argon"
        ];
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
          "zai-coding-cn/glm-5.3-highspeed".reserveTokens = 632121;
          "openai/gpt-6-astra".reserveTokens = 663727;
          "openai/gpt-6.1-sol".reserveTokens = 663727;
          "openai/gpt-6-sol".reserveTokens = 663727;
          "openai/gpt-6-luna".reserveTokens = 663727;
          "openai/gpt-5.6-luna".reserveTokens = 663727;
          "openai/gpt-5.6-terra".reserveTokens = 663727;
          "openai/gpt-5.6-sol".reserveTokens = 663727;
          "google/gemini-3.8-flash".reserveTokens = 662827;
        };
      };
      declaredMcp = (pkgs.formats.json { }).generate "pi-declared-mcp.json" { inherit mcpServers; };
      # Hand-edited subagent state: children must not load the parent-only delegation, questionnaire,
      # and todo extensions, while pstack's skills stay available to them.
      declaredSubagents = (pkgs.formats.json { }).generate "pi-declared-subagents.json" {
        excludedExtensionPackages = childExcludedPackages;
      };
      declaredWorktrees = (pkgs.formats.json { }).generate "pi-declared-worktrees.json" {
        inherit worktreeAgents;
      };
    in
    {
      # Pi does not write back model catalogs or keybindings; pstack setup edits its repository source.
      # models.json: uses GPT long-context windows, not limited to the catalog's 272k pricing tier; unknown ids are ignored.
      # keybindings.json: Toshy maps Cmd to Ctrl; Ctrl+Enter submits and Enter inserts a newline; new namespace ids
      # avoid triggering the legacy-format migration write-back.
      home.file = {
        ".pi/agent/AGENTS.md".source = ../AGENTS-md.txt;
        ".pi/agent/models.json".source = ./models.json;
        ".pi/agent/keybindings.json".source = ./keybindings.json;
        ".pi/agent/pstack-models.md".source = ./pstack-models.md;
      }
      // lib.mapAttrs' (
        name: _: lib.nameValuePair ".pi/agent/agents/${name}.md" { source = "${agents}/${name}.md"; }
      ) agentProfilesResolved;

      # /settings, /mcp, and /subagents:settings write back, so real writable files are kept; activation
      # reasserts declared keys and preserves other user settings.
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

          config_dir="$(${pkgs.coreutils}/bin/dirname "$config_path")"
          # Reassert the five system packages but keep packages the user added through Pi.
          if ! merged="$(${pkgs.jq}/bin/jq -n '
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
            ($dynamic * $static)
            | if ($dynamic.packages | type) == "array" then
                ($dynamic.packages) as $user
                | ($static.packages // []) as $system
                # Match local sources by Pi-resolved identity; keep the object filters on the
                # declared system source so excludedExtensionPackages still matches it.
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
          ' --arg base "$config_dir" --arg home "$HOME" --argjson dynamic "$dynamic" --argjson static "$(${pkgs.coreutils}/bin/cat "$static_path")")"; then
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
        merge_pi_config "$HOME/.pi/agent/subagents.json" '${declaredSubagents}' || exit 1
        merge_pi_config "$HOME/.pi/agent/subagents-worktrees.json" '${declaredWorktrees}' || exit 1
      '';
    };
}
