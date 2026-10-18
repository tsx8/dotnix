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
  version = "2.1.6.2";

  src = fetchFromGitHub {
    owner = "bggRGjQaUbCoE";
    repo = "PiliPlus";
    tag = version;
    hash = "sha256-PrXUQdEZUMNkTzaS7gGgQTrRWcF+4a0tFSpWqLwaubI=";
  };

  # Kept in sync with upstream CI (the common set in lib/scripts/patch.ps1 plus its Linux branch):
  # patch the Flutter framework and material_ui before building (expose internal APIs, fix selection
  # behavior, etc.), otherwise types the app source references, such as StandardBottomSheet and
  # TabBarState, do not exist. The patch files roll with the source tag and need no separately maintained version.
  frameworkPatches = map (name: "${src}/lib/scripts/${name}") [
    "double_tap_gesture.patch"
    "draggable_scrollable_sheet.patch"
    "editable_text.patch"
    "fab.patch"
    "image_anim.patch"
    "layout_builder.patch"
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

    # media_kit_libs_video transitively depends on pub.dev's media_kit_libs_linux, whose CMake downloads
    # mimalloc online by default; switch to the shared library from nixpkgs.
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

  # cnativeapi's build hook invokes pkg-config directly for gtk+-3.0/x11/xi, and the Flutter build's child
  # process environment does not carry the PKG_CONFIG_PATH accumulated by stdenv; preBuild pins the full
  # search path into a wrapper placed ahead on PATH.
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
