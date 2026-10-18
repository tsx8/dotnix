{
  lib,
  flutter347,
  autoPatchelfHook,
  mpv-unwrapped,
  alsa-lib,
  makeDesktopItem,
  copyDesktopItems,
  appSrc,
}:

flutter347.buildFlutterApplication {
  pname = "simple-live-app";
  # Upstream master no longer gets version tags; the version comes from the pubspec description of the pinned
  # commit, and rev tracking is left to the flake input.
  version = "1.11.7";

  src = appSrc;
  # A directory-typed src unpacks under the source/ prefix.
  sourceRoot = "source/simple_live_app";
  pubspecLock = lib.importJSON ./pubspec.lock.json;
  gitHashes = {
    dart_quickjs = "sha256-pG/ilzlQdWhR4oWBKFkjsRWLOgajhiZFdseT99uDhW8=";
    native_toolchain_c = "sha256-pG/ilzlQdWhR4oWBKFkjsRWLOgajhiZFdseT99uDhW8=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    copyDesktopItems
  ];
  buildInputs = [
    mpv-unwrapped
    alsa-lib
  ];

  desktopItems = [
    (makeDesktopItem {
      name = "simple-live-app";
      exec = "simple_live_app";
      icon = "simple-live-app";
      desktopName = "Simple Live";
      categories = [
        "AudioVideo"
        "Video"
      ];
    })
  ];

  postInstall = ''
    install -Dm644 assets/logo.png $out/share/icons/simple-live-app.png
  '';
  extraWrapProgramArgs = ''
    --prefix LD_LIBRARY_PATH : $out/app/simple-live-app/lib
  '';

  meta = {
    description = "Multi-platform live streaming client";
    homepage = "https://github.com/xiaoyaocz/dart_simple_live";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
    mainProgram = "simple_live_app";
  };
}
