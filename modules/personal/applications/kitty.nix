{
  dotnix.modules.nixos =
    { pkgs, ... }:
    {
      # Kitty reports Pi's modified keys without terminal-specific bindings.
      environment.systemPackages = [ pkgs.kitty ];
    };

  dotnix.modules.home = {
    xdg.configFile."kitty/kitty.conf".text = ''
      linux_display_server wayland
      font_size 12
      scrollback_lines 10000
      # Without an SC face, fontconfig selects Korean glyphs from the Noto collection.
      symbol_map U+2E80-U+2EFF,U+3000-U+303F,U+3400-U+4DBF,U+4E00-U+9FFF,U+F900-U+FAFF,U+FF00-U+FFEF Noto Sans Mono CJK SC
      # Closing a kitty window only detaches tmux, so the running-process warning is noise.
      confirm_os_window_close 0
      # tmux owns the window layer; a second tab bar would duplicate it.
      tab_bar_style hidden
      enable_audio_bell no
    '';

    qt.kde.settings.kdeglobals.General.TerminalApplication = "kitty";
  };
}
