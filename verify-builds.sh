#!/usr/bin/env bash
set -euo pipefail

# Verify all agent packages build successfully
# Used in CI after version updates

echo "Verifying flake..."
nix flake check --no-build

echo "Building opencode..."
nix build .#opencode --no-link

echo "Building claude-code..."
nix build .#claude-code --no-link

# Test nixpkgs-based agents (these may fail if tag format doesn't match)
# We build a subset to verify the override mechanism works
echo "Testing nixpkgs-based agents..."
for pkg in aichat; do
  echo "Building $pkg..."
  nix build .#$pkg --no-link
done

echo "All builds successful!"