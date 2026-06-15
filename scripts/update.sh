#!/usr/bin/env bash
# Bump pkgs/nordvpn/source.json to the newest NordVPN release available on the
# upstream apt mirror. Safe to run repeatedly; it is a no-op when already current.
#
# Usage:
#   scripts/update.sh                 # update in place
#   ./result/bin/update-nordvpn       # via `nix run .#update`
#
# Emits machine-readable lines to $GITHUB_OUTPUT when running in GitHub Actions:
#   updated=true|false
#   old_version=<x>
#   new_version=<y>
set -euo pipefail

POOL="https://repo.nordvpn.com/deb/nordvpn/debian/pool/main/n"
CLI_MIRROR="${POOL}/nordvpn"
GUI_MIRROR="${POOL}/nordvpn-gui"

# Locate the repo root. When run via `nix run .#update` the script lives in the
# read-only Nix store, so we cannot use its own location -- walk up from $PWD
# looking for the flake. Fall back to script-relative for direct execution.
find_root() {
  local dir
  dir="$(pwd)"
  while [ "${dir}" != "/" ]; do
    if [ -f "${dir}/pkgs/nordvpn/source.json" ]; then
      echo "${dir}"
      return 0
    fi
    dir="$(dirname "${dir}")"
  done
  # Fallback: relative to this script (direct ./scripts/update.sh execution).
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
  if [ -f "${script_dir}/../pkgs/nordvpn/source.json" ]; then
    (cd "${script_dir}/.." && pwd)
    return 0
  fi
  return 1
}

if ! ROOT="$(find_root)"; then
  echo "ERROR: could not locate pkgs/nordvpn/source.json. Run from the repo root." >&2
  exit 1
fi
SOURCE_JSON="${ROOT}/pkgs/nordvpn/source.json"

emit() {
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "$1=$2" >>"${GITHUB_OUTPUT}"
  fi
}

current_version="$(jq -r .version "${SOURCE_JSON}")"
echo "Current pinned version: ${current_version}"

echo "Querying mirror for available releases..."
latest_version="$(
  curl -fsSL "${CLI_MIRROR}/" \
    | grep -oE 'nordvpn_[0-9]+\.[0-9]+\.[0-9]+_amd64\.deb' \
    | sed -E 's/nordvpn_([0-9.]+)_amd64\.deb/\1/' \
    | sort -V -u \
    | tail -n1
)"

if [ -z "${latest_version}" ]; then
  echo "ERROR: could not determine the latest version from the mirror." >&2
  exit 1
fi
echo "Latest available version: ${latest_version}"

emit old_version "${current_version}"
emit new_version "${latest_version}"

# Compare with version sort; only move forward.
newest="$(printf '%s\n%s\n' "${current_version}" "${latest_version}" | sort -V | tail -n1)"
if [ "${latest_version}" = "${current_version}" ] || [ "${newest}" != "${latest_version}" ]; then
  echo "Already up to date (pinned ${current_version}, latest ${latest_version}). Nothing to do."
  emit updated false
  exit 0
fi

# The GUI package shares the CLI's version (it Depends on nordvpn (>= ver)).
cli_url="${CLI_MIRROR}/nordvpn_${latest_version}_amd64.deb"
gui_url="${GUI_MIRROR}/nordvpn-gui_${latest_version}_amd64.deb"

prefetch() {
  local url="$1" h
  echo "Prefetching ${url} ..." >&2
  h="$(nix store prefetch-file --json "${url}" | jq -r .hash)"
  if [ -z "${h}" ] || [ "${h}" = "null" ]; then
    echo "ERROR: failed to prefetch hash for ${url}." >&2
    exit 1
  fi
  echo "${h}"
}

cli_hash="$(prefetch "${cli_url}")"
echo "New CLI hash: ${cli_hash}"
gui_hash="$(prefetch "${gui_url}")"
echo "New GUI hash: ${gui_hash}"

tmp="$(mktemp)"
jq -n \
  --arg version "${latest_version}" \
  --arg cli_url "${cli_url}" \
  --arg cli_hash "${cli_hash}" \
  --arg gui_url "${gui_url}" \
  --arg gui_hash "${gui_hash}" \
  '{
    version: $version,
    cli: { url: $cli_url, hash: $cli_hash },
    gui: { url: $gui_url, hash: $gui_hash }
  }' >"${tmp}"
mv "${tmp}" "${SOURCE_JSON}"

echo "Updated ${SOURCE_JSON}: ${current_version} -> ${latest_version}"
emit updated true
