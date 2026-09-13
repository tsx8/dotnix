{
  lib,
  flutter347,
  fetchFromGitHub,
  autoPatchelfHook,
  mpv-unwrapped,
  alsa-lib,
  makeDesktopItem,
  copyDesktopItems,
}:

flutter347.buildFlutterApplication {
  pname = "simple-live-app";
  version = "1.11.7";

  src = fetchFromGitHub {
    owner = "xiaoyaocz";
    repo = "dart_simple_live";
    rev = "bccd2ba2e77bc34b3e3a0897f1cb5e0b402afd2b";
    hash = "sha256-WeS7gfrcIez/BUKYGdArIwLziiDEI7ib1fT2J/pHVQM=";
  };
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
