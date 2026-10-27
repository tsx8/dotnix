{
  writers,
  # Injected from mcp-nixos's vendored fastmcp 4 stack: nixpkgs fastmcp 3.x
  # is marked broken against python mcp 2.
  fastmcp,
}:
writers.writePython3Bin "mcp-bex" {
  libraries = [ fastmcp ];
} (builtins.readFile ./server.py)
