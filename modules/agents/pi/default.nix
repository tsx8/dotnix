{ config, inputs, ... }:
{
  dotnix.modules.nixos =
    { pkgs, ... }:
    let
      system = pkgs.stdenv.hostPlatform.system;
      pi = inputs.llm-agents.packages.${system}.pi;
      adapter = config.flake.packages.${system}.pi-mcp-adapter;
      # 只注入主入口：kami/waza 插件无 agents/MCP/hooks 组件，
      # pi-subagents/jiti 仅供未注入的可选入口，不入 node_modules 闭包。
      piPlugins = config.flake.packages.${system}.pi-plugins;
    in
    {
      environment.systemPackages = [
        (pkgs.writeShellScriptBin "pi" ''
          export PATH="${pkgs.bash}/bin:$PATH"
          export BASH_ENV=/etc/direnv/bash-env
          exec ${pi}/bin/pi \
            --extension ${adapter}/index.ts \
            --extension ${piPlugins}/dist/pi/extension.js \
            --extension ${./slash-enter.ts} \
            "$@"
        '')
      ];
    };

  perSystem = { pkgs, ... }: {
    packages.pi-mcp-adapter = pkgs.callPackage ../../../packages/pi-mcp-adapter/package.nix {
      adapterSrc = inputs.pi-mcp-adapter;
    };
    packages.pi-plugins = pkgs.callPackage ../../../packages/pi-plugins/package.nix { };
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
        # 阈值 contextWindow/e 主动压缩（ChatGPT/Codex auto_compact 语义）：
        # reserveTokens = contextWindow − floor(contextWindow/e)，
        # codex 系窗口取 models.json 覆盖的 1,050,000。
        compaction.modelOverrides = {
          "zai-coding-cn/glm-5.3".reserveTokens = 632121;
          "zai-coding-cn/glm-5.3-flash".reserveTokens = 632121;
          "zai-coding-cn/glm-5.3-highspeed".reserveTokens = 632121;
          "openai-codex/gpt-6-astra".reserveTokens = 663727;
          "openai-codex/gpt-6-sol".reserveTokens = 663727;
          "openai-codex/gpt-6-luna".reserveTokens = 663727;
          "openai-codex/gpt-5.6-luna".reserveTokens = 663727;
          "openai-codex/gpt-5.6-terra".reserveTokens = 663727;
          "openai-codex/gpt-5.6-sol".reserveTokens = 663727;
          "google/gemini-flash-latest".reserveTokens = 662827;
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

      # pi 只读这些文件（/settings 只写 settings.json），故用只读 symlink。
      # models.json：openai-codex 目录默认 272k（短上下文定价档），与 codex 侧
      # models.json 的 1050000 清单对齐；spark(128k) 不覆盖，未知 id 被忽略。
      # keybindings.json：Cmd 经 Toshy 译为 Ctrl 提交、Enter 换行；新命名空间 id
      # 避免触发旧格式迁移写回。
      home.file.".pi/agent/models.json".source = ./models.json;
      home.file.".pi/agent/keybindings.json".source = ./keybindings.json;

      # MCP adapter 行为设置：结果用 boxed 渲染（自带 Box 背景）；
      # 上游把行为设置混在 mcp.json 的 settings 节，无独立插件配置接口。
      home.file.".pi/agent/mcp.json".source = ./mcp.json;

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
