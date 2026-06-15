{
  description = "NordVPN CLI + daemon for NixOS, with an automated version-bump pipeline";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      # NordVPN's client is unfree; allow just this package so the flake's own
      # outputs (package, checks, CI) build without callers tweaking config.
      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfreePredicate = pkg: nixpkgs.lib.getName pkg == "nordvpn";
        };
    in
    {
      # nix build .#nordvpn  /  nix run .#nordvpn
      packages = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        rec {
          nordvpn = pkgs.callPackage ./pkgs/nordvpn { };
          default = nordvpn;
        }
      );

      # Importable into any nixpkgs instance:
      #   nixpkgs.overlays = [ nordvpn-nix.overlays.default ];
      overlays.default = final: _prev: {
        nordvpn = final.callPackage ./pkgs/nordvpn { };
      };

      # Importable NixOS module:
      #   imports = [ nordvpn-nix.nixosModules.nordvpn ];
      #   services.nordvpn.enable = true;
      nixosModules = {
        nordvpn = import ./modules/nordvpn.nix { inherit self; };
        default = self.nixosModules.nordvpn;
      };

      # `nix flake check` builds the package and evaluates a sample host.
      checks = forAllSystems (system: {
        nordvpn = self.packages.${system}.nordvpn;
      });

      # `nix run .#update` -> bump pkgs/nordvpn/source.json to newest release.
      apps = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          update = pkgs.writeShellApplication {
            name = "update-nordvpn";
            runtimeInputs = with pkgs; [
              curl
              jq
              gnused
              gnugrep
              coreutils
              nix
            ];
            text = builtins.readFile ./scripts/update.sh;
          };
        in
        {
          update = {
            type = "app";
            program = "${update}/bin/update-nordvpn";
          };
          default = self.apps.${system}.update;
        }
      );

      formatter = forAllSystems (system: (pkgsFor system).nixfmt-rfc-style);
    };
}
