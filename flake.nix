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
                "copilot-cli"
              ];
          };

          inherit (pkgs) lib;

          # All versions and hashes live in sources.json, maintained by
          # ./update-versions.py. claude-code's version comes from its manifest.
          sources = lib.importJSON ./sources.json;

          # Codex retains its complete upstream package (static musl builds on
          # Linux) so its bundled helpers remain available at runtime.
          triple =
            {
              aarch64-darwin = "aarch64-apple-darwin";
              aarch64-linux = "aarch64-unknown-linux-musl";
              x86_64-linux = "x86_64-unknown-linux-musl";
            }
            .${system};
          copilotPlatform =
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
            url = "https://github.com/openai/codex/releases/download/rust-v${sources.codex.version}/codex-package-${triple}.tar.gz";
            binary = "bin/codex";
            packageRoot = ".";
            runtimeInputs = [
              pkgs.ripgrep
            ]
            ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.bubblewrap ];
            completions = true;
            meta = { inherit (pkgs.codex.meta) description homepage license; };
          };

          # The platform-specific single-executable release; its universal package
          # is only an npm loader for these binaries.
          copilot-cli = releaseBinary "copilot-cli" {
            url = "https://github.com/github/copilot-cli/releases/download/v${sources.copilot-cli.version}/copilot-${copilotPlatform}.tar.gz";
            binary = "copilot";
            mainProgram = "copilot";
            patchElf = true;
            # Nix manages updates; the store copy cannot replace itself.
            wrapperArgs = [
              "--add-flags"
              "--no-auto-update"
            ];
            meta = {
              inherit (pkgs.github-copilot-cli.meta) description homepage license;
            };
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
              copilot-cli
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
            copilot-cli = {
              type = "app";
              program = "${copilot-cli}/bin/copilot";
            };
          };

          devShells.default = pkgs.mkShell {
            packages = [
              opencode
              claude-code
              codex
              copilot-cli
            ];
          };

          formatter = pkgs.nixfmt;
        }
      );
}
