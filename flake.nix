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
            wrapperArgs = [
              "--add-flags"
              "-c check_for_update_on_startup=false"
            ];
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

          opencodePlatform =
            {
              aarch64-darwin = "darwin-arm64";
              aarch64-linux = "linux-arm64";
              x86_64-linux = "linux-x64";
            }
            .${system};
          opencode = releaseBinary "opencode" {
            url = "https://github.com/anomalyco/opencode/releases/download/v${sources.opencode.version}/opencode-${opencodePlatform}.${
              if pkgs.stdenv.hostPlatform.isDarwin then "zip" else "tar.gz"
            }";
            binary = "opencode";
            patchElf = true;
            yoloFlag = "--auto";
            # Nix manages updates; the store copy cannot replace itself.
            wrapperArgs = [
              "--set"
              "OPENCODE_DISABLE_AUTOUPDATE"
              "1"
              "--prefix"
              "NODE_OPTIONS"
              ":"
              "--max-old-space-size=8192"
            ];
            meta = { inherit (pkgs.opencode.meta) description homepage license; };
          };

          # claude-code is fetched from Anthropic's release manifest, which
          # lists a hex sha256 per platform.
          claudeManifest = lib.importJSON ./pkgs/claude-code/manifest.json;
          claudePlatform = "${pkgs.stdenv.hostPlatform.node.platform}-${pkgs.stdenv.hostPlatform.node.arch}";
          claude-code = pkgs.callPackage ./pkgs/release-binary {
            pname = "claude-code";
            version = claudeManifest.version;
            url = "https://downloads.claude.ai/claude-code-releases/${claudeManifest.version}/${claudePlatform}/claude";
            hash = builtins.convertHash {
              hash = claudeManifest.platforms.${claudePlatform}.checksum;
              hashAlgo = "sha256";
              toHashFormat = "sri";
            };
            rawBinary = true;
            mainProgram = "claude";
            patchElf = true;
            yoloFlag = "--dangerously-skip-permissions";
            # procps: tree-kill needs pgrep/ps; ripgrep replaces the bundled
            # one; bubblewrap and socat back the Linux sandbox.
            runtimeInputs = [
              pkgs.procps
              pkgs.ripgrep
            ]
            ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
              pkgs.bubblewrap
              pkgs.socat
            ];
            wrapperArgs = [
              "--set"
              "DISABLE_AUTOUPDATER"
              "1"
              "--set"
              "DISABLE_INSTALLATION_CHECKS"
              "1"
              "--set"
              "USE_BUILTIN_RIPGREP"
              "0"
            ]
            ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
              "--prefix"
              "LD_LIBRARY_PATH"
              ":"
              (lib.makeLibraryPath [ pkgs.alsa-lib ])
            ];
            extraAttrs = lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin { __noChroot = true; };
            meta = { inherit (pkgs.claude-code.meta) description homepage license; };
          };

          # Behavioural check of the wrappers: each package is rebuilt around a
          # stub that echoes its arguments, so we see what the agent receives.
          stubArchive =
            files:
            pkgs.runCommand "agent-stub.tar.gz" { } ''
              mkdir -p stub
              for f in ${lib.escapeShellArgs files}; do
                mkdir -p "stub/$(dirname "$f")"
                printf '#!/bin/sh\nfor a in "$@"; do echo "$a"; done\n' > "stub/$f"
                chmod +x "stub/$f"
              done
              tar -czf $out -C stub .
            '';
          stubRaw = pkgs.writeScript "claude" ''
            #!/bin/sh
            for a in "$@"; do echo "$a"; done
          '';
          withStub =
            pkg: src:
            pkg.overrideAttrs {
              inherit src;
              doInstallCheck = false;
            };
          yoloCases = [
            {
              pkg = withStub claude-code stubRaw;
              program = "claude";
              expect = "--dangerously-skip-permissions";
            }
            {
              pkg = withStub opencode (stubArchive [ "opencode" ]);
              program = "opencode";
              expect = "--auto";
            }
            {
              pkg = withStub codex (stubArchive [ "bin/codex" ]);
              program = "codex";
              expect = "--yolo";
            }
            {
              pkg = withStub copilot-cli (stubArchive [ "copilot" ]);
              program = "copilot";
              expect = "--yolo";
            }
          ];
          yolo-wrappers = pkgs.runCommand "yolo-wrappers" { } ''
            ${lib.concatMapStringsSep "\n" (c: ''
              bin=${c.pkg}/bin/${c.program}
              # --yolo reaches the agent as its native flag
              "$bin" --yolo task | grep -Fx -- ${lib.escapeShellArg c.expect}
              # without --yolo the agent keeps its normal permission behaviour
              if "$bin" task | grep -Fx -- ${lib.escapeShellArg c.expect}; then
                echo "${c.program}: permission flag injected without --yolo" >&2
                exit 1
              fi
              # after `--` the argument is passed through unchanged
              "$bin" -- --yolo | grep -Fx -- --yolo
            '') yoloCases}
            touch $out
          '';

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

          checks = {
            inherit yolo-wrappers;
          }
          // pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
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
