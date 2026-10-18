{ config, inputs, ... }: {
  dotnix.modules.nixos = { pkgs, ... }: {
    imports = [ inputs.helium-browser.nixosModules.default ];
    # Write the keymap before login to avoid Preferences write conflicts with the running browser.
    systemd.user.services.helium-keymap = {
      description = "Configure Helium native keyboard actions";
      before = [
        "graphical-session-pre.target"
        "plasma-kwin_wayland.service"
      ];
      wantedBy = [ "graphical-session-pre.target" ];
      partOf = [ "graphical-session.target" ];
      unitConfig.ConditionUser = config.dotnix.host.userName;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        state="$(${pkgs.systemd}/bin/systemctl --user show --property=ActiveState --value graphical-session.target)" || exit 1
        if [ "$state" != inactive ]; then
          echo "Helium keyboard configuration deferred until the next login"
          exit 0
        fi
        exec ${pkgs.python3}/bin/python3 ${./keymap.py} \
          "''${XDG_CONFIG_HOME:-$HOME/.config}/net.imput.helium"
      '';
    };
    programs.helium = {
      enable = true;
      flags = [
        "--ozone-platform-hint=auto"
        "--enable-wayland-ime=true"
        # The CDP debug port binds to the local loopback only, for bex to drive the browser;
        # this means any local process can run arbitrary JS through it — an accepted risk surface.
        "--remote-debugging-port=9222"
      ];
      policies.ExtensionInstallForcelist = [
        "bdiifdefkgmcblbcghdlonllpjhhjgof" # KISS Translator
        "onnepejgdiojhiflfoemillegpgpabdm" # V2EX Polish
        "dhdgffkkebhmkfjojejmpbldmpobfkfo" # Tampermonkey
      ];
    };
  };
}
