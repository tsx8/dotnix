set working-directory := "../.."

fmt: _source-ready
  nix fmt

lint: _source-ready
  @just repo _tracked-files '*.nix' | xargs -0 -r nix fmt -- --no-cache --fail-on-change
  @just repo _tracked-files '*.nix' | xargs -0 -r nix run .#nixf-diagnose --
  @statix check --config modules/maintenance/development/statix.toml
  @just repo _tracked-files '*.sh' | xargs -0 -r shellcheck
  @base="$(just repo _baseline)"; git diff --check "$base"

test: _source-ready
  @nix flake check --no-update-lock-file --no-write-lock-file

# 逐行读取 packages/update.list，用 nix-update 检查并更新非 flake input 形态的远程源包；
# 节点顺序、重试与失败汇总见 scripts/sh/update.sh。
pkg-update:
  scripts/sh/update.sh pkg

update *inputs:
  scripts/sh/update.sh all {{inputs}}

# jj 的 Git index 可保留工作树中已删除的路径；损坏的符号链接仍交给检查器报错。
_tracked-files PATTERN:
  @git ls-files -z -- {{quote(PATTERN)}} | \
    xargs -0 -r sh -c 'for path; do if [ -e "$path" ] || [ -L "$path" ]; then printf "%s\0" "$path"; fi; done' sh

_source-ready:
  @untracked="$(git ls-files --others --exclude-standard)" || exit "$?"; \
    if [ -n "$untracked" ]; then \
      printf 'Untracked files must be explicitly tracked, moved out, or ignored before checking:\n%s\n' "$untracked" >&2; \
      exit 1; \
    fi

# jj 把工作副本导出为 Git HEAD，未封存改动的基线取工作副本父提交；纯 Git 引导退回 HEAD。
_baseline:
  @if [ -d .jj ]; then \
    jj --ignore-working-copy log -r @- --no-graph --no-pager -T commit_id; \
  else \
    git rev-parse HEAD; \
  fi
