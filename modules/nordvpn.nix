{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.nordvpn;
in
{
  options.services.nordvpn = {
    enable = mkEnableOption "NordVPN client and daemon";

    package = mkOption {
      type = types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.nordvpn;
      defaultText = literalExpression "nordvpn-nix.packages.\${system}.nordvpn";
      description = "The NordVPN package to use (CLI + daemon).";
    };

    users = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "alice" ];
      description = ''
        User accounts to add to the `nordvpn` group. Members of this group can
        control the daemon (run `nordvpn ...`) without root.
      '';
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Open the firewall and relax reverse-path filtering as required by the
        NordVPN daemon. Disable only if you manage these rules yourself.
      '';
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    users.groups.nordvpn = { };

    users.users = genAttrs cfg.users (_: {
      extraGroups = [ "nordvpn" ];
    });

    networking.firewall = mkIf cfg.openFirewall {
      # NordVPN needs reverse-path filtering relaxed and the OpenVPN/TLS
      # fallback ports open for non-NordLynx (WireGuard) connections.
      checkReversePath = false;
      allowedUDPPorts = [ 1194 ];
      allowedTCPPorts = [ 443 ];
    };

    systemd.services.nordvpn = {
      description = "NordVPN daemon";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        # Seed the persistent state dir from the package on first boot, then
        # launch the daemon.
        ExecStartPre = ''
          ${pkgs.bash}/bin/bash -c '\
            mkdir -m 700 -p /var/lib/nordvpn; \
            if [ -z "$(ls -A /var/lib/nordvpn)" ]; then \
              cp -r ${cfg.package}/var/lib/nordvpn/* /var/lib/nordvpn; \
            fi'
        '';
        ExecStart = "${cfg.package}/bin/nordvpnd";
        NonBlocking = true;
        KillMode = "process";
        Restart = "on-failure";
        RestartSec = 5;
        RuntimeDirectory = "nordvpn";
        RuntimeDirectoryMode = "0750";
        Group = "nordvpn";
      };
    };
  };
}
