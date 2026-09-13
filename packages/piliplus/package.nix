{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  wrapGAppsHook3,
  makeDesktopItem,
  copyDesktopItems,
  gtk3,
  alsa-lib,
  libayatana-appindicator,
  libayatana-indicator,
  ayatana-ido,
  libdbusmenu,
  webkitgtk_4_1,
  mpv-unwrapped,
  jre,
}:

stdenv.mkDerivation {
  pname = "piliplus";
  version = "2.1.4";

  # Upstream releases include its Flutter framework and dependency patches.
  src = fetchurl {
    url = "https://github.com/bggRGjQaUbCoE/PiliPlus/releases/download/2.1.4/PiliPlus_linux_2.1.4%2B5348_amd64.tar.gz";
    hash = "sha256-HTS62YYUbXw75k87qokI85UQen6QNNfdi3xeaekpH1g=";
  };
  sourceRoot = ".";

  nativeBuildInputs = [
    autoPatchelfHook
    wrapGAppsHook3
    copyDesktopItems
  ];
  buildInputs = [
    gtk3
    alsa-lib
    libayatana-appindicator
    libayatana-indicator
    ayatana-ido
    libdbusmenu
    webkitgtk_4_1
    mpv-unwrapped
    jre
    stdenv.cc.cc.lib
  ];
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/opt/piliplus $out/bin
    cp -r piliplus lib data $out/opt/piliplus/
    ln -s $out/opt/piliplus/piliplus $out/bin/piliplus
    install -Dm644 data/flutter_assets/assets/images/logo/logo.png $out/share/icons/hicolor/256x256/apps/piliplus.png
    runHook postInstall
  '';

  preFixup = ''
    addAutoPatchelfSearchPath ${jre}/lib/openjdk/lib/server
    gappsWrapperArgs+=(--prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ mpv-unwrapped ]})
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "piliplus";
      desktopName = "PiliPlus";
      exec = "piliplus";
      icon = "piliplus";
      categories = [
        "AudioVideo"
        "Video"
      ];
    })
  ];

  meta = {
    description = "Third-party Bilibili client developed in Flutter";
    homepage = "https://github.com/bggRGjQaUbCoE/PiliPlus";
    license = lib.licenses.gpl3Plus;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "piliplus";
  };
}
