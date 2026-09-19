{
  lib,
  stdenvNoCC,
  makeWrapper,
  applyPatches,
  callPackage,
  toshySrc,
}:
let
  source = applyPatches {
    name = "toshy-source";
    src = toshySrc;
    # The upstream tap path leaks the tap key before applying its keymap.
    patches = [
      ./mapped-tap.patch
      ./command-events.patch
      ./idle-grab.patch
      # 锁定键解锁在松开时才落地，长按的翻转改为脉冲输出才能在超时时刻对称生效；
      # 脉冲后把锁定态镜像到 rime ascii，输入指示才能跟随白/en/A。
      ./lock-hold-pulse.patch
    ];
  };
  runtime = callPackage "${source}/nix/toshy-runtime.nix" { toshySrc = source; };
in
stdenvNoCC.mkDerivation {
  pname = "toshy";
  inherit (runtime.xwaykeyz) version;
  src = toshySrc;
  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/toshy $out/bin $out/share/kwin/scripts
    cp -r toshy_common assets kwin-dbus-service $out/share/toshy/
    cp ${./session.py} $out/share/toshy/session.py
    cp -r kwin-script/kde6/toshy-dbus-notifyactivewindow $out/share/kwin/scripts/
    echo 'notifyActiveWindow(workspace.activeWindow);' >> \
      $out/share/kwin/scripts/toshy-dbus-notifyactivewindow/contents/code/main.js
    cat ${./window-actions.js} >> \
      $out/share/kwin/scripts/toshy-dbus-notifyactivewindow/contents/code/main.js
    makeWrapper ${runtime}/bin/python3 $out/bin/toshy-session \
      --add-flags "$out/share/toshy/session.py" \
      --add-flags "${runtime}/bin/xwaykeyz"
    makeWrapper ${runtime}/bin/python3 $out/bin/toshy-kwin-dbus \
      --add-flags "$out/share/toshy/kwin-dbus-service/toshy_kwin_dbus_service.py"
    runHook postInstall
  '';
  passthru = { inherit runtime; };
  meta = {
    description = "Toshy macOS keyboard mappings and Plasma integration";
    homepage = "https://github.com/RedBearAK/Toshy";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
  };
}
