; Reusable nixpkgs version override. `pkgs` is provided by the importing
; flake's per-system binding.
(fn [name version (args :tagFormat (optional (interpolate "v" version)))]
  (let [pkg (attr pkgs (dynamic name))]
    (call (attr pkg overrideAttrs)
      (fn [oldAttrs]
        (attrs
          :version version
          :src (call (attr oldAttrs src overrideAttrs)
                 (fn [srcAttrs]
                   (attrs :tag tagFormat
                          :rev tagFormat)))
          :doCheck false
          :disabledTests
          (++ (or (attr oldAttrs disabledTests) [])
              ["test_separate_git_dir_linked_worktree_cannot_infer_primary_root"
               "test_separate_git_dir_uses_primary_worktree_root"]))))))
