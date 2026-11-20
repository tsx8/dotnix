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
  # Upstream no longer tags releases; keep the display version in sync with the pinned pubspec.
  version = "1.11.7";

  src = appSrc;
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
