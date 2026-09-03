{ python3Packages }:

python3Packages.buildPythonApplication {
  pname = "dotnix-mcp";
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
    "dotnix_mcp"
    "dotnix_mcp.core"
    "dotnix_mcp.server"
  ];

  meta = {
    description = "Read-only NixOS MCP server for dotnix";
    mainProgram = "dotnix-mcp";
  };
}
