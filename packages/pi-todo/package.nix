{
  fetchurl,
  lib,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "pi-todo";
  version = "0.1.2";

  src = fetchurl {
    url = "https://registry.npmjs.org/@riverai7z/pi-todo/-/pi-todo-${finalAttrs.version}.tgz";
    hash = "sha256-1p/L8CZhwSLj3XTsau3C47O2c11JyExigNTh4bGeak8=";
  };

  # Task tools are used intermittently; tool_search loads them when needed.
  patches = [ ./deferred-tools.patch ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    dest="$out/share/pi/packages/todo"
    install -d "$dest"
    cp -R . "$dest"/

    # typebox is supplied by the Pi host. The upstream manifest lists it as a dependency, which Pi
    # warns would let an installed copy bypass the extension module mapping; it never installs one here.
    substituteInPlace "$dest/package.json" \
      --replace-fail '"dependencies": {' '"peerDependencies": {'

    runHook postInstall
  '';

  meta = {
    description = "Claude Code-style task list tools for Pi";
    homepage = "https://github.com/riverai7z/pi-todo";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
})
