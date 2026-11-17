{
  lib,
  python3,
  makeWrapper,
  git,
}:

python3.pkgs.buildPythonApplication {
  pname = "agy-hindsight";
  version = "1.0.0";
  format = "other";
  src = lib.cleanSource ./.;

  nativeBuildInputs = [ makeWrapper ];
  nativeCheckInputs = [ git ];
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    PYTHONDONTWRITEBYTECODE=1 ${python3.interpreter} -m unittest discover -s tests -v
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 src/agy_hindsight.py $out/bin/agy-hindsight
    wrapProgram $out/bin/agy-hindsight --prefix PATH : ${lib.makeBinPath [ git ]}
    runHook postInstall
  '';

  meta = {
    description = "Hindsight memory hooks and MCP tools for the Antigravity CLI, scoped like OMP";
    mainProgram = "agy-hindsight";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
}
