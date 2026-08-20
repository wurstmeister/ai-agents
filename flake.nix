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
            pkg: builtins.elem (pkgs.lib.getName pkg) [ "claude-code" ];
        };

        # Override versions here for quick updates
        # Each agent uses nixpkgs as the base but pins a specific version
        versions = {
          claude-code = "2.1.235"; # from pkgs/claude-code/manifest.json
          codex = "0.147.0";
          qwen-code = "0.16.0";
          goose = "3.27.3";
          aichat = "0.30.0";
          aider-chat = "0.86.1";
        };

        # Build agents from nixpkgs with overridden versions
        # Most use fetchFromGitHub, so we override the source
        mkAgent =
          name: version:
          let
            pkg = pkgs.${name};
          in
          pkg.overrideAttrs (oldAttrs: {
            version = version;
            # Most agents use fetchFromGitHub with tag/rev
            src = oldAttrs.src.overrideAttrs (srcAttrs: {
              # Try to override common attributes
              tag = "v${version}";
              rev = "v${version}";
            });
          });

        # Simple agents that use fetchFromGitHub
        codex = mkAgent "codex" versions.codex;
        qwen-code = mkAgent "qwen-code" versions.qwen-code;
        goose = mkAgent "goose" versions.goose;
        aichat = mkAgent "aichat" versions.aichat;
        aider-chat = mkAgent "aider-chat" versions.aider-chat;

        # opencode from nixpkgs (source build, follows nixpkgs version)
        opencode = pkgs.opencode;

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
          ];
        };

        formatter = pkgs.nixfmt;
      }
    );
}
