#!/usr/bin/env python3
"""Verify release selection and hashes on every supported system."""
import importlib.util
import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True
RELEASE_HASH_AGENTS = ("codex", "goose", "qwen-code", "pi-coding-agent", "mistral-vibe")

spec = importlib.util.spec_from_file_location("updater", Path(__file__).with_name("update-versions.py"))
updater = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updater)


def main():
    sources = updater.load_sources()
    for name in RELEASE_HASH_AGENTS:
        release = updater.RELEASES[name]
        entry = sources[name]
        tag = release["tag_format"].format(version=entry["version"])
        for system, template in release["assets"].items():
            url = template.format(tag=tag, version=entry["version"])
            attr = f".#packages.{system}.{name}.src"
            urls = json.loads(updater.run("nix", "eval", "--json", attr + ".urls").stdout)
            pinned = updater.run("nix", "eval", "--raw", attr + ".outputHash").stdout
            expected = entry["hashes"][system]
            if urls != [url] or pinned != expected:
                raise updater.UpdateError(f"{name} {system}: flake and updater disagree on release URL/hash")
            actual = json.loads(
                updater.run(
                    "nix",
                    "store",
                    "prefetch-file",
                    "--json",
                    "--hash-type",
                    release.get("hash_type", "sha256"),
                    url,
                ).stdout
            )["hash"]
            if actual != expected:
                raise updater.UpdateError(f"{name} {system}: expected {expected}, got {actual}")
            print(f"{name} {system}: official release hash OK ({entry['version']})", flush=True)


if __name__ == "__main__":
    main()
