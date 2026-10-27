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
      # Konsole handles OSC 52, so copies reach the clipboard without a helper command.
      extraConfig = "set -s set-clipboard on";
    };

    # The fish module enables man caches by default (for apropos completions), but home.packages carries no
    # man pages (repo principle); mandb produces nothing for an empty directory and the build fails, so disable it explicitly
    programs.man.generateCaches = false;
  };
}
