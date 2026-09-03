{ python3Packages }:

python3Packages.buildPythonApplication rec {
  pname = "dotnix-debug-mcp";
  version = "0.1.0";
  format = "pyproject";

  src = ./.;

  build-system = [
    python3Packages.setuptools
  ];

  propagatedBuildInputs = [
    python3Packages.mcp
  ];

  checkPhase = ''
    runHook preCheck
    ${python3Packages.python.executable} -m unittest discover -s tests -v
    runHook postCheck
  '';

  pythonImportsCheck = [
    "dotnix_debug_mcp"
    "dotnix_debug_mcp.core"
    "dotnix_debug_mcp.server"
  ];

  meta = {
    description = "Read-only NixOS debug MCP server for dotnix";
    mainProgram = "dotnix-debug-mcp";
  };
}
