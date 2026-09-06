{
  dotnix.modules.nixos = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      git
      gh
    ];
  };
  dotnix.modules.home = {
    programs.git = {
      enable = true;
      package = null;

      settings = {
        user = {
          name = "tsx8";
          email = "tangsongxiaoba@163.com";
        };

        credential."https://github.com".helper = "!gh auth git-credential";
      };
    };
  };
}
