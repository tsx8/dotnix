{ config, ... }:
let
  userName = config.dotnix.host.userName;
in
{
  dotnix.modules.nixos = { pkgs, ... }: {
    programs.fish.enable = true;
    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    users.users.${userName}.shell = pkgs.fish;
    # Pi needs wl-copy in Wayland sessions.
    environment.systemPackages = with pkgs; [
      curl
      wget
      jq
      fd
      ripgrep
      tmux
      wl-clipboard
    ];
  };
  dotnix.modules.home = {
    programs.fish = {
      enable = true;
    };

    # A new terminal can inherit TMUX without owning a pane; compare the actual ttys.
    programs.fish.interactiveShellInit = ''
      if not set -q TMUX_AUTO_SKIP; and test "$TERM" != dumb
          set -l pane_tty
          if set -q TMUX
              set pane_tty (tmux display-message -p -t "$TMUX_PANE" '#{pane_tty}' 2>/dev/null)
          end
          if test -z "$pane_tty"; or test "$pane_tty" != (tty)
              exec bash ${./tmux-auto.sh}
          end
      end
    '';

    # C-b conflicts with editing in Emacs and Pi.
    programs.tmux = {
      enable = true;
      package = null;
      prefix = "C-]";
      # Home Manager would otherwise select screen and a 12-hour clock.
      terminal = "tmux-256color";
      clock24 = true;
      # The module would move the socket under /run/user, which drops it on logout.
      secureSocket = false;
      mouse = true;
      historyLimit = 50000;
      extraConfig = ''
        # Kitty accepts OSC 52 copies without a clipboard helper.
        set -s set-clipboard on
        # Use CSI-u so Pi can distinguish modified Enter inside tmux.
        set -g extended-keys on
        set -g extended-keys-format csi-u
        set -as terminal-features 'xterm*:RGB'
        set -g set-titles on
        set -g set-titles-string '#S:#W'
        # New panes need current desktop and agent sockets, not those from server startup.
        set -g update-environment "DISPLAY WAYLAND_DISPLAY XAUTHORITY SSH_AUTH_SOCK SSH_CONNECTION SSH_AGENT_PID XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS"
        bind N new-session
      '';
    };

    # With no user packages there are no man pages for mandb to index.
    programs.man.generateCaches = false;
  };
}
