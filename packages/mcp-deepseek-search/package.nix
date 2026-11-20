{
  python3Packages,
  writers,
}:
writers.writePython3Bin "mcp-deepseek-search" {
  libraries = [
    python3Packages.fastmcp
    python3Packages.httpx
    python3Packages.pydantic
  ];
} (builtins.readFile ./server.py)
