# Local port of nixpkgs PR #553134 (deepseek-harness: init at 0.1.0-rc.6,
# upstream PR still unmerged at that version; this port tracks 0.1.0-rc.7).
# Keep in sync with the upstream expression; delete this directory and use
# pkgs.deepseek-harness once it lands in the tracked nixpkgs revision.
# meta.maintainers is omitted: the locked nixpkgs predates that PR's maintainer.
{
  lib,
  stdenv,
  bash,
  bubblewrap,
  buildNpmPackage,
  fetchurl,
  makeWrapper,
  nodejs_24,
  pnpm_11,
  versionCheckHook,
}:

let
  # node-pty prebuild directories use Node's process.arch naming.
  nodePtyArch =
    {
      x86_64 = "x64";
      aarch64 = "arm64";
    }
    .${stdenv.hostPlatform.uname.processor} or stdenv.hostPlatform.uname.processor;

  runtimePath = lib.makeBinPath (
    [
      bash
      pnpm_11
    ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [ bubblewrap ]
  );
in
buildNpmPackage (finalAttrs: {
  pname = "deepseek-harness";
  version = "0.1.0-rc.7";

  __structuredAttrs = true;

  src = fetchurl {
    url = "https://registry.npmjs.org/@deepseek-ai/dsh/-/dsh-${finalAttrs.version}.tgz";
    hash = "sha256-L48Ldj1hGsU296lBHuQ8CvwGfBuHMsMQLATb45i8rMU=";
  };

  nodejs = nodejs_24;

  npmDepsHash = "sha256-Y+Y1f1V7+1sXkezKAeqEOW8GZeScERo/+gWXU4Qjqho=";

  # The npm tarball retains development-only workspace packages, which npm
  # would otherwise install because the tarball is the derivation's root.
  patches = [
    ./remove-dev-dependencies.patch
    ./use-nix-bash.patch
  ];

  postPatch = ''
    cp ${./package-lock.json} package-lock.json

    # NixOS does not provide the terminal backend's default /bin/bash.
    substituteInPlace config/agent-presets/minimal/agent.cordis.yml \
      --replace-fail "@bash@" "${lib.getExe bash}"
  '';

  npmInstallFlags = [ "--omit=dev" ];
  dontNpmBuild = true;

  # Rewriting the bundled libvips RPATH makes sharp crash during module load.
  # Its upstream RPATH is complete, and Node already supplies libstdc++.
  dontPatchELF = true;

  nativeBuildInputs = [ makeWrapper ];

  # node-pty 1.2 ships per-platform prebuilds and loads the current
  # platform's pty.node from them at runtime (its install script skips
  # node-gyp when a matching prebuild exists), so keep only that directory.
  postInstall = ''
    # HMR needs Node's internal ESM loader, which its native fallback cannot
    # resolve with Node 24.
    rm $out/bin/dsh
    makeWrapper ${nodejs_24}/bin/node $out/bin/dsh \
      --add-flags "--expose-internals" \
      --add-flags "$out/lib/node_modules/@deepseek-ai/dsh/lib/bin.js" \
      --prefix PATH : ${runtimePath}
  ''
  + lib.optionalString stdenv.hostPlatform.isGnu ''
    find $out/lib/node_modules/@deepseek-ai/dsh/node_modules/node-pty/prebuilds \
      -mindepth 1 -maxdepth 1 -type d ! -name "linux-${nodePtyArch}" -exec rm -r {} +
    find $out/lib/node_modules/@deepseek-ai/dsh/node_modules/@koromix \
      -type d -name 'musl_*' -prune -exec rm -r {} +
    find $out/lib/node_modules/@deepseek-ai/dsh/node_modules/@img \
      -mindepth 1 -maxdepth 1 -type d -name '*linuxmusl*' -exec rm -r {} +
  ''
  + lib.optionalString stdenv.hostPlatform.isDarwin ''
    find $out/lib/node_modules/@deepseek-ai/dsh/node_modules/node-pty/prebuilds \
      -mindepth 1 -maxdepth 1 -type d ! -name "darwin-${nodePtyArch}" -exec rm -r {} +
    # npm does not reliably preserve the helper's executable bit.
    find $out/lib/node_modules/@deepseek-ai/dsh/node_modules/node-pty \
      -type f -name spawn-helper -exec chmod +x {} +
  ''
  + lib.optionalString stdenv.hostPlatform.isMusl ''
    find $out/lib/node_modules/@deepseek-ai/dsh/node_modules/@koromix \
      -type d -name 'linux_*' -prune -exec rm -r {} +
    find $out/lib/node_modules/@deepseek-ai/dsh/node_modules/@img \
      -mindepth 1 -maxdepth 1 -type d -name '*linux-*' -exec rm -r {} +
  '';

  # node-pty's prebuilds are glibc-only; on musl its own build-from-source
  # switch makes prebuild.js drop the prebuilds and rebuild with node-gyp.
  env = lib.optionalAttrs stdenv.hostPlatform.isMusl {
    npm_config_build_from_source = "true";
  };

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;

  postVersionCheck = ''
    export DSH_HOME="$TMPDIR/dsh-home"
    export DSH_AGENTS_HOME="$TMPDIR/dsh-agents"
    export DSH_TELEMETRY_DISABLED=1

    $out/bin/dsh web --dump-default-config >/dev/null
    $out/bin/dsh web --help >/dev/null
    $out/bin/dsh plugin --profile nix-smoke --version | grep -Fx ${pnpm_11.version}

    webLog="$TMPDIR/dsh-web.log"
    $out/bin/dsh web --port 0 >"$webLog" 2>&1 &
    webPid=$!

    stopWeb() {
      kill "$webPid" 2>/dev/null || true
      wait "$webPid" 2>/dev/null || true
    }
    trap stopWeb EXIT

    webUrl=
    attempt=0
    while [ "$attempt" -lt 200 ]; do
      webUrl="$(sed -n 's|^dsh web: \(http://127\.0\.0\.1:[0-9][0-9]*\)$|\1|p' "$webLog" | head -n 1)"
      if [ -n "$webUrl" ]; then
        break
      fi
      if ! kill -0 "$webPid" 2>/dev/null; then
        cat "$webLog" >&2
        exit 1
      fi
      sleep 0.1
      attempt=$((attempt + 1))
    done

    if [ -z "$webUrl" ]; then
      cat "$webLog" >&2
      echo "dsh web did not start within 20 seconds" >&2
      exit 1
    fi

    sleep 1
    if ! kill -0 "$webPid" 2>/dev/null; then
      cat "$webLog" >&2
      exit 1
    fi

    stopWeb
    trap - EXIT

    (
      cd $out/lib/node_modules/@deepseek-ai/dsh
      EXPECTED_PTY_SHELL=${lib.getExe bash} ${nodejs_24}/bin/node -e '
        const { readFileSync } = require("node:fs");
        const pty = require("node-pty");
        const preset = readFileSync("config/agent-presets/minimal/agent.cordis.yml", "utf8");
        const shell = /^\s+shellPath:\s+(.+)$/mu.exec(preset)?.[1];
        if (shell !== process.env.EXPECTED_PTY_SHELL) {
          console.error({ shell, expected: process.env.EXPECTED_PTY_SHELL });
          process.exit(1);
        }
        const terminal = pty.spawn(shell, ["-c", "printf nix-pty-smoke"], {
          name: "xterm",
          cols: 80,
          rows: 24,
          cwd: process.cwd(),
          env: process.env,
        });
        let output = "";
        const timeout = setTimeout(() => {
          terminal.kill();
          console.error("PTY smoke test timed out");
          process.exit(1);
        }, 5000);
        terminal.onData((data) => { output += data; });
        terminal.onExit(({ exitCode }) => {
          clearTimeout(timeout);
          if (exitCode !== 0 || !output.includes("nix-pty-smoke")) {
            console.error({ exitCode, output });
            process.exitCode = 1;
          }
        });
      '
    )
  '';

  meta = {
    description = "Plugin-based agent harness developed by DeepSeek AI";
    homepage = "https://github.com/deepseek-ai/deepseek-harness";
    downloadPage = "https://www.npmjs.com/package/@deepseek-ai/dsh";
    license = lib.licenses.mit;
    mainProgram = "dsh";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
