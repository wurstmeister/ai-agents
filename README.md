# Coding Agents Nix Flake

This is a Nix flake for popular AI coding agents with quick version overrides.

**The flake uses nixpkgs as the source but allows quick version bumps for faster updates.**

## Available Agents

- **opencode** - The open source AI coding agent (from nixpkgs)
- **claude-code** - Anthropic's official coding agent (local manifest-based fetch)
- **codex** - OpenAI's coding agent
- **qwen-code** - Qwen's coding agent
- **goose** - Block's coding agent
- **aichat** - Multi-provider AI chat CLI
- **aider-chat** - AI pair programming

## Usage

### Run an agent

```bash
# Run opencode (default)
nix run .

# Run specific agents
nix run .#claude-code
nix run .#codex
nix run .#qwen-code
nix run .#goose
nix run .#aichat
nix run .#aider-chat

# With arguments
nix run .#opencode -- --help
nix run .#codex -- --version
```

### Enter development shell

```bash
nix develop
```

This will give you a shell with all agents available in your PATH.

### Install

```bash
# Install default (opencode)
nix profile install .

# Install specific agent
nix profile install .#codex
```

### Build a package

```bash
nix build .#opencode
```

The built package will be in `./result`.

## Flake Outputs

- `packages.<system>.default`: The opencode package
- `packages.<system>.opencode`: OpenCode with binary fetch
- `packages.<system>.claude-code`: Claude Code from nixpkgs
- `packages.<system>.codex`: Codex from nixpkgs
- `packages.<system>.qwen-code`: Qwen Code from nixpkgs
- `packages.<system>.goose`: Goose from nixpkgs
- `packages.<system>.aichat`: Aichat from nixpkgs
- `packages.<system>.aider-chat`: Aider Chat from nixpkgs

## Customization

### Change Agent Versions

To update an agent to a new version, edit `flake.nix`:

```nix
versions = {
  opencode = "1.18.18";
  claude-code = "2.1.235";  # Change this to your desired version
  codex = "0.147.0";
  qwen-code = "0.16.0";
  goose = "3.27.3";
  aichat = "0.30.0";
  aider-chat = "0.86.1";
};
```

**Most agents** (codex, qwen-code, goose, aichat, aider-chat) use `fetchFromGitHub` from nixpkgs, so the version override automatically updates the source.

**For opencode**: Uses custom binary fetch from GitHub releases for fast builds. To update:
1. Update `versions.opencode` in `flake.nix`
2. Update `hashes.opencode` in `flake.nix` with the new sha256 (use a fake hash like `sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=` and rebuild; Nix will print the actual hash)

**For claude-code**: The version is pinned in `pkgs/claude-code/manifest.json`. To update it:
1. Run `./pkgs/claude-code/update.sh` to fetch the latest manifest
2. Or manually edit the version in `flake.nix` and update the manifest checksums

### Update claude-code manifest

```bash
# Fetch latest manifest from Anthropic's CDN
./pkgs/claude-code/update.sh

# Or update to a specific version
./pkgs/claude-code/update.sh 2.1.236
```

### Pin nixpkgs

You can also pin to a specific nixpkgs revision in `flake.nix`:

```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
};
```

## Notes

- **opencode**: Uses custom binary fetch from GitHub releases (fast builds, easy version overrides)
- **claude-code**: Uses local package with manifest-based binary fetch (pinned in `pkgs/claude-code/manifest.json`)
- **Other agents**: Use nixpkgs as base with version overrides for quick updates
- **claude-code is unfree** - the flake is configured with `allowUnfreePredicate` to allow it
- Supported systems: x86_64-linux, x86_64-darwin, aarch64-darwin, aarch64-linux

## First Build

The first build downloads the binaries from GitHub or builds from source. The build may take a moment as it fetches dependencies.
