{ lib, t3code }:
let
  release = import ./release.nix;
  inherit (release) version;
  appName = "T3 Code (Nightly)";
  package = t3code.unwrapped.override (previous: {
    fetchFromGitHub =
      args:
      previous.fetchFromGitHub (
        if args.owner == "pingdotgg" && args.repo == "t3code" then
          args
          // {
            tag = "v${version}";
            hash = release.sourceHash;
          }
        else
          args
      );
    fetchPnpmDeps =
      args:
      previous.fetchPnpmDeps (
        args
        // {
          inherit version;
          hash = release.pnpmHash;
        }
      );
    rustPlatform = previous.rustPlatform // {
      buildRustPackage =
        args:
        previous.rustPlatform.buildRustPackage (
          args
          // {
            inherit version;
            cargoHash = release.cargoHashes.${args.pname};
          }
        );
    };
    makeDesktopItem = args: previous.makeDesktopItem (args // { desktopName = appName; });
  });
  replace =
    from: to: body:
    if lib.hasInfix from body then
      builtins.replaceStrings [ from ] [ to ] body
    else
      throw "llm-agents T3 Code recipe changed; missing ${from}";
  unwrapped = package.overrideAttrs (old: {
    inherit version;
    inherit (old) src;
    preBuild =
      replace "node scripts/update-release-package-versions.ts ${t3code.version}"
        "node scripts/update-release-package-versions.ts ${version}"
        old.preBuild;
    postBuild = (old.postBuild or "") + ''
      node scripts/apply-web-brand-assets.ts nightly apps/server/dist/client
    '';
    installPhase = lib.pipe old.installPhase [
      (replace "assets/prod/black-universal-1024.png" "assets/nightly/nightly-universal-1024.png")
      (replace "mkdir -p \"$desktop/share/icons/hicolor/scalable/apps\"\n" "")
      (replace "install -Dm444 assets/prod/logo.svg \"$desktop/share/icons/hicolor/scalable/apps/t3code.svg\"" "install -Dm444 assets/nightly/nightly-web-icon-512x512.png \"$desktop/share/icons/hicolor/512x512/apps/t3code.png\"")
    ];
    passthru = old.passthru // {
      inherit appName;
    };
    meta = old.meta // {
      platforms = [ "x86_64-linux" ];
      changelog = "https://github.com/pingdotgg/t3code/releases/tag/v${version}";
    };
  });
in
assert lib.assertMsg (
  package.src.tag or null == "v${version}" && package.src.outputHash == release.sourceHash
) "T3 Code source no longer follows the pinned nightly tag and hash";
t3code.override {
  t3code-unwrapped = unwrapped;
  providerPackages = [ ];
}
