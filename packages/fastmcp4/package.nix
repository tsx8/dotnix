# Vendor fastmcp 4 wheels from mcp-nixos while nixpkgs ships fastmcp 3.x, which is
# marked broken against python mcp 2. Other dependencies come from nixpkgs, whose
# versions already satisfy fastmcp 4's bounds. Remove this when nixpkgs ships fastmcp >= 4.
{
  python3Packages,
  mcpNixosSrc,
}:
let
  fastmcp-slim = python3Packages.callPackage "${mcpNixosSrc}/nix/fastmcp-slim.nix" { };
in
python3Packages.callPackage "${mcpNixosSrc}/nix/fastmcp.nix" {
  inherit fastmcp-slim;
}
