#!/usr/bin/env bash
set -euo pipefail

echo "Checking for new versions..."

# claude-code
echo -n "claude-code: "
LATEST_CC=$(curl -fsSL "https://downloads.claude.ai/claude-code-releases/latest")
CURRENT_CC=$(grep '"version"' pkgs/claude-code/manifest.json | head -1 | sed 's/.*"version": "\([^"]*\)".*/\1/')
echo "current=$CURRENT_CC latest=$LATEST_CC"
if [[ "$CURRENT_CC" != "$LATEST_CC" ]]; then
  echo "  -> UPDATE AVAILABLE"
fi

# opencode
echo -n "opencode: "
LATEST_OC=$(curl -fsSL "https://api.github.com/repos/opencode-ai/opencode/releases/latest" 2>/dev/null | grep '"tag_name"' | sed 's/.*"tag_name": "v*\([^"]*\)".*/\1/' || echo "unknown")
CURRENT_OC=$(grep 'opencode = "' flake.nix | head -1 | sed 's/.*opencode = "\([^"]*\)".*/\1/')
echo "current=$CURRENT_OC latest=$LATEST_OC"
if [[ "$CURRENT_OC" != "$LATEST_OC" && "$LATEST_OC" != "unknown" ]]; then
  echo "  -> UPDATE AVAILABLE"
fi

# Other agents from GitHub - name:repo
agents=(
  "codex:openai/codex"
  "qwen-code:QwenLM/qwen-code"
  "goose:pressly/goose"
  "aichat:sigoden/aichat"
  "aider-chat:Aider-AI/aider"
  "mistral-vibe:mistralai/mistral-vibe"
)

for agent_repo in "${agents[@]}"; do
  IFS=':' read -r agent repo <<< "$agent_repo"
  echo -n "$agent: "
  LATEST=$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null | grep '"tag_name"' | sed 's/.*"tag_name": "v*\([^"]*\)".*/\1/' || echo "unknown")
  CURRENT=$(grep "$agent = \"" flake.nix | sed 's/.*'"$agent"' = "\([^"]*\)".*/\1/')
  echo "current=$CURRENT latest=$LATEST"
  if [[ "$CURRENT" != "$LATEST" && "$LATEST" != "unknown" ]]; then
    echo "  -> UPDATE AVAILABLE"
  fi
done

# pi-coding-agent and codebuff - not on GitHub, skip
for agent in "pi-coding-agent" "codebuff"; do
  echo -n "$agent: "
  CURRENT=$(grep "$agent = \"" flake.nix | sed 's/.*'"$agent"' = "\([^"]*\)".*/\1/')
  echo "current=$CURRENT (no GitHub releases check)"
done

echo "Done."