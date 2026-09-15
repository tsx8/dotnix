{ config, inputs, ... }:
let
  userName = config.dotnix.host.userName;
  toshyModule = { pkgs, ... }: {
    _module.args.toshyPackage = pkgs.callPackage ../../../../packages/toshy {
      toshySrc = inputs.toshy;
    };
  };
in
{
  perSystem = { pkgs, ... }: {
    packages.toshy = pkgs.callPackage ../../../../packages/toshy {
      toshySrc = inputs.toshy;
    };
  };
  dotnix.modules.nixos =
    {
      config,
      pkgs,
      toshyPackage,
      ...
    }:
    let
      macKeyboard = pkgs.callPackage ../../../../packages/mac-keyboard { };
    in
    {
      imports = [
        toshyModule
        inputs.toshy.nixosModules.toshy
      ];
      services.toshy = {
        enable = true;
        users = [ userName ];
      };
      environment.systemPackages = [ toshyPackage ];
      services.xserver.xkb = {
        dir = "${macKeyboard}/etc/X11/xkb";
        layout = "us";
        options = "";
      };
      environment.sessionVariables.XKB_CONFIG_ROOT = config.services.xserver.xkb.dir;
      systemd.user.services.toshy-kwin-dbus = {
        description = "Toshy Plasma window context";
        after = [ "graphical-session.target" ];
        partOf = [ "graphical-session.target" ];
        wantedBy = [ "graphical-session.target" ];
        unitConfig.ConditionUser = userName;
        environment = {
          XDG_SESSION_TYPE = "wayland";
          XDG_CURRENT_DESKTOP = "KDE";
          PYTHONDONTWRITEBYTECODE = "1";
        };
        serviceConfig = {
          Type = "dbus";
          BusName = "org.toshy.Plasma";
          ExecStart = "${toshyPackage}/bin/toshy-kwin-dbus";
          Restart = "on-failure";
          RestartSec = 3;
        };
        postStart = ''
          ${pkgs.systemd}/bin/busctl --user call org.kde.KWin /Scripting \
            org.kde.kwin.Scripting unloadScript s toshy-dbus-notifyactivewindow
          ${pkgs.systemd}/bin/busctl --user call org.kde.KWin /Scripting \
            org.kde.kwin.Scripting loadScript ss \
            ${toshyPackage}/share/kwin/scripts/toshy-dbus-notifyactivewindow/contents/code/main.js \
            toshy-dbus-notifyactivewindow
          ${pkgs.systemd}/bin/busctl --user call org.kde.KWin /Scripting org.kde.kwin.Scripting start
        '';
      };
      systemd.user.services.toshy = {
        description = "Toshy keyboard remapping";
        after = [
          "graphical-session.target"
          "toshy-kwin-dbus.service"
        ];
        wants = [ "toshy-kwin-dbus.service" ];
        partOf = [ "graphical-session.target" ];
        wantedBy = [ "graphical-session.target" ];
        unitConfig.ConditionUser = userName;
        restartTriggers = [
          config.home-manager.users.${userName}.xdg.configFile."toshy/toshy_config.py".source
          config.home-manager.users.${userName}.xdg.configFile."toshy/desktop-bindings.json".source
        ];
        environment = {
          XDG_SESSION_TYPE = "wayland";
          XDG_CURRENT_DESKTOP = "KDE";
          PYTHONDONTWRITEBYTECODE = "1";
        };
        serviceConfig = {
          ExecStart = "${toshyPackage}/bin/toshy-session";
          Restart = "on-failure";
          RestartSec = 3;
          TimeoutStopSec = 5;
        };
      };
    };
  dotnix.modules.home =
    { lib, pkgs, ... }:
    let
      desktop = builtins.fromJSON (builtins.readFile ./desktop-bindings.json);
      toshy = pkgs.callPackage ../../../../packages/toshy {
        toshySrc = inputs.toshy;
      };
      insertSlice =
        name: text: content:
        assert lib.assertMsg (
          builtins.length (
            lib.splitString "###  SLICE_MARK_START: ${name}  ###  EDITS OUTSIDE THESE MARKS WILL BE LOST ON UPGRADE" content
          ) == 2
        ) "Toshy configuration slice ${name} changed upstream";
        lib.replaceStrings
          [ "###  SLICE_MARK_START: ${name}  ###  EDITS OUTSIDE THESE MARKS WILL BE LOST ON UPGRADE" ]
          [ "###  SLICE_MARK_START: ${name}\n${text}" ]
          content;
      configText =
        builtins.foldl' (content: slice: insertSlice slice.name slice.text content)
          (builtins.readFile "${inputs.toshy}/default-toshy-config/toshy_config.py")
          [
            {
              name = "user_custom_lists";
              text = ''
                browsers_chrome.append("helium")
                browsers_chromeStr = toRgxStr(browsers_chrome)
                browsers_all.append("helium")
                browsers_allStr = toRgxStr(browsers_all)
              '';
            }
            {
              name = "user_custom_modmaps";
              text = builtins.readFile ./modmaps.py;
            }
            {
              name = "user_apps";
              text = ''
                import dbus
                _desktop_programs = {"spectacle": "${pkgs.kdePackages.spectacle}/bin/spectacle"}
              ''
              + builtins.readFile ./desktop.py
              + "\n"
              + builtins.readFile ./keymaps.py;
            }
          ];
    in
    {
      xdg.configFile = {
        "toshy/toshy_config.py".text = configText;
        "toshy/toshy_common".source = "${toshy}/share/toshy/toshy_common";
        "toshy/assets".source = "${toshy}/share/toshy/assets";
        "toshy/desktop-bindings.json".source = ./desktop-bindings.json;
      };
      qt.kde.settings.kwinrc = {
        Plugins.toshy-dbus-notifyactivewindowEnabled = true;
        Plugins.invertEnabled = true;
        TabBox.ApplicationsMode = 1;
      };
      qt.kde.settings.kxkbrc.Layout = {
        Use = true;
        LayoutList = "us";
        VariantList = "";
        Options = "";
        ResetOldOptions = true;
      };
      qt.kde.settings.konsolerc.Shortcuts.Copy = "Ctrl+Ins";
      # Desktop actions are dispatched before application mappings. Only the held
      # switcher channels and existing media keys need compositor key bindings.
      # KGlobalAccel keeps live registrations; these overrides require a new login.
      qt.kde.settings.kglobalshortcutsrc = desktop.shortcuts // {
        inherit (desktop) services;
      };
    };
}
