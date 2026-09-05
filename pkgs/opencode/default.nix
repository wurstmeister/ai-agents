{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  unzip,
  version ? "1.18.18",
  hash ? "sha256-fWaL8mSW/shobU5R67GsK9Ljk/DBYgqmlsTCQqnlgGo=",
  ...
}:

let
  # Platform detection
  platform =
    if stdenv.hostPlatform.isDarwin then
      if stdenv.hostPlatform.isx86_64 then "darwin-x64" else "darwin-arm64"
    else if stdenv.hostPlatform.isLinux then
      if stdenv.hostPlatform.isx86_64 then "linux-x64" else "linux-arm64"
    else
      throw "Unsupported platform: ${stdenv.system}";

  # Binary archive name from GitHub releases
  archiveName =
    if stdenv.hostPlatform.isDarwin then "opencode-${platform}.zip" else "opencode-${platform}.tar.gz";

  # GitHub release URL
  githubOwner = "anomalyco";
  githubRepo = "opencode";
  url = "https://github.com/${githubOwner}/${githubRepo}/releases/download/v${version}/${archiveName}";

in
stdenv.mkDerivation rec {
  pname = "opencode";
  inherit version;

  src = fetchurl {
    inherit url hash;
  };

  nativeBuildInputs = [
    makeWrapper
    unzip
  ]
  ++ lib.optionals stdenv.hostPlatform.isElf [ autoPatchelfHook ];
  buildInputs = lib.optionals stdenv.hostPlatform.isElf [ stdenv.cc.cc.lib ];

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    extractDir="$TMPDIR/opencode-extract"
    rm -rf "$extractDir"
    mkdir -p "$extractDir" $out/bin

    # Extract the archive based on type
    if [[ "$src" == *.zip ]]; then
      unzip -o "$src" -d "$extractDir"
      binary="$extractDir/opencode"
    elif [[ "$src" == *.tar.gz ]]; then
      tar -xzf "$src" -C "$extractDir"
      # Find the binary - it might be in a subdirectory
      binary=$(find "$extractDir" -name "opencode" -type f | head -1)
    else
      echo "Unknown archive type: $src" >&2
      exit 1
    fi

    # Make the binary executable
    chmod +x "$binary"

    # Move the real binary under a private name so the wrapper below
    # doesn't overwrite itself (which would recurse forever on run)
    cp "$binary" $out/bin/.opencode-wrapped

    # Create wrapper with NODE_OPTIONS
    makeWrapper $out/bin/.opencode-wrapped $out/bin/opencode \
      --prefix NODE_OPTIONS : "--max-old-space-size=8192"

    runHook postInstall
  '';

  meta = with lib; {
    description = "The open source AI coding agent";
    homepage = "https://opencode.ai";
    license = licenses.mit;
    maintainers = with maintainers; [ ];
    mainProgram = "opencode";
    platforms = platforms.linux ++ platforms.darwin;
  };
}
