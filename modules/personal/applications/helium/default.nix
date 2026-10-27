{
  config,
  inputs,
  ...
}:
{
  dotnix.modules.nixos =
    { pkgs, ... }@nixos:
    {
      imports = [ inputs.helium-browser.nixosModules.default ];

      # Copy the configured browser entry and replace only Exec, so translations, MIME types and
      # actions stay upstream-owned while every launch goes through the service wrapper.
      environment.etc."xdg/applications/helium.desktop".source = pkgs.runCommand "helium.desktop" { } ''
        cp ${nixos.config.system.path}/share/applications/helium.desktop $out
        ${pkgs.gnused}/bin/sed -i -E 's|^Exec=[^ ]*/bin/helium|Exec=helium-cdp-ensure --window|' $out
        ! ${pkgs.gnugrep}/bin/grep -q '^Exec=.*/bin/helium' $out
      '';

      # The service owns the browser so CDP survives closing every window; `--no-startup-window` keeps
      # Helium alive without a window, and the desktop wrapper attaches a window later.
      environment.systemPackages = [
        (pkgs.writeShellScriptBin "helium-cdp-ensure" ''
          set -eu

          window=0
          if [ "''${1:-}" = "--window" ]; then
            window=1
            shift
          fi

          # An existing browser already serves CDP; starting the service would hand off and restart-loop.
          if ! ${pkgs.curl}/bin/curl -fsS http://127.0.0.1:9222/json/version >/dev/null 2>&1; then
            ${pkgs.systemd}/bin/systemctl --user start helium-cdp.service
          fi
          i=0
          while [ "$i" -lt 60 ]; do
            if ${pkgs.curl}/bin/curl -fsS http://127.0.0.1:9222/json/version >/dev/null 2>&1; then
              break
            fi
            i=$((i + 1))
            ${pkgs.coreutils}/bin/sleep 0.25
          done
          if [ "$i" -eq 60 ]; then
            echo "helium-cdp: CDP endpoint did not become ready" >&2
            exit 1
          fi

          if [ "$window" -eq 1 ]; then
            if [ "$#" -eq 0 ]; then
              set -- --new-window
            fi
            exec /run/current-system/sw/bin/helium "$@"
          fi
        '')
      ];

      systemd.user.services.helium-cdp = {
        description = "Persistent Helium browser for bex";
        wantedBy = [ "graphical-session.target" ];
        partOf = [ "graphical-session.target" ];
        unitConfig.ConditionUser = config.dotnix.host.userName;
        serviceConfig = {
          ExecStart = "/run/current-system/sw/bin/helium --no-startup-window";
          # A second Helium invocation hands off to an existing browser and exits 0; `always` restarts it.
          Restart = "on-failure";
          RestartSec = 2;
        };
      };

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

  # A direct launch would own the browser process and exit with its last window; route the desktop
  # entry through the ensure wrapper so the service is the owner before a window is attached.
  dotnix.modules.home =
    { config, ... }:
    {
      home.file.".local/share/applications/helium.desktop".source =
        config.lib.file.mkOutOfStoreSymlink "/etc/xdg/applications/helium.desktop";
    };
}
