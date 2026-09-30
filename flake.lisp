; DSL source for flake.nix.
;
; Compile with the nix-lisp-dsl Clojure CLI from this directory so the
; generated flake.nix keeps ./pkgs paths relative to the repository root:
;   lein run -- flake.lisp flake.nix
(flake
  :description "Popular coding agents with quick version overrides"
  :inputs {:nixpkgs {:url "github:NixOS/nixpkgs/nixos-unstable"}
           :flake-utils {:url "github:numtide/flake-utils"}}
  :unfree ["claude-code" "textual-speedups"]
  :bindings [

              ; Override versions here for quick updates.
              versions (attrs
                         :opencode "1.18.29"
                         :claude-code "2.1.261"
                         :codex "0.153.4"
                         :qwen-code "0.23.0"
                         :goose "3.28.0"
                         :aichat "0.30.0"
                         :aider-chat "0.86.0"
                         :mistral-vibe "2.25.0"
                         :pi-coding-agent "0.84.2"
                         :codebuff "1.0.684")

              ; Hashes for binary fetch agents (opencode).
              hashes (attrs
                       :opencode "sha256-/nZPfzYMWEqD4Y3V8j+xprJyX17ohUsCUv5Vj3eY6UY=")

              ; Build agents from nixpkgs with overridden versions.
              mkAgent (dsl-import "./mk_agent.lisp")

              ; Tag format overrides for agents with non-standard tags.
              tagFormats (attrs
                           :codex (interpolate "rust-v" (attr versions codex)))

              getTagFormat (fn [name]
                             (or (attr tagFormats (dynamic name))
                                 (interpolate "v" (attr versions (dynamic name)))))

              codex (mkAgent "codex" (attr versions codex)
                      (attrs :tagFormat (getTagFormat "codex")))
              qwen-code (mkAgent "qwen-code" (attr versions qwen-code)
                          (attrs :tagFormat (getTagFormat "qwen-code")))
              goose (mkAgent "goose" (attr versions goose)
                      (attrs :tagFormat (getTagFormat "goose")))
              aichat (mkAgent "aichat" (attr versions aichat)
                       (attrs :tagFormat (getTagFormat "aichat")))
              aider-chat (mkAgent "aider-chat" (attr versions aider-chat)
                           (attrs :tagFormat (getTagFormat "aider-chat")))
              mistral-vibe (mkAgent "mistral-vibe" (attr versions mistral-vibe)
                             (attrs :tagFormat (getTagFormat "mistral-vibe")))
              pi-coding-agent (mkAgent "pi-coding-agent" (attr versions pi-coding-agent)
                                (attrs :tagFormat (getTagFormat "pi-coding-agent")))
              codebuff (mkAgent "codebuff" (attr versions codebuff)
                         (attrs :tagFormat (getTagFormat "codebuff")))

              ; opencode uses a binary fetch for fast builds.
              opencode (call (attr pkgs callPackage) (path "pkgs/opencode")
                         (attrs :version (attr versions opencode)
                                :hash (attr hashes opencode)))

              ; claude-code uses a manifest and a local package.
               claude-code (pkgs.callPackage (path "pkgs/claude-code")
                            (attrs :version (attr versions claude-code)))]

  :packages {:opencode opencode :claude-code claude-code :codex codex
             :qwen-code qwen-code :goose goose :aichat aichat
             :aider-chat aider-chat :mistral-vibe mistral-vibe
             :pi-coding-agent pi-coding-agent :codebuff codebuff}
  :default-package :opencode

  :apps {:default {:type "app" :program (interpolate opencode "/bin/opencode")}
         :claude-code {:type "app" :program (interpolate claude-code "/bin/claude")}
         :codex {:type "app" :program (interpolate codex "/bin/codex")}}

  :dev-shell [opencode claude-code codex qwen-code goose aichat aider-chat
              mistral-vibe pi-coding-agent codebuff]
  :formatter pkgs.nixfmt)
