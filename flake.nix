{
  description = "NixOS desktop configuration";

  inputs = {
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    import-tree.url = "github:denful/import-tree";

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

    toshy = {
      url = "github:RedBearAK/Toshy";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    rime-frost = {
      url = "github:gaboolic/rime-frost";
      flake = false;
    };

    # Upstreams of agent plugins/skills and source-built apps ship no flake; the locked revision
    # stays in flake.lock and repo update advances it.
    pi-packages = {
      url = "github:gotgenes/pi-packages";
      flake = false;
    };

    cursor-plugins = {
      url = "github:cursor/plugins";
      flake = false;
    };

    obelisk-skill = {
      url = "github:tommy0103/obelisk-skill";
      flake = false;
    };

    simple-live-app = {
      url = "github:xiaoyaocz/dart_simple_live";
      flake = false;
    };
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } (
      inputs.import-tree.filter (path: !inputs.nixpkgs.lib.hasSuffix ".data.nix" path) ./modules
    );
}
