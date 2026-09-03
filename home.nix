{
  config,
  lib,
  osConfig,
  pkgs,
  rimeFrostSource,
  ...
}:

let
  rimeFrostData = pkgs.runCommand "rime-frost-data" { } ''
    mkdir -p "$out/share/rime-data"
    cp -r ${rimeFrostSource}/. "$out/share/rime-data/"
  '';

  rimeLocalData = pkgs.runCommand "rime-local-data" { } ''
    mkdir -p "$out/share/rime-data/lua"

    cp ${./rime/default.custom.yaml} \
      "$out/share/rime-data/default.custom.yaml"

    cp ${./rime/rime_frost.custom.yaml} \
      "$out/share/rime-data/rime_frost.custom.yaml"

    cp ${./rime/lua/direct_uppercase.lua} \
      "$out/share/rime-data/lua/direct_uppercase.lua"

    cp ${./rime/lua/post_commit_reject.lua} \
      "$out/share/rime-data/lua/post_commit_reject.lua"
  '';

  rimeData = pkgs.symlinkJoin {
    name = "rime-data";
    paths = [
      rimeFrostData
      rimeLocalData
    ];
  };

  rimeBuildDir = "${config.xdg.cacheHome}/fcitx5-rime";

  fcitx5Remote = "${osConfig.i18n.inputMethod.package}/bin/fcitx5-remote";

  busctl = lib.getExe' pkgs.systemd "busctl";
in
{
  home.stateVersion = "26.05";

  programs.fish = {
    enable = true;
  };

  # fish 模块默认开启 man 缓存（供 apropos 补全），但 home.packages 不含
  # man pages（仓库原则），mandb 对空目录不产出导致构建失败，显式关闭
  programs.man.generateCaches = false;

  # 仓库原则：应用不进用户环境
  home.packages = lib.mkForce [
    config.home.sessionVariablesPackage
  ];

  home.file.".config/sops/age/keys.txt".source =
    config.lib.file.mkOutOfStoreSymlink "/var/lib/sops-nix/key.txt";

  xdg.dataFile = {
    "fcitx5/rime" = {
      source = "${rimeData}/share/rime-data";
      recursive = true;
    };

    "fcitx5/rime/build".source = config.lib.file.mkOutOfStoreSymlink rimeBuildDir;

    "fcitx5/rime/.dotnix-generation" = {
      text = "${rimeData}\n";

      onChange = ''
        rimeDataChanged=1
      '';
    };
  };

  home.activation.deployRime = lib.hm.dag.entryAfter [ "onFilesChange" ] ''
    run mkdir -p ${lib.escapeShellArg rimeBuildDir}

    if [[ -v rimeDataChanged ]]; then
      # Nix Store 的 mtime 被规范化，不能依赖 librime 的增量时间戳判断。
      run rm -rf ${lib.escapeShellArg rimeBuildDir}
      run mkdir -p ${lib.escapeShellArg rimeBuildDir}

      # Fcitx 未运行时，让下次 Rime 启动也能检测到 user-data root 变化。
      run touch ${lib.escapeShellArg "${config.xdg.dataHome}/fcitx5/rime"}

      if ${fcitx5Remote} --check >/dev/null 2>&1; then
        run ${busctl} --user call \
          org.fcitx.Fcitx5 \
          /controller \
          org.fcitx.Fcitx.Controller1 \
          SetConfig \
          sv \
          fcitx://config/addon/rime/deploy \
          s ""
      fi
    fi
  '';

  home.file.".codex/models.json".text = ''
    {
      "models": [
        {
          "slug": "glm-5.3",
          "display_name": "glm-5.3",
          "description": "Z.ai's latest flagship model",
          "default_reasoning_level": "high",
          "supported_reasoning_levels": [
            { "effort": "low",  "description": "Light reasoning" },
            { "effort": "high", "description": "Enhanced reasoning" },
            { "effort": "max",  "description": "Deep reasoning" }
          ],
          "shell_type": "shell_command",
          "visibility": "list",
          "supported_in_api": true,
          "priority": 0,
          "base_instructions": "",
          "supports_reasoning_summaries": true,
          "default_reasoning_summary": "none",
          "support_verbosity": false,
          "apply_patch_tool_type": "freeform",
          "truncation_policy": { "mode": "bytes", "limit": 10000 },
          "context_window": 1048576,
          "max_context_window": 1048576,
          "effective_context_window_percent": 95,
          "supports_parallel_tool_calls": true,
          "experimental_supported_tools": [],
          "input_modalities": [ "text" ]
        },
        {
          "slug": "glm-5.3-flash",
          "display_name": "glm-5.3-flash",
          "description": "GLM-5 series first native multimodal model",
          "default_reasoning_level": "low",
          "supported_reasoning_levels": [
            { "effort": "low",  "description": "Light reasoning" },
            { "effort": "high", "description": "Enhanced reasoning" },
            { "effort": "max",  "description": "Deep reasoning" }
          ],
          "shell_type": "shell_command",
          "visibility": "list",
          "supported_in_api": true,
          "priority": 1,
          "base_instructions": "",
          "supports_reasoning_summaries": true,
          "default_reasoning_summary": "none",
          "support_verbosity": false,
          "apply_patch_tool_type": "freeform",
          "truncation_policy": { "mode": "bytes", "limit": 10000 },
          "context_window": 1048576,
          "max_context_window": 1048576,
          "effective_context_window_percent": 95,
          "supports_parallel_tool_calls": false,
          "experimental_supported_tools": [],
          "input_modalities": [ "text", "image" ]
        }
      ]
    }
  '';

  home.file.".codex/AGENTS.md".source = ./codex/AGENTS-md.txt;

  programs.git = {
    enable = true;
    package = null;

    settings = {
      user = {
        name = "tsx8";
        email = "tangsongxiaoba@163.com";
      };

      credential."https://github.com".helper = "!gh auth git-credential";
    };
  };

  programs.zed-editor = {
    enable = true;
    package = null;

    mutableUserSettings = false;

    extensions = [
      "nix"
    ];

    userSettings = {
      agent.button = false;
      autosave.after_delay.milliseconds = 0;

      auto_update = false;
      base_keymap = "VSCode";

      edit_predictions.provider = "none";

      languages.Nix.language_servers = [
        "nixd"
        "!nil"
      ];

      lsp.gopls.binary.path_lookup = true;

      session.trust_all_worktrees = true;

      terminal = {
        env = {
          EDITOR = "zeditor --wait";
          VISUAL = "zeditor --wait";
        };
      };
    };
  };
}
