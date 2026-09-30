#!/usr/bin/env bash
set -euo pipefail

# Check that every OpenCode platform hash in sources.json matches the release.
# Only the host platform is built, so the others would otherwise go unchecked.

cd "$(dirname "${BASH_SOURCE[0]}")"

version=$(jq -r '.opencode.version' sources.json)

for platform in darwin-arm64 darwin-x64 linux-arm64 linux-x64; do
  case "$platform" in
    darwin-*) extension=zip ;;
    *) extension=tar.gz ;;
  esac

  expected=$(jq -r --arg p "$platform" '.opencode.hashes[$p]' sources.json)
  url="https://github.com/anomalyco/opencode/releases/download/v${version}/opencode-${platform}.${extension}"
  actual=$(nix store prefetch-file --json "$url" | jq -r .hash)

  if [[ "$actual" != "$expected" ]]; then
    printf 'OpenCode %s hash mismatch:\n  expected: %s\n  actual:   %s\n' "$platform" "$expected" "$actual" >&2
    exit 1
  fi
done
echo "OpenCode hashes OK ($version)"
