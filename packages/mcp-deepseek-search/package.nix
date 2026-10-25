{
  python3Packages,
  writers,
  # Injected from mcp-nixos's vendored fastmcp 4 stack: nixpkgs fastmcp 3.x
  # is marked broken against python mcp 2.
  fastmcp,
}:
writers.writePython3Bin "mcp-deepseek-search" {
  libraries = [
    fastmcp
    python3Packages.httpx
    python3Packages.pydantic
  ];
} (builtins.readFile ./server.py)
