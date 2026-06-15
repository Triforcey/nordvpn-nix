{
  autoPatchelfHook,
  buildFHSEnvChroot ? false,
  buildFHSUserEnv ? false,
  dpkg,
  fetchurl,
  lib,
  stdenv,
  sysctl,
  iptables,
  iproute2,
  procps,
  cacert,
  libxml2,
  libidn2,
  libnl,
  libcap,
  libcap_ng,
  zlib,
  sqlite,
  wireguard-tools,
}:

# NordVPN CLI + daemon, packaged from the upstream Debian .deb.
#
# The version pin lives in ./source.json, NOT in this file, so the automated
# updater (scripts/update.sh + the GitHub Actions cron) can bump it without
# touching Nix code. NordVPN's apt mirror prunes old .deb releases, so a stale
# pin eventually 404s on build -- the updater keeps it current.
#
# Lineage: originally derived from the wingej0 NUR package.
let
  source = lib.importJSON ./source.json;

  pname = "nordvpn";
  inherit (source) version;

  buildEnv =
    if builtins.typeOf buildFHSEnvChroot == "set" then buildFHSEnvChroot else buildFHSUserEnv;

  # NordVPN's daemon links against libxml2 2.13.x; nixpkgs has moved past it.
  libxml2_13 = libxml2.overrideAttrs rec {
    version = "2.13.8";
    src = fetchurl {
      url = "mirror://gnome/sources/libxml2/${lib.versions.majorMinor version}/libxml2-${version}.tar.xz";
      hash = "sha256-J3KUyzMRmrcbK8gfL0Rem8lDW4k60VuyzSsOhZoO6Eo=";
    };
    patches = [ ];
  };

  nordVPNBase = stdenv.mkDerivation {
    inherit pname version;

    src = fetchurl {
      inherit (source.cli) url hash;
    };

    buildInputs = [
      libxml2_13
      libidn2
      libnl
      libcap
      libcap_ng
      sqlite
    ];

    nativeBuildInputs = [
      dpkg
      autoPatchelfHook
      stdenv.cc.cc.lib
      libxml2
    ];

    dontConfigure = true;
    dontBuild = true;

    unpackPhase = ''
      runHook preUnpack
      dpkg --extract $src .
      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      mv usr/* $out/
      mv var/ $out/
      mv etc/ $out/
      runHook postInstall
    '';
  };

  nordVPNfhs = buildEnv {
    name = "nordvpnd";
    runScript = "nordvpnd";

    targetPkgs =
      pkgs: with pkgs; [
        nordVPNBase
        sysctl
        iptables
        iproute2
        procps
        cacert
        libxml2_13
        libidn2
        zlib
        wireguard-tools
        sqlite
      ];
  };

in
stdenv.mkDerivation {
  inherit pname version;

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/share
    ln -s ${nordVPNBase}/bin/nordvpn $out/bin
    ln -s ${nordVPNfhs}/bin/nordvpnd $out/bin
    ln -s ${nordVPNBase}/share* $out/share
    ln -s ${nordVPNBase}/var $out/
    runHook postInstall
  '';

  meta = with lib; {
    description = "CLI client for NordVPN";
    homepage = "https://www.nordvpn.com";
    license = licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "nordvpn";
  };
}
