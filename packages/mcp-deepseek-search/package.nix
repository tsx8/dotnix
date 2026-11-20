{
  python3Packages,
  writers,
  fastmcp,
}:
writers.writePython3Bin "mcp-deepseek-search" {
  libraries = [
    fastmcp
    python3Packages.httpx
    python3Packages.pydantic
  ];
} (builtins.readFile ./server.py)
