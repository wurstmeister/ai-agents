{
  lib,
  stdenv,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  installShellFiles,
  unzip,
  versionCheckHook,
  pname,
  version,
  url,
  hash,
  # Path of the executable inside the archive
  binary ? null,
  # The download is the executable itself rather than an archive.
  rawBinary ? false,
  # Complete package directory inside the archive. When set, retain its
  # contents so binaries can discover their bundled metadata and helpers.
  packageRoot ? null,
  mainProgram ? pname,
  # Patch glibc-linked Linux executables to run against Nix's glibc.
  patchElf ? false,
  # Added to PATH of the wrapped program
  runtimeInputs ? [ ],
  # Extra makeWrapper arguments
  wrapperArgs ? [ ],
  # Agents without a native --yolo set this to the flag it maps to. The
  # wrapper rewrites --yolo to it unless it follows a `--` separator.
  yoloFlag ? null,
  # Generate completions via `<program> completion <shell>`
  completions ? false,
  # Extra attributes for the derivation
  extraAttrs ? { },
  meta ? { },
}:

assert rawBinary || binary != null;

let
  yoloTranslation = ''
    args=()
    for arg in "$@"; do
      if [[ "$arg" == -- ]]; then
        args+=("$@")
        break
      elif [[ "$arg" == --yolo ]]; then
        args+=(${yoloFlag})
      else
        args+=("$arg")
      fi
      shift
    done
    set -- "''${args[@]}"
  '';
  executable =
    if rawBinary then
      "$src"
    else if packageRoot == null then
      lib.escapeShellArg binary
    else
      "${lib.escapeShellArg packageRoot}/${lib.escapeShellArg binary}";
  needsPatch = patchElf && stdenvNoCC.hostPlatform.isElf;
in
stdenvNoCC.mkDerivation (
  {
    inherit pname version;

    src = fetchurl { inherit url hash; };
    sourceRoot = ".";
    dontUnpack = rawBinary;

    nativeBuildInputs = [
      makeWrapper
      installShellFiles
    ]
    ++ lib.optionals (lib.hasSuffix ".zip" url) [ unzip ]
    ++ lib.optionals needsPatch [ autoPatchelfHook ];
    buildInputs = lib.optionals needsPatch [ stdenv.cc.cc.lib ];

    dontConfigure = true;
    dontBuild = true;
    # Release binaries are already stripped, and stripping corrupts the
    # payload embedded in Bun/Node single-file executables.
    dontStrip = true;

    installPhase = ''
      runHook preInstall
      ${
        if packageRoot == null then
          "install -Dm755 ${executable} $out/libexec/${mainProgram}"
        else
          ''
            install -d $out/libexec/${mainProgram}
            cp -a ${lib.escapeShellArg packageRoot}/. $out/libexec/${mainProgram}
          ''
      }
      makeWrapper ${
        if packageRoot == null then
          "$out/libexec/${mainProgram}"
        else
          "$out/libexec/${mainProgram}/${binary}"
      } $out/bin/${mainProgram} \
        ${lib.optionalString (yoloFlag != null) "--run ${lib.escapeShellArg yoloTranslation}"} \
        ${lib.optionalString (runtimeInputs != [ ]) "--prefix PATH : ${lib.makeBinPath runtimeInputs}"} \
        ${lib.escapeShellArgs wrapperArgs}
      runHook postInstall
    '';

    postInstall =
      lib.optionalString (completions && stdenvNoCC.buildPlatform.canExecute stdenvNoCC.hostPlatform)
        ''
          export HOME=$(mktemp -d)
          installShellCompletion --cmd ${mainProgram} \
            --bash <($out/bin/${mainProgram} completion bash) \
            --fish <($out/bin/${mainProgram} completion fish) \
            --zsh <($out/bin/${mainProgram} completion zsh)
        '';

    doInstallCheck = true;
    nativeInstallCheckInputs = [ versionCheckHook ];
    versionCheckProgramArg = "--version";
    preInstallCheck = "export HOME=$(mktemp -d)";
    versionCheckKeepEnvironment = [ "HOME" ];

    meta = {
      inherit mainProgram;
      sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
      platforms = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
    }
    // meta;
  }
  // extraAttrs
)
