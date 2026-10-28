{ lib, python3 }:

python3.pkgs.buildPythonApplication {
  pname = "jevify-writing";
  version = "0.1.0";
  format = "other";
  src = ./src;

  installPhase = ''
    install -Dm755 jevify-writing.py $out/bin/jevify-writing
  '';

  meta = {
    description = "Deterministic destination-aware writing artifact validator";
    mainProgram = "jevify-writing";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
