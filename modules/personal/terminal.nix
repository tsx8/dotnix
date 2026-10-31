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
    # Terminal programs such as pi rely on wl-copy for the Wayland clipboard; nothing else on this machine provides it
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

    # A new terminal opens a tmux session, not a window: tmux keeps the current
    # window per session, so one terminal per window would make terminals share
    # navigation. A window spawned from inside tmux inherits TMUX without owning a
    # pane, so the pane's tty decides whether this shell really sits in one.
    programs.fish.interactiveShellInit = ''
      if not set -q TMUX_AUTO_SKIP; and test "$TERM" != dumb
          set -l pane_tty
          if set -q TMUX
              set pane_tty (tmux display-message -p -t "$TMUX_PANE" '#{pane_tty}' 2>/dev/null)
          end
          if test -z "$pane_tty"; or test "$pane_tty" != (tty)
              exec bash ${./terminal/tmux-auto.sh}
          end
      end
    '';

    # Emacs and pi press C-b constantly, so a C-b prefix fires in the middle of editing;
    # C-] only costs Emacs's abort-recursive-edit, and pressing it twice passes the key through.
    programs.tmux = {
      enable = true;
      # tmux is a system package; the module would add a second, user-level copy.
      package = null;
      prefix = "C-]";
      # Preserve tmux's own defaults: the module would write "screen" and a 12-hour clock.
      terminal = "tmux-256color";
      clock24 = true;
      # The module would move the socket under /run/user, which drops it on logout.
      secureSocket = false;
      # tmux is the terminal layer now, so the wheel is the only way to reach
      # scrollback and clicking is how the second pane gets focus.
      mouse = true;
      # Konsole's own scrollback is no longer in play; the default is a day of work.
      historyLimit = 50000;
      extraConfig = ''
        # kitty handles OSC 52, so copies reach the clipboard without a helper command.
        set -s set-clipboard on
        # pi needs modified Enter from the outer terminal, and kitty is the only
        # installed terminal that reports it; CSI-u is the format pi documents.
        set -g extended-keys on
        set -g extended-keys-format csi-u
        # kitty reports truecolor; declare it so tmux forwards direct-color SGR.
        set -as terminal-features 'xterm*:RGB'
        # The title is the only place that shows which session a terminal holds.
        set -g set-titles on
        set -g set-titles-string '#S:#W'
        # A long-lived server keeps the environment from login, so refresh what GUI
        # and agent tools read before each new pane.
        set -g update-environment "DISPLAY WAYLAND_DISPLAY XAUTHORITY SSH_AUTH_SOCK SSH_CONNECTION SSH_AGENT_PID XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS"
        # Sessions replace windows as what a terminal opens, so a new session needs a key.
        bind N new-session
      '';
    };

    # The fish module enables man caches by default (for apropos completions), but home.packages carries no
    # man pages (repo principle); mandb produces nothing for an empty directory and the build fails, so disable it explicitly
    programs.man.generateCaches = false;
  };
}
