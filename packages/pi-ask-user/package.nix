{
  fetchurl,
  lib,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "pi-ask-user";
  version = "0.4.1";

  src = fetchurl {
    url = "https://registry.npmjs.org/@lwlee2608/pi-ask-user/-/pi-ask-user-${finalAttrs.version}.tgz";
    hash = "sha256-WVNH8fz19HDXV7gIXsBj2yxThBTm0cluS0KyzO0fidQ=";
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
