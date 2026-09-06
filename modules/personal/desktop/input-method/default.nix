{ inputs, ... }: {
  dotnix.modules.nixos =
    { config, pkgs, ... }:
    let
      fcitx5Rime = pkgs.fcitx5-rime.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          # 保留声明式配置入口，但不在托盘菜单暴露 Rime 运行时操作。
          sed -i \
            -e '/imAction_->setMenu/d' \
            -e '/registerAction("fcitx-rime-separator"/,/);/d' \
            -e '/registerAction("fcitx-rime-deploy"/,/);/d' \
            -e '/registerAction("fcitx-rime-sync"/,/);/d' \
            -e '/updateSchemaMenu();/d' \
            src/rimeengine.cpp

          substituteInPlace src/rime.conf.in \
            --replace-fail 'Configurable=True' 'Configurable=False'
        '';
      });
    in
    {
      i18n.inputMethod = {
        enable = true;
        type = "fcitx5";

        fcitx5 = {
          waylandFrontend = true;

          addons = [
            fcitx5Rime
          ];

          settings.inputMethod = {
            "Groups/0" = {
              Name = "Default";
              "Default Layout" = "us";
              DefaultIM = "rime";
            };

            "Groups/0/Items/0" = {
              Name = "keyboard-us";
              Layout = "";
            };

            "Groups/0/Items/1" = {
              Name = "rime";
              Layout = "";
            };

            GroupOrder = {
              "0" = "Default";
            };
          };

          settings.globalOptions = {
            "Hotkey" = {
              # 点按 CapsLock 由 keyd 转为该组合键，切换 keyboard-us ↔ rime
              "EnumerateWithTriggerKeys" = "False";
            };

            # 键列表用编号子节，写成标量会被静默忽略
            "Hotkey/TriggerKeys" = {
              "0" = "Control+space";
            };

            # Shift 已用于大写直上屏，禁用 AltTrigger 的临时切换
            "Hotkey/AltTriggerKeys" = {
              "0" = "";
            };
          };

          settings.addons = {
            # 对齐 macOS：切走时上屏原始拼音（默认上屏中文）
            rime.globalSection.SwitchInputMethodBehavior = "Commit raw input";
          };
        };
      };

      environment.etc."xdg/kwinrc".text = ''
        [Wayland]
        InputMethod=${config.i18n.inputMethod.package}/share/applications/fcitx5-wayland-launcher.desktop
      '';
    };
  dotnix.modules.home =
    {
      config,
      lib,
      osConfig,
      pkgs,
      ...
    }:
    let
      rimeFrostData = pkgs.runCommand "rime-frost-data" { } ''
        mkdir -p "$out/share/rime-data"
        cp -r ${inputs.rime-frost}/. "$out/share/rime-data/"
      '';

      rimeLocalData = pkgs.runCommand "rime-local-data" { } ''
        mkdir -p "$out/share/rime-data/lua"

        cp ${./default.custom.yaml} \
          "$out/share/rime-data/default.custom.yaml"

        cp ${./rime_frost.custom.yaml} \
          "$out/share/rime-data/rime_frost.custom.yaml"

        cp ${./lua/direct_uppercase.lua} \
          "$out/share/rime-data/lua/direct_uppercase.lua"

        cp ${./lua/post_commit_reject.lua} \
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
    };
}
