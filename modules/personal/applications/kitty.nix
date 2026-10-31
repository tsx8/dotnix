{
  dotnix.modules.nixos =
    { pkgs, ... }:
    {
      # Kitty is the desktop terminal: pi documents its keyboard protocol as needing
      # no terminal configuration. Konsole stays installed because plasma6 pulls it in.
      environment.systemPackages = [ pkgs.kitty ];
    };

  dotnix.modules.home = {
    xdg.configFile."kitty/kitty.conf".text = ''
      linux_display_server wayland
      font_size 12
      scrollback_lines 10000
      # fontconfig resolves CJK to the Korean variant of the Noto ttc; pin the
      # Simplified Chinese faces so ideographs render with Chinese glyph forms.
      symbol_map U+2E80-U+2EFF,U+3000-U+303F,U+3400-U+4DBF,U+4E00-U+9FFF,U+F900-U+FAFF,U+FF00-U+FFEF Noto Sans Mono CJK SC
      # Closing a kitty window only detaches tmux, so the running-process warning is noise.
      confirm_os_window_close 0
      # tmux owns the window layer; a second tab bar would duplicate it.
      tab_bar_style hidden
      enable_audio_bell no
    '';

    # Konsole is still present from plasma6; this makes kitty the terminal that
    # Dolphin, KRunner, and Plasma open.
    qt.kde.settings.kdeglobals.General.TerminalApplication = "kitty";
  };
}
