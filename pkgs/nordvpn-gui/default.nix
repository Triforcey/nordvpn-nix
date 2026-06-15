{
  autoPatchelfHook,
  dpkg,
  fetchurl,
  lib,
  makeWrapper,
  stdenv,
  wrapGAppsHook3,
  # runtime / link deps for the Flutter + GTK app
  atk,
  cairo,
  gdk-pixbuf,
  glib,
  gtk3,
  harfbuzz,
  libepoxy,
  libGL,
  pango,
  xorg,
}:

# NordVPN's Flutter/GTK desktop GUI, packaged from the upstream Debian .deb.
#
# The version + hash come from ../nordvpn/source.json (shared with the CLI, since
# the GUI depends on `nordvpn (>= <same version>)`). The automated updater keeps
# both in lockstep.
#
# The GUI is just a front-end: it talks to the `nordvpnd` daemon over its socket,
# so the `nordvpn` CLI/daemon package must also be installed and running.
let
  source = lib.importJSON ../nordvpn/source.json;
  pname = "nordvpn-gui";
  inherit (source) version;
in
stdenv.mkDerivation {
  inherit pname version;

  src = fetchurl {
    inherit (source.gui) url hash;
  };

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    makeWrapper
    wrapGAppsHook3
  ];

  buildInputs = [
    atk
    cairo
    gdk-pixbuf
    glib
    gtk3
    harfbuzz
    libepoxy
    libGL
    pango
    stdenv.cc.cc.lib
    xorg.libX11
  ];

  dontConfigure = true;
  dontBuild = true;

  unpackPhase = ''
    runHook preUnpack
    dpkg --extract $src .
    runHook postUnpack
  '';

  # The Flutter bundle loads its plugin .so files from a `lib/` dir next to the
  # executable, so keep the opt/ layout intact and expose a launcher on PATH.
  installPhase = ''
    runHook preInstall

    mkdir -p $out/opt $out/bin $out/share
    cp -r opt/nordvpn-gui $out/opt/nordvpn-gui

    # autoPatchelf needs to find the bundled plugins.
    addAutoPatchelfSearchPath $out/opt/nordvpn-gui/lib

    makeWrapper $out/opt/nordvpn-gui/nordvpn-gui $out/bin/nordvpn-gui

    # Desktop entry + icon.
    if [ -d usr/share/applications ]; then
      cp -r usr/share/applications $out/share/
    fi
    if [ -d usr/share/icons ]; then
      cp -r usr/share/icons $out/share/
    fi

    runHook postInstall
  '';

  meta = with lib; {
    description = "Graphical desktop client for NordVPN (Flutter/GTK)";
    longDescription = ''
      The official NordVPN desktop GUI for Linux. It is a front-end for the
      `nordvpnd` daemon, so the `nordvpn` package (CLI + daemon) must also be
      installed and the daemon running.
    '';
    homepage = "https://www.nordvpn.com";
    license = licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "nordvpn-gui";
  };
}
