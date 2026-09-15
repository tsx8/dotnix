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
        exec ${pkgs.python3}/bin/python3 ${./helium-keymap.py} \
          "''${XDG_CONFIG_HOME:-$HOME/.config}/net.imput.helium"
      '';
    };
    programs.helium = {
      enable = true;
      flags = [
        "--ozone-platform-hint=auto"
        "--enable-wayland-ime=true"
      ];
      policies.ExtensionInstallForcelist = [
        "hehggadaopoacecdllhhajmbjkdcmajg" # ChatGPT for Chrome
        "bdiifdefkgmcblbcghdlonllpjhhjgof" # KISS Translator
        "onnepejgdiojhiflfoemillegpgpabdm" # V2EX Polish
        "dhdgffkkebhmkfjojejmpbldmpobfkfo" # Tampermonkey
      ];
    };
  };
  dotnix.modules.home = { config, ... }: {
    # ChatGPT 只为已识别的浏览器生成通信配置；Helium 复用其更新后的 Chromium 配置。
    xdg.configFile."net.imput.helium/NativeMessagingHosts/com.openai.codexextension.json".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/chromium/NativeMessagingHosts/com.openai.codexextension.json";
  };
}
