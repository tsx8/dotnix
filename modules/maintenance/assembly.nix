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
    perSystem = { system, ... }: {
      # perSystem evaluation is independent of the NixOS config; it likewise allows unfree by default.
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    };

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

      # Forbid installing apps into the user environment while keeping the Home Manager generated session variables.
      home.packages = lib.mkForce [ config.home.sessionVariablesPackage ];
    };
  };
}
