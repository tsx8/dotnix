{ config, inputs, ... }:
{
  perSystem = { pkgs, ... }: {
    packages.wechat = pkgs.callPackage ../../../packages/wechat/package.nix {
      # Reuse nixpkgs' AppImage packaging and metadata; only pin the drifting version/src.
      linuxNix = "${inputs.nixpkgs}/pkgs/by-name/we/wechat/linux.nix";
      inherit (pkgs.wechat) pname meta;
    };
  };

  dotnix.modules.nixos = { pkgs, ... }: {
    environment.systemPackages = [
      config.flake.packages.${pkgs.stdenv.hostPlatform.system}.wechat
    ];
  };
}
