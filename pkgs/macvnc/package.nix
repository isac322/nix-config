{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  pkg-config,
  libvncserver,
}:

stdenv.mkDerivation {
  pname = "macvnc";
  version = "0-unstable-2024-12-22";

  src = fetchFromGitHub {
    owner = "LibVNC";
    repo = "macVNC";
    rev = "6c45640168dd170120d96661b3b711d283257166";
    hash = "sha256-5cPRDVzPWE8dcTf6hIk0mV+6Np2Z0sjW9YOOrQ1Idzg=";
  };

  patches = [
    ./accessibility-prompt.patch
    ./dynamic-capture-filter.patch
  ];

  nativeBuildInputs = [
    cmake
    pkg-config
  ];
  buildInputs = [ libvncserver ];

  cmakeFlags = [ "-DCMAKE_BUILD_TYPE=Release" ];

  installPhase = ''
    runHook preInstall

    app="$out/Applications/macVNC.app"
    mkdir -p "$out/Applications" "$out/bin" "$out/share/licenses/macvnc"
    cp -R macVNC.app "$app"
    install -m 0644 "$src/COPYING" "$out/share/licenses/macvnc/COPYING"
    ln -s ../Applications/macVNC.app/Contents/MacOS/macVNC \
      "$out/bin/macvnc"

    runHook postInstall
  '';

  # Sign only after the standard fixup/strip phases have finished. A stable
  # bundle identity lets macOS retain Screen Recording and Accessibility
  # consent across immutable Nix store generations.
  postFixup = ''
    info="$out/Applications/macVNC.app/Contents/Info.plist"
    /usr/bin/plutil -replace CFBundleIdentifier \
      -string com.github.LibVNC.macVNC "$info"
    /usr/bin/plutil -replace CFBundleName -string macVNC "$info"
    /usr/bin/plutil -insert CFBundleDisplayName -string macVNC "$info"
    /usr/bin/plutil -replace CFBundleVersion -string 1 "$info"
    /usr/bin/codesign --force --sign - \
      --identifier com.github.LibVNC.macVNC \
      "$out/Applications/macVNC.app"
  '';

  meta = {
    description = "Native LibVNCServer-based VNC server for macOS";
    homepage = "https://github.com/LibVNC/macVNC";
    license = lib.licenses.gpl2Plus;
    mainProgram = "macvnc";
    platforms = [ "aarch64-darwin" ];
    maintainers = [ ];
  };
}
