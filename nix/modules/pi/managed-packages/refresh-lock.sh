#!/usr/bin/env bash
# Regenerate nix/modules/pi/managed-packages/package-lock.json.
#
# The committed lock is generated with --install-strategy=nested: pi's
# extension loader resolves imports against the literal path, so every
# managed package must be self-contained (dependencies nested under its own
# directory, like npm's global-install layout). Peer entries stay in the
# lock so offline `npm ci` has complete resolution.
#
# Usage: nix/modules/pi/managed-packages/refresh-lock.sh
set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$dir"
npm install --package-lock-only --install-strategy=nested --ignore-scripts --no-audit --no-fund

echo "Lock refreshed. Update npmDeps hash in nix/modules/pi/config.nix with:"
echo "  nix build nixpkgs#prefetch-npm-deps && ./result/bin/prefetch-npm-deps $dir/package-lock.json"
