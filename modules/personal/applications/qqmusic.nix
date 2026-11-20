{
  dotnix.modules.nixos = { pkgs, ... }: {
    environment.systemPackages = [
      (pkgs.qqmusic.overrideAttrs (_: {
        version = "1.1.7";
        src = pkgs.fetchurl {
          url = "https://dldir1.qq.com/music/clntupate/linux/qqmusic_1.1.7_amd64.deb";
          hash = "sha256-NPJHH7VwTzdNY87jFh28GaPjT7kRMweGI/XTOBAzM5E=";
        };
      }))
    ];
  };
}
