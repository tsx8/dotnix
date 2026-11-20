set working-directory := "../.."

fmt: _source-ready
  nix fmt

lint: _source-ready
  @scripts/sh/module-layout.sh
  @check-comments
  @just repo _tracked-files '*.nix' | xargs -0 -r nix fmt -- --no-cache --fail-on-change
  @just repo _tracked-files '*.nix' | xargs -0 -r nix run .#nixf-diagnose --
  @statix check --config modules/maintenance/development/statix.toml
  @just repo _tracked-files '*.sh' | xargs -0 -r shellcheck
  @git diff --check HEAD
  @scripts/sh/overlay-advisory.sh

test: _source-ready
  @nix flake check --no-update-lock-file --no-write-lock-file

[doc('Update the non-flake packages registered in packages/update.list.')]
pkg-update:
  scripts/sh/update.sh pkg

update *inputs:
  scripts/sh/update.sh all {{inputs}}

# Check broken symlinks, but not unstaged deletions still present in the index.
_tracked-files PATTERN:
  @git ls-files -z -- {{quote(PATTERN)}} | \
    xargs -0 -r sh -c 'for path; do if [ -e "$path" ] || [ -L "$path" ]; then printf "%s\0" "$path"; fi; done' sh

_source-ready:
  @untracked="$(git ls-files --others --exclude-standard)" || exit "$?"; \
    if [ -n "$untracked" ]; then \
      printf 'Untracked files must be explicitly tracked, moved out, or ignored before checking:\n%s\n' "$untracked" >&2; \
      exit 1; \
    fi
