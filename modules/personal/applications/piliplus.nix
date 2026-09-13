{
  dotnix.modules.nixos = { pkgs, ... }: {
    environment.systemPackages = [ pkgs.piliplus ];
  };
}
