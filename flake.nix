{
  description = "Popular coding agents with quick version overrides";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachSystem
      [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ]
      (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfreePredicate =
              pkg:
              builtins.elem (pkgs.lib.getName pkg) [
                "claude-code"
                "textual-speedups"
              ];
          };

          inherit (pkgs) lib;

          # All versions and hashes live in sources.json, maintained by
          # ./update-versions.py. claude-code's version comes from its manifest.
          sources = lib.importJSON ./sources.json;
          fetchGitHub =
            old: s:
            pkgs.fetchFromGitHub {
              inherit (old.src) owner repo;
              inherit (s) tag hash;
            };

          # Pin a nixpkgs package to the version in sources.json. When nixpkgs
          # already ships that version, use it unchanged (binary cache hit).
          # Otherwise override the source *and* every fixed-output fetcher that
          # depends on it; overriding only `src.tag` silently reuses stale
          # sources, and `cargoHash`/`npmDepsHash` do not propagate through
          # overrideAttrs.
          pin =
            name: attr: override:
            let
              s = sources.${name};
              base = pkgs.${attr};
            in
            if base.version == s.version then
              base
            else
              base.overrideAttrs (old: { version = s.version; } // override s old);

          rust =
            s: old:
            let
              src = fetchGitHub old s;
            in
            {
              inherit src;
              cargoDeps = pkgs.rustPlatform.fetchCargoVendor (
                {
                  inherit src;
                  name = "${old.pname}-${s.version}-vendor";
                  hash = s.cargoHash;
                  patches = old.cargoPatches or [ ];
                }
                // lib.optionalAttrs (old ? sourceRoot) { inherit (old) sourceRoot; }
                // lib.optionalAttrs (old ? cargoRoot) { inherit (old) cargoRoot; }
              );
            };

          npmDeps =
            s: old: src: extra:
            old.npmDeps.overrideAttrs (
              {
                inherit src;
                name = "${old.pname}-${s.version}-npm-deps";
                outputHash = s.npmDepsHash;
              }
              // extra
            );

          npm =
            s: old:
            let
              src = fetchGitHub old s;
            in
            {
              inherit src;
              npmDeps = npmDeps s old src { };
            };

          python = s: old: { src = fetchGitHub old s; };

          aichat = pin "aichat" "aichat" rust;
          qwen-code = pin "qwen-code" "qwen-code" npm;
          pi-coding-agent = pin "pi-coding-agent" "pi-coding-agent" (
            s: old:
            npm s old
            // {
              modelData = pkgs.fetchurl {
                url = "https://registry.npmjs.org/@earendil-works/pi-ai/-/pi-ai-${s.version}.tgz";
                hash = s.modelDataHash;
              };
            }
          );
          aider-chat = pin "aider-chat" "aider-chat" python;
          mistral-vibe = pin "mistral-vibe" "mistral-vibe" python;
          # codebuff ships no lock file; ./update-versions.py regenerates ours.
          codebuff = pin "codebuff" "codebuff" (
            s: old:
            let
              src = pkgs.fetchzip {
                url = "https://registry.npmjs.org/codebuff/-/codebuff-${s.version}.tgz";
                inherit (s) hash;
              };
              lockPatch = "cp ${./pkgs/codebuff/package-lock.json} package-lock.json";
            in
            {
              inherit src;
              # Some releases ship monorepo pack scripts (../release-core/...)
              # that don't exist in the tarball; the tarball is already built.
              postPatch = ''
                ${lockPatch}
                ${lib.getExe pkgs.jq} 'del(.scripts)' package.json > package.json.tmp
                mv package.json.tmp package.json
              '';
              npmDeps = npmDeps s old src { postPatch = lockPatch; };
            }
          );

          # Codex and Goose are large Rust builds; use upstream's published
          # artifacts (static musl builds on Linux) instead of compiling.
          triple =
            {
              aarch64-darwin = "aarch64-apple-darwin";
              aarch64-linux = "aarch64-unknown-linux-musl";
              x86_64-linux = "x86_64-unknown-linux-musl";
            }
            .${system};
          codexPlatform =
            {
              aarch64-darwin = "darwin-arm64";
              aarch64-linux = "linux-arm64";
              x86_64-linux = "linux-x64";
            }
            .${system};
          releaseBinary =
            name: args:
            pkgs.callPackage ./pkgs/release-binary (
              {
                pname = name;
                inherit (sources.${name}) version;
                hash = sources.${name}.hashes.${system};
              }
              // args
            );

          codex = releaseBinary "codex" {
            # The GitHub archive only ships a binary. Codex's app-server
            # requires the complete package layout and companion binaries.
            url = "https://registry.npmjs.org/@openai/codex/-/codex-${sources.codex.version}-${codexPlatform}.tgz";
            binary = "bin/codex";
            packageRoot = "package/vendor/${triple}";
            runtimeInputs = [
              pkgs.ripgrep
            ]
            ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.bubblewrap ];
            completions = true;
            meta = { inherit (pkgs.codex.meta) description homepage license; };
          };

          # Block/AAIF's goose agent (nixpkgs `goose` is an unrelated DB migration tool)
          goose = releaseBinary "goose" {
            url = "https://github.com/aaif-goose/goose/releases/download/v${sources.goose.version}/goose-${triple}.tar.gz";
            binary = "goose";
            runtimeInputs =
              with pkgs;
              [
                bash
                python3
              ]
              ++ lib.optionals stdenv.hostPlatform.isLinux [
                xdotool
                wmctrl
                xclip
                xwininfo
                wtype
                wl-clipboard
              ];
            meta = { inherit (pkgs.goose-cli.meta) description homepage license; };
          };

          # opencode uses binary fetch for fast builds and easy version overrides
          opencode = pkgs.callPackage ./pkgs/opencode {
            inherit (sources.opencode) version;
            hash =
              sources.opencode.hashes.${
                if pkgs.stdenv.hostPlatform.isDarwin then
                  if pkgs.stdenv.hostPlatform.isx86_64 then "darwin-x64" else "darwin-arm64"
                else if pkgs.stdenv.hostPlatform.isx86_64 then
                  "linux-x64"
                else
                  "linux-arm64"
              };
          };

          # claude-code is fetched from Anthropic's release manifest
          claude-code = pkgs.callPackage ./pkgs/claude-code {
            inherit ((lib.importJSON ./pkgs/claude-code/manifest.json)) version;
          };

        in
        {
          packages = {
            default = opencode;
            inherit
              opencode
              claude-code
              codex
              qwen-code
              goose
              aichat
              aider-chat
              mistral-vibe
              pi-coding-agent
              codebuff
              ;
          };

          checks = pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
            opencode-nixos = pkgs.testers.nixosTest {
              name = "opencode-nixos";
              nodes.machine = { ... }: {
                environment.systemPackages = [ opencode ];
              };
              testScript = ''
                machine.succeed("opencode --version")
              '';
            };
          };

          apps = {
            default = {
              type = "app";
              program = "${opencode}/bin/opencode";
            };
            claude-code = {
              type = "app";
              program = "${claude-code}/bin/claude";
            };
            codex = {
              type = "app";
              program = "${codex}/bin/codex";
            };
          };

          devShells.default = pkgs.mkShell {
            packages = [
              opencode
              claude-code
              codex
              qwen-code
              goose
              aichat
              aider-chat
              mistral-vibe
              pi-coding-agent
              codebuff
            ];
          };

          formatter = pkgs.nixfmt;
        }
      );
}
