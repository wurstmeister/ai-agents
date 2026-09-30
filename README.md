# Coding Agents Nix Flake

A Nix flake for popular AI coding agents, kept closer to upstream than nixpkgs.

Versions and platform hashes are pinned in `sources.json` (Claude Code uses its
release manifest). Codex uses its complete GitHub release package, and Goose
uses its upstream release binary (including static musl binaries on Linux). For agents packaged from source, if nixpkgs
already ships the pinned version, the nixpkgs package is used unchanged (so it comes from the binary
cache). If the pin is newer, the package is rebuilt from the new source with
correct source and dependency hashes.

## Available Agents

| Package | Agent | Built from |
|---|---|---|
| `opencode` (default) | OpenCode | release binary (`pkgs/opencode`) |
| `claude-code` | Anthropic Claude Code | release binary (`pkgs/claude-code/manifest.json`) |
| `codex` | OpenAI Codex CLI | official complete GitHub release package |
| `qwen-code` | Qwen Code | nixpkgs `qwen-code` |
| `goose` | Goose (AAIF/Block) | official `aaif-goose/goose` release binary |
| `aichat` | Multi-provider AI chat CLI | nixpkgs `aichat` |
| `aider-chat` | Aider | nixpkgs `aider-chat` |
| `mistral-vibe` | Mistral Vibe | nixpkgs `mistral-vibe` |
| `pi-coding-agent` | Pi | nixpkgs `pi-coding-agent` |
| `codebuff` | Codebuff | nixpkgs `codebuff` (lock file in `pkgs/codebuff`) |

## Usage

```bash
nix run .                  # opencode
nix run .#claude-code
nix run .#codex -- --version
nix develop                # shell with every agent
nix profile install .#codex
```

## Updating

```bash
./update-versions.py --dry-run          # show available updates
./update-versions.py                    # update everything
./update-versions.py codex goose        # update specific agents
./update-versions.py --update-nixpkgs   # also run `nix flake update`
```

For each agent the updater:

1. finds the latest stable release. Tags must match a strict pattern, so SDK
   and pre-release tags are ignored.
2. fetches platform artifacts and pins their hashes for binary agents.
   For source packages, it computes every fixed-output hash (source, `cargoHash`, `npmDepsHash`, pi's
   model data) by building with a fake hash, or copies nixpkgs' values if
   nixpkgs already has that version. For codebuff it also regenerates
   `pkgs/codebuff/package-lock.json`.
3. builds the package, and rolls that agent back if the build fails.

Rolled-back agents usually changed their build upstream (e.g. switched build
system or added a workspace package), so nixpkgs' recipe no longer fits. They
pick up again once nixpkgs repackages them and `--update-nixpkgs` pulls it in.

Don't edit versions by hand without updating the hashes. Run
`./update-versions.py <agent>` instead.

## CI

- **Update Agent Versions** (`update-versions.yml`) runs daily. It runs the
  updater with `--update-nixpkgs`, builds everything with `./verify-builds.sh`,
  and commits the result straight to `main`. If any agent had to be rolled
  back, the successful updates are still pushed and the run is marked failed.
- **Verify Builds** (`verify-builds.yml`) runs `./verify-builds.sh` on pushes
  and PRs. It builds every package, runs the flake checks, and checks all
  four OpenCode platform hashes and all supported Codex/Goose platform hashes.
  The Codex/Goose check also verifies that the flake and updater select the same
  official release URL and pinned hash.

## Notes

- `claude-code` is unfree. The flake allows it via `allowUnfreePredicate`.
- Codex and Goose do not compile Rust or fetch Cargo dependencies. Nix still
  downloads packaging tools and runtime dependencies (such as ripgrep).
- `flake.nix` and `sources.json` are authoritative. The experimental `flake.lisp`
  and `mk_agent.lisp` predate this packaging; regenerating from them would restore
  the old source-based overrides.
- Supported systems: x86_64-linux, aarch64-linux, aarch64-darwin (nixpkgs dropped x86_64-darwin).
