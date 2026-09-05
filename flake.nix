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

    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    mcp-nixos = {
      url = "github:utensils/mcp-nixos";
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
      llm-agents,
      mcp-nixos,
      ...
    }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      # 上游查询 flake 输入时调用 nix flake archive，但缺少 lock 保护参数。
      mcpNixos = mcp-nixos.packages.x86_64-linux.mcp-nixos.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          substituteInPlace mcp_nixos/sources/flake_inputs.py \
            --replace-fail \
              '["flake", "archive", "--json"]' \
              '["flake", "archive", "--json", "--no-update-lock-file", "--no-write-lock-file"]'
        '';
      });
      mcpDotnix = pkgs.callPackage ./tools/mcp-dotnix/default.nix { };
    in
    {
      nixosConfigurations.maco = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";

        specialArgs = {
          inherit daeuniverse llm-agents;
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

        mcp-dotnix = mcpDotnix;

        mcp-nixos = mcpNixos;

        nixf-diagnose = nixpkgs.legacyPackages.x86_64-linux.nixf-diagnose;
      };

      devShells.x86_64-linux.default = pkgs.callPackage ./shell.nix {
        inherit mcpDotnix mcpNixos;
      };
    };
}
