{
  dotnix.modules.nixos = { pkgs, ... }: {
    environment.systemPackages = [
      # Tencent moved the 1.1.8 Linux deb to COS archive storage, so fresh builds fail with 403; stay on the last live 1.1.7 direct link.
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
