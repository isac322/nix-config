{ lib, python3, makeWrapper, gh, git, gnutar, coreutils }:

python3.pkgs.buildPythonApplication {
  pname = "pr-gate";
  version = "0.1.0";
  format = "other";
  src = lib.cleanSource ./.;

  # The end-to-end tests drive a real temporary Git repository and `git archive | tar`.
  nativeBuildInputs = [ makeWrapper git gnutar ];
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    PYTHONDONTWRITEBYTECODE=1 ${python3.interpreter} -m unittest discover -s tests -v
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 src/pr_gate.py $out/bin/pr-gate
    install -Dm644 src/gate-prompt.md $out/share/pr-gate/gate-prompt.md
    install -Dm644 src/gate-schema.json $out/share/pr-gate/gate-schema.json
    wrapProgram $out/bin/pr-gate \
      --set PR_GATE_DATA_DIR $out/share/pr-gate \
      --prefix PATH : ${lib.makeBinPath [ gh git gnutar coreutils ]}
    runHook postInstall
  '';

  meta = {
    description = "Read-only, observe-only local pull request review gate";
    mainProgram = "pr-gate";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
}
