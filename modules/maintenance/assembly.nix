{
  config,
  inputs,
  lib,
  ...
}:

let
  host = config.dotnix.host;
in
{
  options.dotnix = {
    host = lib.mkOption {
      type = lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.singleLineStr;
            description = "NixOS configuration name and host name.";
          };
          system = lib.mkOption {
            type = lib.types.singleLineStr;
            description = "Platform for the host and project packages.";
          };
          userName = lib.mkOption {
            type = lib.types.singleLineStr;
            description = "Account bound to the personal environment.";
          };
        };
      };
    };
    modules = {
      nixos = lib.mkOption {
        type = lib.types.deferredModule;
        description = "NixOS configuration contributed by the features.";
      };
      home = lib.mkOption {
        type = lib.types.deferredModule;
        description = "Home Manager configuration contributed by the features.";
      };
    };
  };

  config = {
    dotnix.host = {
      name = "maco";
      system = "x86_64-linux";
      userName = "tsxb";
    };

    systems = [ host.system ];

    flake.nixosConfigurations.${host.name} = inputs.nixpkgs.lib.nixosSystem {
      inherit (host) system;
      modules = [ config.dotnix.modules.nixos ];
    };

    dotnix.modules.nixos = {
      imports = [ inputs.home-manager.nixosModules.home-manager ];

      networking.hostName = host.name;

      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = false;
        users.${host.userName} = config.dotnix.modules.home;
      };
    };

    dotnix.modules.home = { config, lib, ... }: {
      home.stateVersion = "26.05";

      # 仓库原则：应用不进用户环境
      home.packages = lib.mkForce [ config.home.sessionVariablesPackage ];
    };
  };
}
