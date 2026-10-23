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
      replaceOnce =
        old: new: content:
        assert lib.assertMsg (
          builtins.length (lib.splitString old content) == 2
        ) "Toshy configuration anchor changed upstream: ${old}";
        lib.replaceStrings [ old ] [ new ] content;
      upstreamConfig =
        builtins.foldl' (content: replacement: replaceOnce replacement.old replacement.new content)
          (builtins.readFile "${inputs.toshy}/default-toshy-config/toshy_config.py")
          [
            {
              old = "dump_diagnostics_key(Key.F15)";
              new = "dump_diagnostics_key(None)";
            }
            {
              old = "emergency_eject_key(Key.F16)";
              new = "emergency_eject_key(None)";
            }
            {
              old = "\nmodmap(\"Cond modmap - Media Arrows Fix\",{";
              new = "\n${builtins.readFile ./pc-modmaps.py}\nmodmap(\"Cond modmap - Media Arrows Fix\",{";
            }
          ];
      configText = ''
        import xwaykeyz.config_api as _config_api
        from xwaykeyz.models.combo import Combo
        from xwaykeyz.models.modifier import Modifier


        # xwaykeyz.transform builds its window-context provider at import time,
        # which would pin it to the X11 default before this config calls
        # environ_api(). Keep the import lazy so Wayland sessions get the KWin
        # provider instead of an empty X11 window class.
        def get_pressed_mods(*args, **kwargs):
            from xwaykeyz.transform import get_pressed_mods as _get_pressed_mods
            return _get_pressed_mods(*args, **kwargs)


        # Upstream GUI Control is Meta; terminal Control is already explicit LC.
        # Generic Ctrl sources in the upstream GUI app maps mean Cmd, not Control.
        _mac_input_roles = {
            Modifier.META: Modifier.L_CONTROL,
            Modifier.L_META: Modifier.L_CONTROL,
            Modifier.R_META: Modifier.L_CONTROL,
            Modifier.CONTROL: Modifier.R_CONTROL,
        }


        def _mac_role_inputs(mappings):
            adapted = {}
            for source, commands in mappings.items():
                if isinstance(source, Combo):
                    source = Combo([_mac_input_roles.get(mod, mod) for mod in source.modifiers], source.key)
                if isinstance(commands, dict):
                    commands = _mac_role_inputs(commands)
                # Consume text macros, but preserve file-manager deletion sequences.
                for combo, selection in (
                    (C("LC-k"), "Shift-End"),
                    (C("RC-Backspace"), "Shift-Home"),
                    (C("RC-Delete"), "Shift-End"),
                ):
                    if (source == combo and isinstance(commands, list) and len(commands) == 2
                            and commands[0] == C(selection)
                            and commands[1] in (C("Backspace"), C("Delete"))):
                        commands = ignore_combo
                # Upstream helpers declare both Super and LC for the same Control role.
                adapted[source] = commands
            return adapted


        def _guard_registration(register, *, is_keymap=False):
            def guarded(name, mappings, when=None):
                if is_keymap:
                    mappings = _mac_role_inputs(mappings)
                    if name == "General GUI":
                        mappings[C("RC-Backspace")] = ignore_combo
                        mappings[C("RC-Delete")] = ignore_combo
                if when is None:
                    if mappings:
                        raise ValueError(f"Unconditional mapping is not allowed: {name}")
                    return register(name, mappings)

                def enabled(ctx):
                    if not getattr(ctx, "_dotnix_context_sampled", False):
                        _context_pre_check(ctx)
                        ctx._dotnix_context_sampled = True
                    if ctx_app_is_remote or when is _context_pre_check:
                        return False
                    if is_keymap and any(mod in (Modifier.L_META, Modifier.R_META)
                                         for mod in get_pressed_mods()):
                        return False
                    return when(ctx)

                return register(name, mappings, when=enabled)
            return guarded


        # Patch the API before the star import, including deferred Hyper expansions.
        _config_api.modmap = _guard_registration(_config_api.modmap)
        _config_api.multipurpose_modmap = _guard_registration(_config_api.multipurpose_modmap)
        _config_api.keymap = _guard_registration(_config_api.keymap, is_keymap=True)

      ''
      + builtins.foldl' (content: slice: insertSlice slice.name slice.text content) upstreamConfig [
        {
          name = "user_custom_lists";
          text = ''
            browsers_chrome.append("helium")
            browsers_chromeStr = toRgxStr(browsers_chrome)
            browsers_all.append("helium")
            browsers_allStr = toRgxStr(browsers_all)

            remotes.append("cs2")
            remotes.extend(["bg3", "steam_app_1551360", "steam_app_261550", "Slay the Spire 2"])
            remoteStr = toRgxStr(remotes)
            vscodes_and_remotes_Str = toRgxStr(vscodes + remotes)
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
      # Upstream maps Cmd+C to Ctrl+Insert; binding Konsole Copy to it consumes the
      # combo instead of letting it reach the pty.
      qt.kde.settings.konsolerc.Shortcuts.Copy = "Ctrl+Ins";
      # KGlobalAccel keeps live registrations; these overrides require a new login.
      qt.kde.settings.kglobalshortcutsrc = desktop.shortcuts // {
        inherit (desktop) services;
      };
    };
}
