{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      fastmcp = pkgs.callPackage ../../packages/fastmcp4/package.nix {
        mcpNixosSrc = inputs.mcp-nixos;
      };
    in
    {
      packages = {
        mcp-dotnix = pkgs.callPackage ../../packages/mcp-dotnix/package.nix { inherit fastmcp; };

        mcp-nixos = pkgs.callPackage ../../packages/mcp-nixos/package.nix {
          inherit fastmcp;
          mcpNixosSrc = inputs.mcp-nixos;
        };
      };
    };
}
