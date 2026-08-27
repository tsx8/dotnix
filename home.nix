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

  programs.deepseek-harness = {
    enable = true;
    # 应用由 NixOS 系统级安装
    package = null;

    agentsFile = ./dsh/AGENTS.md;

    profiles.next = {
      # 这些插件只为补官方预置未覆盖的能力而存在；每次上游 dsh 更新后
      # 逐一复查：官方是否已覆盖其能力、是否需要升级跟随、是否需要暂时禁用。
      dependencies = {
        # 上下文统计展示，官方预置无此能力
        "dsh-context" = "0.34.0";
      };
      bundles = [
        "@deepseek-ai/dsh-base"
        "@deepseek-ai/dsh-web-app"
        "dsh-context"
      ];
      cordisPatch = [ ];
      pnpmDepsHash = "sha256-YHf6ILWUt4Ad4RcSVI8F834gj7EIhuFyz6sWUe4M9oY=";
    };
  };

  programs.fish = {
    enable = true;
    # dsh 内置的 `web` 是 --profile web 的别名，这里给 next profile 一个
    # 等价快捷命令：dsh next ≡ dsh --profile next，其余参数照常转发
    functions.dsh = ''
      if test "$argv[1]" = "next"
        set -e argv[1]
        command dsh --profile next $argv
      else
        command dsh $argv
      end
    '';
  };

  # fish 模块默认开启 man 缓存（供 apropos 补全），但 home.packages 不含
  # man pages（仓库原则），mandb 对空目录不产出导致构建失败，显式关闭
  programs.man.generateCaches = false;

  # 仓库原则：应用不进用户环境
  home.packages = lib.mkForce [
    config.home.sessionVariablesPackage
  ];

  home.file.".dsh/.credentials.yaml".source =
    config.lib.file.mkOutOfStoreSymlink
      osConfig.sops.templates."dsh-credentials.yaml".path;

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
      autosave.after_delay.milliseconds = 0;

      auto_update = false;
      base_keymap = "VSCode";

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
