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
      wl-clipboard
    ];
  };
  dotnix.modules.home = {
    programs.fish = {
      enable = true;
    };

    # The fish module enables man caches by default (for apropos completions), but home.packages carries no
    # man pages (repo principle); mandb produces nothing for an empty directory and the build fails, so disable it explicitly
    programs.man.generateCaches = false;
  };
}
