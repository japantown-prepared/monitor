{ lib
, buildPythonApplication
, flit-core
, requests
, diskcache
, python-dotenv
}:

let
  pyproject = builtins.fromTOML (builtins.readFile ./pyproject.toml);
in
buildPythonApplication {
  pname = pyproject.project.name;
  version = pyproject.project.version;
  src = ./.;

  pyproject = true;
  build-system = [ flit-core ];
  dependencies = [
    requests
    diskcache
    python-dotenv
  ];

  meta = {
    description = pyproject.project.description or "Japantown Monitor Service";
    mainProgram = "japantown-monitor";
  };
}
