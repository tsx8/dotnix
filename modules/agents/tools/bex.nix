{ config, inputs, ... }:
{
  perSystem = { pkgs, ... }: {
    packages.bex = pkgs.callPackage ../../../packages/bex/package.nix {
      piChromeUseSrc = inputs.pi-chrome-use;
    };
  };

  dotnix.modules.nixos = { pkgs, ... }: {
    environment.systemPackages = [
      # bex 端点固化：覆盖式导出，会话内改写环境无法把 bex 指向其他浏览器；
      # helium-use skill 声明该端点为唯一授权浏览器。
      (pkgs.writeShellScriptBin "bex" ''
        export BU_CDP_URL=http://127.0.0.1:9222
        export BU_CDP_LAUNCH=helium
        exec ${config.flake.packages.${pkgs.stdenv.hostPlatform.system}.bex}/bin/bex "$@"
      '')
    ];
  };
}
