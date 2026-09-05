{ python3Packages }:

python3Packages.buildPythonApplication {
  pname = "mcp-dotnix";
  version = "0.1.0";
  format = "pyproject";

  src = ./.;

  build-system = [
    python3Packages.setuptools
  ];

  propagatedBuildInputs = [
    python3Packages.mcp
  ];

  meta = {
    description = "Read-only NixOS MCP server for dotnix";
    mainProgram = "mcp-dotnix";
  };
}
