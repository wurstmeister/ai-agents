#!/usr/bin/env python3
"""Update agent versions and hashes in sources.json.

For every agent this:
  1. finds the latest stable upstream release (tags are matched against a
     strict pattern, so SDK or pre-release tags are ignored),
  2. computes every fixed-output hash by building with a fake hash and reading
     the hash Nix reports (or copies nixpkgs' values if nixpkgs already ships
     that version),
  3. builds the package, and rolls the agent back if the build fails.

Usage:
  ./update-versions.py [--dry-run] [--update-nixpkgs] [--summary FILE] [AGENT ...]

Exit status is 0 if every attempted update succeeded, 1 if any failed (the
successful ones are still written).
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SOURCES = ROOT / "sources.json"
CODEBUFF_LOCK = ROOT / "pkgs/codebuff/package-lock.json"
CLAUDE_MANIFEST = ROOT / "pkgs/claude-code/manifest.json"
FAKE_HASH = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
SEMVER = r"(\d+\.\d+\.\d+)"
TRIPLES = {
    "aarch64-darwin": "aarch64-apple-darwin",
    "aarch64-linux": "aarch64-unknown-linux-musl",
    "x86_64-linux": "x86_64-unknown-linux-musl",
}

# Agents packaged from upstream release binaries: platform key -> asset URL.
RELEASES = {
    "opencode": {
        "repo": "anomalyco/opencode",
        "tag": rf"v{SEMVER}",
        "assets": {
            p: f"https://github.com/anomalyco/opencode/releases/download/{{tag}}/opencode-{p}.{ext}"
            for p, ext in [
                ("darwin-arm64", "zip"),
                ("darwin-x64", "zip"),
                ("linux-arm64", "tar.gz"),
                ("linux-x64", "tar.gz"),
            ]
        },
    },
    "codex": {
        "repo": "openai/codex",
        "tag": rf"rust-v{SEMVER}",
        "assets": {
            system: f"https://github.com/openai/codex/releases/download/{{tag}}/codex-package-{triple}.tar.gz"
            for system, triple in TRIPLES.items()
        },
    },
    "goose": {
        "repo": "aaif-goose/goose",
        "tag": rf"v{SEMVER}",
        "assets": {
            system: f"https://github.com/aaif-goose/goose/releases/download/{{tag}}/goose-{t}.tar.gz"
            for system, t in TRIPLES.items()
        },
    },
}

# name -> upstream + which fixed-output attributes hold which hash field.
# Order matters: the source hash must be known before dependency hashes.
AGENTS = {
    "aichat": {
        "nixpkgs": "aichat",
        "repo": "sigoden/aichat",
        "tag": rf"v{SEMVER}",
        "hashes": [("hash", "src"), ("cargoHash", "cargoDeps")],
    },
    "qwen-code": {
        "nixpkgs": "qwen-code",
        "repo": "QwenLM/qwen-code",
        "tag": rf"v{SEMVER}",
        "hashes": [("hash", "src"), ("npmDepsHash", "npmDeps")],
    },
    "pi-coding-agent": {
        "nixpkgs": "pi-coding-agent",
        "repo": "earendil-works/pi",
        "tag": rf"v{SEMVER}",
        "hashes": [
            ("hash", "src"),
            ("modelDataHash", "modelData"),
            ("npmDepsHash", "npmDeps"),
        ],
    },
    "aider-chat": {
        "nixpkgs": "aider-chat",
        "repo": "Aider-AI/aider",
        "tag": rf"v{SEMVER}",
        "hashes": [("hash", "src")],
    },
    "mistral-vibe": {
        "nixpkgs": "mistral-vibe",
        "repo": "mistralai/mistral-vibe",
        "tag": rf"v{SEMVER}",
        "hashes": [("hash", "src")],
    },
    "codebuff": {
        "nixpkgs": "codebuff",
        "npm": "codebuff",
        "hashes": [("hash", "src"), ("npmDepsHash", "npmDeps")],
    },
}
ALL = [*RELEASES, "claude-code", *AGENTS]


class UpdateError(Exception):
    pass


def log(msg):
    print(msg, flush=True)


def run(*cmd, check=True, cwd=ROOT):
    proc = subprocess.run(cmd, cwd=cwd, text=True, capture_output=True)
    if check and proc.returncode != 0:
        raise UpdateError(f"{' '.join(cmd)} failed:\n{proc.stderr[-4000:]}")
    return proc


def http_get(url):
    headers = {"User-Agent": "ai-agents-updater"}
    token = os.environ.get("GITHUB_TOKEN")
    if token and url.startswith("https://api.github.com/"):
        headers["Authorization"] = f"Bearer {token}"
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers)) as r:
        return r.read()


def version_key(v):
    return tuple(int(x) for x in v.split("."))


def latest_github(repo, tag_pattern):
    pattern = re.compile(rf"^{tag_pattern}$")
    best = None
    for page in range(1, 4):
        releases = json.loads(
            http_get(f"https://api.github.com/repos/{repo}/releases?per_page=100&page={page}")
        )
        for rel in releases:
            if rel["draft"] or rel["prerelease"]:
                continue
            m = pattern.match(rel["tag_name"])
            if m and (best is None or version_key(m.group(1)) > version_key(best[0])):
                best = (m.group(1), rel["tag_name"])
        if len(releases) < 100:
            break
    if best is None:
        raise UpdateError(f"no stable release of {repo} matches {tag_pattern}")
    return best


def load_sources():
    return json.loads(SOURCES.read_text())


def save_sources(sources):
    SOURCES.write_text(json.dumps(sources, indent=2, sort_keys=True) + "\n")


def current_system():
    return run("nix", "eval", "--impure", "--raw", "--expr", "builtins.currentSystem").stdout


def build(system, attr):
    return run("nix", "build", "--no-link", "-L", f".#packages.{system}.{attr}", check=False)


def got_hash(system, attr):
    """Build a fixed-output attr that carries FAKE_HASH and return the real hash."""
    proc = build(system, attr)
    m = re.search(r"got:\s+(sha256-[A-Za-z0-9+/=]+)", proc.stderr)
    if not m:
        raise UpdateError(
            f"expected a hash mismatch building {attr}, got:\n{proc.stderr[-4000:]}"
        )
    return m.group(1)


def nixpkgs_eval(expr):
    """Evaluate `expr` with `p` bound to this flake's pinned nixpkgs."""
    full = (
        f'let p = (builtins.getFlake "{ROOT}").inputs.nixpkgs'
        f".legacyPackages.${{builtins.currentSystem}}; in {expr}"
    )
    return json.loads(run("nix", "eval", "--impure", "--json", "--expr", full).stdout)


def nixpkgs_entry(name, spec):
    """sources.json entry equal to what nixpkgs ships (used when it is current)."""
    a = f'p."{spec["nixpkgs"]}"'
    fields = {
        "hash": f"{a}.src.outputHash",
        "cargoHash": f"{a}.cargoHash",
        "npmDepsHash": f"{a}.npmDeps.outputHash",
        "modelDataHash": f"{a}.modelData.outputHash",
    }
    attrs = [f"version = {a}.version;"]
    if "repo" in spec:
        attrs.append(f"tag = {a}.src.tag;")
    attrs += [f"{field} = {fields[field]};" for field, _ in spec["hashes"]]
    return nixpkgs_eval("{ " + " ".join(attrs) + " }")


def regenerate_codebuff_lock(version):
    with tempfile.TemporaryDirectory() as tmp:
        run(
            "nix", "shell", "nixpkgs#nodejs", "-c",
            "npm", "install", "--package-lock-only", "--ignore-scripts",
            f"codebuff@{version}",
            cwd=tmp,
        )
        lock = json.loads((Path(tmp) / "package-lock.json").read_text())
        lock["name"] = "codebuff"
        CODEBUFF_LOCK.write_text(json.dumps(lock, indent=2) + "\n")


def update_agent(name, system, dry_run):
    spec = AGENTS[name]
    sources = load_sources()
    old = sources[name]
    if "npm" in spec:
        version = json.loads(http_get(f"https://registry.npmjs.org/{spec['npm']}/latest"))["version"]
        tag = None
    else:
        version, tag = latest_github(spec["repo"], spec["tag"])
    if version_key(version) <= version_key(old["version"]):
        return None
    change = f"{name}: {old['version']} -> {version}"
    if dry_run:
        return change

    nixpkgs_version = nixpkgs_eval(f'p."{spec["nixpkgs"]}".version')
    if nixpkgs_version == version:
        sources[name] = nixpkgs_entry(name, spec)
        save_sources(sources)
    else:
        entry = {"version": version, **({"tag": tag} if tag else {})}
        entry.update({field: FAKE_HASH for field, _ in spec["hashes"]})
        sources[name] = entry
        save_sources(sources)
        if name == "codebuff":
            regenerate_codebuff_lock(version)
        for field, attr in spec["hashes"]:
            entry[field] = got_hash(system, f"{name}.{attr}")
            save_sources(sources)
    return change


def update_release(name, dry_run):
    spec = RELEASES[name]
    sources = load_sources()
    old = sources[name]["version"]
    version, tag = latest_github(spec["repo"], spec["tag"])
    if version_key(version) <= version_key(old):
        return None
    change = f"{name}: {old} -> {version}"
    if dry_run:
        return change
    hashes = {}
    for platform, url in spec["assets"].items():
        hashes[platform] = json.loads(
            run(
                "nix",
                "store",
                "prefetch-file",
                "--json",
                "--hash-type",
                spec.get("hash_type", "sha256"),
                url.format(tag=tag, version=version),
            ).stdout
        )["hash"]
    sources[name] = {"version": version, "hashes": hashes}
    save_sources(sources)
    return change


def update_claude_code(system, dry_run):
    base = "https://downloads.claude.ai/claude-code-releases"
    old = json.loads(CLAUDE_MANIFEST.read_text())["version"]
    version = http_get(f"{base}/latest").decode().strip()
    if version_key(version) <= version_key(old):
        return None
    change = f"claude-code: {old} -> {version}"
    if not dry_run:
        CLAUDE_MANIFEST.write_bytes(http_get(f"{base}/{version}/manifest.json"))
    return change


def snapshot():
    return {p: p.read_bytes() for p in (SOURCES, CODEBUFF_LOCK, CLAUDE_MANIFEST, ROOT / "flake.lock")}


def restore(snap):
    for path, data in snap.items():
        path.write_bytes(data)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("agents", nargs="*", metavar="AGENT", help=f"one of: {', '.join(ALL)}")
    ap.add_argument("--dry-run", action="store_true", help="only report available updates")
    ap.add_argument("--update-nixpkgs", action="store_true", help="also run `nix flake update`")
    ap.add_argument("--summary", type=Path, help="write a markdown list of changes here")
    args = ap.parse_args()
    unknown = set(args.agents) - set(ALL)
    if unknown:
        ap.error(f"unknown agent(s): {', '.join(sorted(unknown))}")
    agents = args.agents or ALL

    system = current_system()
    changes, failures = [], []

    if args.update_nixpkgs and not args.dry_run:
        snap = snapshot()
        before = (ROOT / "flake.lock").read_bytes()
        run("nix", "flake", "update")
        if (ROOT / "flake.lock").read_bytes() != before:
            log("Checking all packages against updated nixpkgs...")
            broken = [a for a in ALL if build(system, a).returncode != 0]
            if broken:
                restore(snap)
                failures.append(f"nixpkgs update (breaks {', '.join(broken)})")
                log(f"  nixpkgs update reverted: breaks {', '.join(broken)}")
            else:
                changes.append("nixpkgs: updated flake.lock")

    for name in agents:
        log(f"Checking {name}...")
        snap = snapshot()
        try:
            if name in RELEASES:
                change = update_release(name, args.dry_run)
            elif name == "claude-code":
                change = update_claude_code(system, args.dry_run)
            else:
                change = update_agent(name, system, args.dry_run)
            if change is None:
                log("  up to date")
                continue
            if not args.dry_run:
                proc = build(system, name)
                if proc.returncode != 0:
                    raise UpdateError(f"build failed:\n{proc.stderr[-4000:]}")
            log(f"  {change}")
            changes.append(change)
        except (UpdateError, OSError) as e:
            restore(snap)
            log(f"  FAILED, rolled back: {e}")
            failures.append(name)

    if args.summary:
        lines = [f"- {c}" for c in changes] + [f"- FAILED: {f}" for f in failures]
        args.summary.write_text("\n".join(lines) + "\n")
    log("")
    log("Updates:" if changes else "No updates.")
    for c in changes:
        log(f"  {c}")
    if failures:
        log(f"Failed (rolled back): {', '.join(failures)}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
