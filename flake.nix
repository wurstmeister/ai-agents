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
    flake-utils.lib.eachDefaultSystem (
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

        # Override versions here for quick updates
        # Each agent uses nixpkgs as the base but pins a specific version
        versions = {
          opencode = "1.18.29";
          claude-code = "2.1.261"; # from pkgs/claude-code/manifest.json
          codex = "0.153.4";
          qwen-code = "0.23.0";
          goose = "3.28.0";
          aichat = "0.30.0";
          aider-chat = "0.86.0";
          mistral-vibe = "2.25.0";
          pi-coding-agent = "0.84.2";
          codebuff = "1.0.684";
        };

        # Hashes for binary fetch agents (opencode)
        hashes = {
          opencode = "sha256-/nZPfzYMWEqD4Y3V8j+xprJyX17ohUsCUv5Vj3eY6UY=";
        };

# Build agents from nixpkgs with overridden versions
        # Most use fetchFromGitHub, so we override the source
        mkAgent =
          name: version: { tagFormat ? "v${version}" }:
          let
            pkg = pkgs.${name};
          in
          pkg.overrideAttrs (oldAttrs: {
            version = version;
            src = oldAttrs.src.overrideAttrs (srcAttrs: {
              tag = tagFormat;
              rev = tagFormat;
            });
            doCheck = false;
            disabledTests = (oldAttrs.disabledTests or [ ]) ++ [
              "test_separate_git_dir_linked_worktree_cannot_infer_primary_root"
              "test_separate_git_dir_uses_primary_worktree_root"
            ];
          });

        # Tag format overrides for agents with non-standard tags
        tagFormats = {
          codex = "rust-v${versions.codex}";
          # Add more as needed
        };

        getTagFormat = name: tagFormats.${name} or "v${versions.${name}}";

        # Simple agents that use fetchFromGitHub
        codex = mkAgent "codex" versions.codex { tagFormat = getTagFormat "codex"; };
        qwen-code = mkAgent "qwen-code" versions.qwen-code { tagFormat = getTagFormat "qwen-code"; };
        goose = mkAgent "goose" versions.goose { tagFormat = getTagFormat "goose"; };
        aichat = mkAgent "aichat" versions.aichat { tagFormat = getTagFormat "aichat"; };
        aider-chat = mkAgent "aider-chat" versions.aider-chat { tagFormat = getTagFormat "aider-chat"; };
        mistral-vibe = mkAgent "mistral-vibe" versions.mistral-vibe { tagFormat = getTagFormat "mistral-vibe"; };
        pi-coding-agent = mkAgent "pi-coding-agent" versions.pi-coding-agent { tagFormat = getTagFormat "pi-coding-agent"; };
        codebuff = mkAgent "codebuff" versions.codebuff { tagFormat = getTagFormat "codebuff"; };

        # opencode uses binary fetch for fast builds and easy version overrides
        opencode = pkgs.callPackage ./pkgs/opencode {
          version = versions.opencode;
          hash = hashes.opencode;
        };

        # claude-code uses a manifest, needs special handling
        # Use our local package that allows version overrides
        claude-code = pkgs.callPackage ./pkgs/claude-code {
          version = versions.claude-code;
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
