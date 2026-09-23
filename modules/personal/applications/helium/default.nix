{ config, inputs, ... }: {
  dotnix.modules.nixos = { pkgs, ... }: {
    imports = [ inputs.helium-browser.nixosModules.default ];
    # 在登录前写入快捷键，避免浏览器运行时的 Preferences 写入冲突。
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
        # CDP 调试端口仅绑本机回环，供 bex 操作浏览器；
        # 意味着本机任意进程可经它执行任意 JS，接受此风险面。
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
