{
  dotnix.modules.nixos = {
    # macOS 键位：keyd 在 evdev 层重映射（X11/Wayland/TTY 均生效）
    services.keyd = {
      enable = true;

      keyboards.default = {
        ids = [ "*" ];

        settings = {
          main = {
            leftalt = "layer(meta_mac)";
            rightalt = "layer(meta_mac)";
            leftmeta = "alt";
            rightmeta = "rightalt";

            capslock = "overload(capslock, C-space)";
          };

          # 基于 keyd v2.6.0 examples/macos.conf。
          # ":C" 让未显式定义的 Cmd 组合按 Ctrl 处理。
          "meta_mac:C" = {
            # Plasma 的 KRunner 用 Alt+Space
            space = "A-space";

            # Qt/KDE 仅识别 Insert/Delete 形式的剪贴板快捷键
            c = "C-insert";
            v = "S-insert";
            x = "S-delete";

            left = "home";
            right = "end";

            # swapm：Cmd 按住期间维持 Alt，Tab 可连续切换
            tab = "swapm(app_switch_state, A-tab)";

            # KWin 用 Alt+` 切换当前应用窗口
            grave = "A-grave";
          };

          "app_switch_state:A" = {
            tab = "A-tab";
            right = "A-tab";
            grave = "A-S-tab";
            left = "A-S-tab";
          };

          # overload 的 hold 动作：长按保持 CapsLock
          capslock = {
            capslock = "capslock";
          };
        };
      };
    };

    environment.etc."xdg/kwinrc".text = ''
      [TabBox]
      ApplicationsMode=1
    '';
  };
}
