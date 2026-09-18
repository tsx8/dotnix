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

    # Agent 插件/技能与源码构建应用的上游，均无 flake；版本由 flake.lock 锁定。
    kami = {
      url = "github:tw93/kami";
      flake = false;
    };

    waza = {
      url = "github:tw93/waza";
      flake = false;
    };

    obelisk-skill = {
      url = "github:tommy0103/obelisk-skill";
      flake = false;
    };

    pi-mcp-adapter = {
      url = "github:nicobailon/pi-mcp-adapter";
      flake = false;
    };

    pi-chrome-use = {
      url = "github:citrolabs/pi-chrome-use";
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
