{
  python3Packages,
  fastmcp,
}:

python3Packages.buildPythonApplication {
  pname = "mcp-dotnix";
  version = "0.3.0";
  pyproject = true;

  src = ./.;

  build-system = [
    python3Packages.hatchling
  ];

  dependencies = [
    fastmcp
  ];

  pythonImportsCheck = [
    "mcp_dotnix.server"
  ];

  meta = {
    description = "Read-only NixOS diagnostics for dotnix";
    mainProgram = "mcp-dotnix";
  };
}
