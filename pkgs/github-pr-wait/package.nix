{ lib, python3, makeWrapper, gh }:

python3.pkgs.buildPythonApplication {
  pname = "github-pr-wait";
  version = "0.1.0";
  format = "other";
  src = lib.cleanSource ./.;

  nativeBuildInputs = [ makeWrapper ];
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    PYTHONDONTWRITEBYTECODE=1 ${python3.interpreter} -m unittest discover -s tests -v
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 src/github_pr_wait.py $out/bin/github-pr-wait
    wrapProgram $out/bin/github-pr-wait --prefix PATH : ${lib.makeBinPath [ gh ]}
    runHook postInstall
  '';

  meta = {
    description = "Read-only, bounded GitHub pull request condition waiter";
    mainProgram = "github-pr-wait";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
}
