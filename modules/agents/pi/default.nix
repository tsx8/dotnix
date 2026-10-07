{ config, inputs, ... }:
{
  dotnix.modules.nixos =
    { pkgs, ... }:
    let
      system = pkgs.stdenv.hostPlatform.system;
      pi = inputs.llm-agents.packages.${system}.pi;
      # 只注入主入口：kami/waza 插件无 agents/MCP/hooks 组件，
      # pi-subagents/jiti 仅供未注入的可选入口，不入 node_modules 闭包。
      piPlugins = config.flake.packages.${system}.pi-plugins;
    in
    {
      environment.systemPackages = [
        (pkgs.writeShellScriptBin "pi" ''
          export PATH="${pkgs.bash}/bin:$PATH"
          export BASH_ENV=/etc/direnv/bash-env
          # 上游仅按首参数分派子命令，不能在其前注入扩展参数。
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
      # 仅声明与上游默认不同的键；与默认相同的不入模板。
      # lastChangelogVersion 等运行时键由深合并保留，声明键在每次激活时重申。
      declaredSettings = (pkgs.formats.json { }).generate "pi-declared-settings.json" {
        defaultProvider = "zai-coding-cn";
        defaultModel = "glm-5.3";
        showCacheMissNotices = true;
        collapseChangelog = true;
        enableInstallTelemetry = false;
        quietStartup = "header";
        defaultProjectTrust = "always";
        defaultTools = [ "+codemode" ];
        # 阈值 contextWindow/e 主动压缩（ChatGPT/Codex auto_compact 语义）：
        # reserveTokens = contextWindow − floor(contextWindow/e)，
        # codex 系窗口取 models.json 覆盖的 1,050,000。
        compaction.modelOverrides = {
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
      # 市场与插件全量声明，激活时由 plugin-ensure.sh 登记/安装；store 路径随
      # 输入变化时重建重装。
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

      # pi 不回写这两个文件，故用只读 symlink。
      # models.json：使用 GPT 长上下文窗口，不限于目录的 272k 定价档；未知 id 被忽略。
      # keybindings.json：Cmd 经 Toshy 译为 Ctrl 提交、Enter 换行；新命名空间 id
      # 避免触发旧格式迁移写回。
      home.file.".pi/agent/models.json".source = ./models.json;
      home.file.".pi/agent/keybindings.json".source = ./keybindings.json;

      # /settings 和 /mcp 会回写，保持真实可写文件；激活重申声明键，保留其余用户设置。
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

      # 市场未登记或源路径变化时由脚本重建；已装插件仅在对应市场重建时重装，
      # 重装保留 .disabled/.auto-update 标记，其余用户状态不动。
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
