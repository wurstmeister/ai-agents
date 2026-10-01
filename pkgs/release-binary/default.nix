{
  lib,
  stdenvNoCC,
  fetchurl,
  makeBinaryWrapper,
  installShellFiles,
  unzip,
  versionCheckHook,
  pname,
  version,
  url,
  hash,
  # Path of the executable inside the archive
  binary,
  # Complete package directory inside the archive. When set, retain its
  # contents so binaries can discover their bundled metadata and helpers.
  packageRoot ? null,
  # Some release archives ship a launcher without an executable mode bit.
  makeExecutable ? false,
  mainProgram ? pname,
  # Added to PATH of the wrapped program
  runtimeInputs ? [ ],
  # Generate completions via `<program> completion <shell>`
  completions ? false,
  meta ? { },
}:

stdenvNoCC.mkDerivation {
  inherit pname version;

  src = fetchurl { inherit url hash; };
  sourceRoot = ".";

  nativeBuildInputs = [
    makeBinaryWrapper
    installShellFiles
    unzip
  ];

  dontConfigure = true;
  dontBuild = true;
  # Release binaries are already stripped; stripping can break embedded payloads.
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    ${
      if packageRoot == null then
        "install -Dm755 ${lib.escapeShellArg binary} $out/libexec/${mainProgram}"
      else
        ''
          install -d $out/libexec/${mainProgram}
          cp -a ${lib.escapeShellArg packageRoot}/. $out/libexec/${mainProgram}
        ''
    }
    ${lib.optionalString makeExecutable "chmod +x $out/libexec/${mainProgram}/${binary}"}
    makeWrapper ${
      if packageRoot == null then
        "$out/libexec/${mainProgram}"
      else
        "$out/libexec/${mainProgram}/${binary}"
    } $out/bin/${mainProgram} \
      ${lib.optionalString (runtimeInputs != [ ]) "--prefix PATH : ${lib.makeBinPath runtimeInputs}"}
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
