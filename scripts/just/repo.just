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
  @nix flake check --no-update-lock-file --no-write-lock-file

# 逐行读取 packages/update.list，用 nix-update 检查并更新非 flake input 形态的远程源包；
# 节点顺序、重试与失败汇总见 scripts/sh/update.sh。
pkg-update:
  scripts/sh/update.sh pkg

update *inputs:
  scripts/sh/update.sh all {{inputs}}
