{ python3Packages }:

python3Packages.buildPythonApplication {
  pname = "mcp-dotnix";
  version = "0.1.0";
  pyproject = true;

  src = ./.;

  build-system = [
    python3Packages.hatchling
  ];

  dependencies = [
    python3Packages.fastmcp
  ];

  pythonImportsCheck = [
    "mcp_dotnix.server"
  ];

  meta = {
    description = "Read-only NixOS MCP server for dotnix";
    mainProgram = "mcp-dotnix";
  };
}
