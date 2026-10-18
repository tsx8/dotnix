{
  python3Packages,
  writers,
}:
writers.writePython3Bin "mcp-deepseek-search" {
  libraries = with python3Packages; [
    fastmcp
    httpx
    pydantic
  ];
} (builtins.readFile ./server.py)
