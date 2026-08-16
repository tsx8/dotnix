{
  description = "NixOS desktop configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    buaa-login = {
      url = "github:tsx8/buaa-login";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    daeuniverse = {
      url = "github:daeuniverse/flake.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    helium-browser = {
      url = "github:oxcl/nix-flake-helium-browser";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    rime-frost = {
      url = "github:gaboolic/rime-frost";
      flake = false;
    };
  };

  outputs =
    {
      nixpkgs,
      disko,
      sops-nix,
      buaa-login,
      daeuniverse,
      home-manager,
      helium-browser,
      rime-frost,
      ...
    }:
    {
      nixosConfigurations.maco = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";

        specialArgs = {
          inherit daeuniverse;
          rimeFrostSource = rime-frost;
        };

        modules = [
          ./configuration.nix
          ./disk.nix

          disko.nixosModules.disko
          sops-nix.nixosModules.sops
          buaa-login.nixosModules.default
          daeuniverse.nixosModules.dae
          home-manager.nixosModules.home-manager
          helium-browser.nixosModules.default
        ];
      };

      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt-tree;

      packages.x86_64-linux = {
        nixos-facter = nixpkgs.legacyPackages.x86_64-linux.nixos-facter;

        disko = disko.packages.x86_64-linux.default;

        age = nixpkgs.legacyPackages.x86_64-linux.age;

        sops = nixpkgs.legacyPackages.x86_64-linux.sops;

        nixos-install = nixpkgs.legacyPackages.x86_64-linux.nixos-install;
      };
    };
}
