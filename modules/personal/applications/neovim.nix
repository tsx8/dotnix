{
  dotnix.modules.nixos = { pkgs, ... }: {
    environment.variables = {
      EDITOR = "nvim";
      VISUAL = "nvim";
    };

    environment.systemPackages = [ pkgs.neovim ];
  };
}
