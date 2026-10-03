# Coding Agents Nix Flake

A Nix flake for popular AI coding agents, kept closer to upstream than nixpkgs.

Every agent is packaged from its official upstream release binaries; nothing
is compiled from source. Versions and platform hashes are pinned in
`sources.json` (Claude Code uses its release manifest).

## Available Agents

| Package | Agent | Built from |
|---|---|---|
| `opencode` (default) | OpenCode | release binary (`pkgs/opencode`) |
| `claude-code` | Anthropic Claude Code | release binary (`pkgs/claude-code/manifest.json`) |
| `codex` | OpenAI Codex CLI | official complete GitHub release package |
| `copilot-cli` | GitHub Copilot CLI | official `github/copilot-cli` release binary |

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
./update-versions.py codex copilot-cli  # update specific agents
./update-versions.py --update-nixpkgs   # also run `nix flake update`
```

For each agent the updater:

1. finds the latest stable release. Tags must match a strict pattern, so SDK
   and pre-release tags are ignored.
2. prefetches every supported platform's release artifact and pins its hash.
3. builds the package, and rolls that agent back if the build fails.

Rolled-back agents usually changed their release layout. The updater keeps the
prior pin until the package recipe is updated.

Don't edit versions by hand without updating the hashes. Run
`./update-versions.py <agent>` instead.

## CI

- **Update Agent Versions** (`update-versions.yml`) runs daily. It runs the
  updater with `--update-nixpkgs`, builds everything with `./verify-builds.sh`,
  and commits the result straight to `main`. If any agent had to be rolled
  back, the successful updates are still pushed and the run is marked failed.
- **Verify Builds** (`verify-builds.yml`) runs `./verify-builds.sh` on pushes
  and PRs. It builds every package, runs the flake checks, and checks all
  four OpenCode platform hashes and all supported release-agent platform hashes.
  The release-agent check also verifies that the flake and updater select the
  same official release URL and pinned hash.

## Notes

- `claude-code` and `copilot-cli` are unfree. The flake allows them via `allowUnfreePredicate`.
- Nix still downloads packaging tools and runtime dependencies (such as ripgrep).
  glibc-linked Linux binaries are patched with `autoPatchelfHook`.
- `flake.nix` and `sources.json` are authoritative. The experimental `flake.lisp`
  and `mk_agent.lisp` predate this packaging; regenerating from them would restore
  the old source-based overrides and removed agents.
- Supported systems: x86_64-linux, aarch64-linux, aarch64-darwin (nixpkgs dropped x86_64-darwin).
