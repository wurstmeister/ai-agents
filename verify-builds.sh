#!/usr/bin/env bash
set -euo pipefail

# Build every package and run the flake checks. Used by CI.

cd "$(dirname "${BASH_SOURCE[0]}")"

./verify-opencode-hashes.sh
python3 ./verify-release-hashes.py

echo "Checking flake..."
nix flake check --no-build

system=$(nix eval --impure --raw --expr builtins.currentSystem)
package_names=$(nix eval --json ".#packages.$system" --apply builtins.attrNames | jq -r '.[]')
packages=()
while IFS= read -r package; do
  packages+=("$package")
done <<< "$package_names"
echo "Building: ${packages[*]}"
nix build --no-link -L "${packages[@]/#/.#}"

echo "Running checks..."
nix flake check -L

echo "All builds successful!"
