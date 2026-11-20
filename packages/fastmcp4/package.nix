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
