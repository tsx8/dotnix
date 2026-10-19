{
  fetchurl,
  lib,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "pi-ask-user";
  version = "0.3.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/@lwlee2608/pi-ask-user/-/pi-ask-user-${finalAttrs.version}.tgz";
    hash = "sha256-/XKLrI/yPpiLQUEmHcrwRio9YmJ2PMCPXGmgdT2sYgg=";
  };

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    dest="$out/share/pi/packages/ask-user"
    install -d "$dest"
    cp -R . "$dest"/

    runHook postInstall
  '';

  meta = {
    description = "Structured terminal questionnaire for Pi";
    homepage = "https://github.com/lwlee2608/pi-extensions";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
})
