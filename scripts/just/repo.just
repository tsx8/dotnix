set working-directory := "../.."

fmt:
  nix fmt

lint:
  @git ls-files -z -- '*.nix' | xargs -0 -r nix fmt -- --no-cache --fail-on-change
  @git ls-files -z -- '*.nix' | xargs -0 -r nix run .#nixf-diagnose --
  @statix check --config modules/maintenance/development/statix.toml
  @git ls-files -z -- '*.sh' | xargs -0 -r shellcheck
  @git diff --check HEAD

test:
  nix flake check --no-update-lock-file --no-write-lock-file

# 逐行读取 packages/update.list，用 nix-update 检查并更新非 flake input 形态的远程源包。
# pi-plugins 的依赖闭包 lock 须跟随刚更新的版本重生成。
pkg-update:
  #!/usr/bin/env bash
  set -euo pipefail
  while read -r name extra; do
    [[ -z "$name" || $name == \#* ]] && continue
    # shellcheck disable=SC2086
    nix-update "$name" --flake --format $extra
  done < packages/update.list
  scripts/sh/sync-pi-plugins-lock.sh

update *inputs:
  @bash -euo pipefail -c 'if (($# == 0)); then nix flake update; else nix flake update "$@"; fi; just repo pkg-update; scripts/sh/sync-models.sh; just repo lint; just repo test' update {{inputs}}
