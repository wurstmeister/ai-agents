#!/usr/bin/env bash
set -euo pipefail

# Deterministic version updater for all agents
# Usage: ./update-versions.sh [--dry-run]

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
fi

FLAKE_FILE="flake.nix"

# GitHub API helper with auth if available
gh_api() {
  local url=$1
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    curl -fsSL -H "Authorization: token ${GITHUB_TOKEN}" "$url"
  else
    curl -fsSL "$url"
  fi
}

get_current_version() {
  local agent=$1
  grep "^[[:space:]]*${agent} = " "$FLAKE_FILE" | head -1 | sed 's/.*= "\([^"]*\)".*/\1/'
}

update_version() {
  local agent=$1
  local new_version=$2
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "  [dry-run] Would update $agent to $new_version"
  else
    sed -i '' "s/^[[:space:]]*${agent} = \"[^\"]*\"/  ${agent} = \"${new_version}\"/" "$FLAKE_FILE"
    echo "  Updated $agent to $new_version"
  fi
}

update_hash() {
  local new_hash=$1
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "  [dry-run] Would update opencode hash to $new_hash"
  else
    sed -i '' "s/opencode = \"sha256-[^\"]*\"/opencode = \"${new_hash}\"/" "$FLAKE_FILE"
    echo "  Updated opencode hash to $new_hash"
  fi
}

# --- claude-code ---
echo "Checking claude-code..."
LATEST_CC=$(curl -fsSL "https://downloads.claude.ai/claude-code-releases/latest")
CURRENT_CC=$(get_current_version "claude-code")
if [[ "$CURRENT_CC" != "$LATEST_CC" ]]; then
  echo "claude-code: $CURRENT_CC -> $LATEST_CC"
  if [[ "$DRY_RUN" == "false" ]]; then
    curl -fsSL "https://downloads.claude.ai/claude-code-releases/$LATEST_CC/manifest.json" -o pkgs/claude-code/manifest.json
  fi
  update_version "claude-code" "$LATEST_CC"
else
  echo "claude-code: up to date ($CURRENT_CC)"
fi

# --- opencode ---
echo "Checking opencode..."
LATEST_OC=$(gh_api "https://api.github.com/repos/anomalyco/opencode/releases/latest" | grep '"tag_name"' | sed 's/.*"tag_name": "v*\([^"]*\)".*/\1/')
CURRENT_OC=$(get_current_version "opencode")
if [[ "$CURRENT_OC" != "$LATEST_OC" ]]; then
  echo "opencode: $CURRENT_OC -> $LATEST_OC"
  update_version "opencode" "$LATEST_OC"
  # Compute new hash
  if [[ "$DRY_RUN" == "false" ]]; then
    ARCH=$(uname -m)
    if [[ "$ARCH" == "arm64" ]] || [[ "$ARCH" == "aarch64" ]]; then
      PLATFORM="darwin-arm64"
    else
      PLATFORM="darwin-x64"
    fi
    URL="https://github.com/anomalyco/opencode/releases/download/v${LATEST_OC}/opencode-${PLATFORM}.zip"
    echo "  Fetching hash for $URL..."
    RAW_HASH=$(nix-prefetch-url --unpack "$URL" 2>/dev/null)
    SRI_HASH=$(nix hash to-sri --type sha256 "$RAW_HASH" 2>/dev/null)
    update_hash "$SRI_HASH"
  fi
else
  echo "opencode: up to date ($CURRENT_OC)"
fi

# --- GitHub-based agents ---
# name:repo:tag_prefix (optional, for stripping prefix like "rust-v")
declare -A AGENT_REPOS=(
  ["codex"]="openai/codex:rust-v"
  ["qwen-code"]="QwenLM/qwen-code:"
  ["goose"]="pressly/goose:"
  ["aichat"]="sigoden/aichat:"
  ["aider-chat"]="Aider-AI/aider:"
  ["mistral-vibe"]="mistralai/mistral-vibe:"
)

for agent in "${!AGENT_REPOS[@]}"; do
  IFS=':' read -r repo tag_prefix <<< "${AGENT_REPOS[$agent]}"
  echo "Checking $agent..."
  LATEST_TAG=$(gh_api "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null | grep '"tag_name"' | sed 's/.*"tag_name": "\([^"]*\)".*/\1/' || echo "")
  if [[ -n "$LATEST_TAG" && -n "$tag_prefix" ]]; then
    LATEST="${LATEST_TAG#$tag_prefix}"
  else
    LATEST="${LATEST_TAG#v}"
  fi
  CURRENT=$(get_current_version "$agent")
  if [[ -n "$LATEST" && "$CURRENT" != "$LATEST" ]]; then
    echo "$agent: $CURRENT -> $LATEST (tag: $LATEST_TAG)"
    update_version "$agent" "$LATEST"
  elif [[ -z "$LATEST" ]]; then
    echo "$agent: could not fetch latest (rate limited?)"
  else
    echo "$agent: up to date ($CURRENT)"
  fi
done

# --- pi-coding-agent & codebuff ---
for agent in "pi-coding-agent" "codebuff"; do
  CURRENT=$(get_current_version "$agent")
  echo "$agent: $CURRENT (manual check required)"
done

if [[ "$DRY_RUN" == "true" ]]; then
  echo ""
  echo "Dry run complete. Run without --dry-run to apply changes."
else
  echo ""
  echo "All updates applied. Run 'nix flake check' to verify."
fi