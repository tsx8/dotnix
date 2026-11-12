{
  dotnix.modules.nixos =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.neovim ];

      environment.variables = {
        EDITOR = "nvim";
        VISUAL = "nvim";
      };
    };
}
