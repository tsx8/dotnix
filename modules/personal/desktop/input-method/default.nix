{ inputs, ... }: {
  dotnix.modules.nixos =
    { config, pkgs, ... }:
    let
      fcitx5Rime = pkgs.fcitx5-rime.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [
          ./rime-editing-order.patch
        ];
        postPatch = (old.postPatch or "") + ''
          # Keep the declarative config entry points, but stop exposing Rime runtime actions in the tray menu.
          sed -i \
            -e '/imAction_->setMenu/d' \
            -e '/registerAction("fcitx-rime-separator"/,/);/d' \
            -e '/registerAction("fcitx-rime-deploy"/,/);/d' \
            -e '/registerAction("fcitx-rime-sync"/,/);/d' \
            -e '/updateSchemaMenu();/d' \
            src/rimeengine.cpp

          substituteInPlace src/rime.conf.in \
            --replace-fail 'Configurable=True' 'Configurable=False'

          # The editing macro must also record the first-step state during raw ASCII input.
          substituteInPlace src/rime-addon.conf.in.in \
            --replace-fail 'OnDemand=True' 'OnDemand=False'
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
              # Tapping CapsLock is translated by Toshy into this chord, switching keyboard-us ↔ rime
              "EnumerateWithTriggerKeys" = "False";
            };

            # Key lists use numbered subsections; scalars are silently ignored
            "Hotkey/TriggerKeys" = {
              "0" = "Control+space";
            };

            # Shift already commits uppercase directly; disable the AltTrigger temporary switch
            "Hotkey/AltTriggerKeys" = {
              "0" = "";
            };
          };

          settings.addons = {
            # Toshy uses Super for Mac Control; the Quick Phrase default hotkey would steal application shortcuts.
            quickphrase = {
              globalSection = { };
              sections.TriggerKey."0" = "";
            };
            # Match macOS: commit the raw pinyin when switching away (default commits Chinese)
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
          # Nix Store mtimes are normalized, so librime's incremental timestamp check cannot be relied on.
          run rm -rf ${lib.escapeShellArg rimeBuildDir}
          run mkdir -p ${lib.escapeShellArg rimeBuildDir}

          # When Fcitx is not running, let the next Rime startup also detect the user-data root change.
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
