{
  lib,
  stdenv,
  flutter,
  fetchFromGitHub,
  autoPatchelfHook,
  makeWrapper,
  pkg-config,
  alsa-lib,
  glib-networking,
  libayatana-appindicator,
  mimalloc,
  mpv-unwrapped,
  webkitgtk_4_1,
}:

let
  version = "2.2.1";

  src = fetchFromGitHub {
    owner = "bggRGjQaUbCoE";
    repo = "PiliPlus";
    tag = version;
    hash = "sha256-IhW0TKDf7Pfr7zD65SEF3eXzKwrkvBLX+7XhWEyiyD8=";
  };

  # Match lib/scripts/patch.ps1 from the source tag: the app uses APIs absent from stock Flutter.
  frameworkPatches = map (name: "${src}/lib/scripts/${name}") [
    "double_tap_gesture.patch"
    "draggable_scrollable_sheet.patch"
    "editable_text.patch"
    "fab.patch"
    "image_anim.patch"
    "layout_builder.patch"
    "media_query.patch"
    "modal_barrier.patch"
    "mouse_cursor.patch"
    "navigation_drawer.patch"
    "null_safety_for_selectable_region.patch"
    "popup_menu.patch"
    "refresh_indicator.patch"
    "scaffold.patch"
    "scroll_position.patch"
    "scrollable.patch"
    "scrollable_gesture.patch"
    "selectable_region.patch"
    "sliver.patch"
    "text.patch"
    "text_field.patch"
    "text_painter.patch"
    "text_selection.patch"
  ];

  materialPatches = map (name: "${src}/lib/scripts/material/${name}") [
    "fab.patch"
    "modal_barrier_material.patch"
    "navigation_drawer.patch"
    "popup_menu.patch"
    "refresh_indicator.patch"
    "scaffold.patch"
    "tabs.patch"
    "text_field.patch"
  ];
in
flutter.buildFlutterApplication {
  pname = "piliplus";
  inherit version src;

  pubspecLock = lib.importJSON ./pubspec.lock.json;
  gitHashes = lib.importJSON ./git-hashes.json;

  customSourceBuilders = {
    flutter =
      { src, ... }:
      stdenv.mkDerivation {
        pname = "flutter-framework-piliplus";
        inherit (flutter) version;
        passthru.packageRoot = ".";

        buildCommand = ''
          cp -rL --no-preserve=mode,ownership ${src} ./framework
          chmod -R u+w ./framework
          for p in ${lib.concatStringsSep " " frameworkPatches}; do
            (cd ./framework && patch -p3 < "$p")
          done
          mv ./framework "$out"
        '';
      };

    material_ui =
      {
        src,
        version,
        ...
      }:
      stdenv.mkDerivation {
        pname = "material_ui-piliplus";
        inherit version src;
        passthru.packageRoot = ".";

        patches = materialPatches;

        installPhase = ''
          cp -r . "$out"
        '';
      };

    # Link the packaged mimalloc so CMake does not download it inside the sandbox.
    media_kit_libs_linux =
      {
        version,
        src,
        ...
      }:
      stdenv.mkDerivation {
        pname = "media_kit_libs_linux";
        inherit version src;
        inherit (src) passthru;

        postPatch = ''
          substituteInPlace linux/CMakeLists.txt \
            --replace-fail '"Whether to prefer linking to mimalloc statically" ON' '"Whether to prefer linking to mimalloc statically" OFF'
        '';

        installPhase = ''
          cp -r . "$out"
        '';
      };
  };

  # Flutter's cnativeapi hook drops PKG_CONFIG_PATH in its child environment.
  preBuild = ''
    mkdir -p "$NIX_BUILD_TOP/pkgconfig-bin"
    makeWrapper "$(command -v pkg-config)" "$NIX_BUILD_TOP/pkgconfig-bin/pkg-config" \
      --set-default PKG_CONFIG_PATH "$PKG_CONFIG_PATH"
    export PATH="$NIX_BUILD_TOP/pkgconfig-bin:$PATH"
  '';

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
    pkg-config
  ];

  buildInputs = [
    alsa-lib
    glib-networking
    libayatana-appindicator
    mimalloc
    mpv-unwrapped
    webkitgtk_4_1
  ];

  postInstall = ''
    ln -snf ${mpv-unwrapped}/lib/libmpv.so.2 $out/app/$pname/lib/libmpv.so.2
    install -Dm0644 assets/linux/com.example.piliplus.desktop $out/share/applications/piliplus.desktop
    install -Dm0644 assets/images/logo/logo.png $out/share/icons/hicolor/256x256/apps/piliplus.png
  '';

  meta = {
    description = "Third-party Bilibili client developed in Flutter";
    homepage = "https://github.com/bggRGjQaUbCoE/PiliPlus";
    license = lib.licenses.gpl3Plus;
    platforms = [ "x86_64-linux" ];
    mainProgram = "piliplus";
  };
}
