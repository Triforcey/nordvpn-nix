# nordvpn-nix

The official **NordVPN** CLI + daemon packaged for NixOS, with a self-maintaining
version pipeline. A scheduled GitHub Actions workflow watches NordVPN's apt
mirror, bumps the pinned release, verifies it builds, and opens a pull request —
so the package does not rot when NordVPN prunes old `.deb` files from its mirror.

- Flake package: `packages.<system>.nordvpn`
- Overlay: `overlays.default` (adds `pkgs.nordvpn`)
- NixOS module: `nixosModules.nordvpn` (`services.nordvpn.*`)
- Auto-update app: `nix run .#update`

> NordVPN's client is **unfree**. Set `nixpkgs.config.allowUnfree = true;`
> (or allowlist `nordvpn`). Only `x86_64-linux` is published upstream.

## Quick start (flake)

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nordvpn-nix.url = "github:Triforcey/nordvpn-nix";
    nordvpn-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, nordvpn-nix, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nordvpn-nix.nixosModules.nordvpn
        {
          nixpkgs.config.allowUnfree = true;
          services.nordvpn = {
            enable = true;
            users = [ "alice" ]; # added to the `nordvpn` group
          };
        }
      ];
    };
  };
}
```

Then log in once (credentials are not declarative):

```console
$ nordvpn login
$ nordvpn connect
```

## Module options

`services.nordvpn`:

| Option         | Type            | Default                         | Description                                                                 |
| -------------- | --------------- | ------------------------------- | --------------------------------------------------------------------------- |
| `enable`       | bool            | `false`                         | Install the CLI and run the `nordvpnd` daemon.                              |
| `package`      | package         | this flake's `nordvpn`          | Override the package (e.g. a pinned revision).                             |
| `users`        | list of str     | `[ ]`                           | Users added to the `nordvpn` group (control the daemon without root).      |
| `openFirewall` | bool            | `true`                          | Relax reverse-path filtering and open UDP 1194 / TCP 443 for OpenVPN fallback. |

## Overlay only (no module)

```nix
nixpkgs.overlays = [ nordvpn-nix.overlays.default ];
environment.systemPackages = [ pkgs.nordvpn ];
```

You then wire up the daemon yourself, or just use the bundled module.

## Try it without installing

```console
$ nix run github:Triforcey/nordvpn-nix#nordvpn -- --version
```

## How the auto-update works

The version pin lives in [`pkgs/nordvpn/source.json`](pkgs/nordvpn/source.json)
(version + URL + hash) — **data, not Nix code**. The build reads it via
`lib.importJSON`.

- [`scripts/update.sh`](scripts/update.sh) queries the mirror, selects the
  highest semver, prefetches the SRI hash, and rewrites `source.json`. It is a
  no-op when already current.
- [`.github/workflows/update.yml`](.github/workflows/update.yml) runs it daily
  (and on demand via *Run workflow*). On a change it builds the package and
  opens a PR titled `nordvpn: <old> -> <new>`.
- [`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs `nix flake check`
  and `nix build` on every push/PR, so the update PR is gated on a green build.

Run it locally anytime:

```console
$ nix run .#update
```

### When an upgrade needs a human

The package unpacks NordVPN's `.deb` and `autoPatchelf`s it into an FHS env. A
new release occasionally shifts native dependencies. If `nix build` fails after
a bump with a missing-library error, add the library to `buildInputs` and/or the
FHS `targetPkgs` list in [`pkgs/nordvpn/default.nix`](pkgs/nordvpn/default.nix).
The `libxml2` version is pinned there for the same reason.

## Caveats

- **NordLynx (WireGuard)** is the default protocol and needs the `wireguard`
  kernel module — standard on modern NixOS kernels.
- Credentials/login state live in `/var/lib/nordvpn` and are **not** declarative.
- This is an unofficial community package; it is not affiliated with NordVPN.

## Lineage

The package derivation was originally derived from the
[`wingej0` NUR package](https://github.com/wingej0/nur-packages) and restructured
so the version pin is externalized and machine-updatable.

## License

Packaging in this repo is MIT (see [LICENSE](LICENSE)). The NordVPN client itself
is proprietary and governed by NordVPN's own license/terms.
