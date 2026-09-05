#!/usr/bin/env bash
set -euo pipefail

version=$(grep '^[[:space:]]*opencode = ' flake.nix | head -1 | sed 's/.*= "\([^"]*\)".*/\1/')

for platform in darwin-arm64 darwin-x64 linux-arm64 linux-x64; do
  case "$platform" in
    darwin-*) extension=zip ;;
    *) extension=tar.gz ;;
  esac

  expected=$(grep "\"${platform}\" = " flake.nix | sed 's/.*= "\([^"]*\)".*/\1/')
  url="https://github.com/anomalyco/opencode/releases/download/v${version}/opencode-${platform}.${extension}"
  raw_hash=$(nix-prefetch-url "$url" 2>/dev/null)
  actual=$(nix hash convert --hash-algo sha256 --to sri "$raw_hash")

  if [[ "$actual" != "$expected" ]]; then
    printf 'OpenCode %s hash mismatch:\n  expected: %s\n  actual:   %s\n' "$platform" "$expected" "$actual" >&2
    exit 1
  fi
done
