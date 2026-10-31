set working-directory := "../.."

fmt: _source-ready
  nix fmt

lint: _source-ready
  @scripts/sh/module-layout.sh
  @just repo _tracked-files '*.nix' | xargs -0 -r nix fmt -- --no-cache --fail-on-change
  @just repo _tracked-files '*.nix' | xargs -0 -r nix run .#nixf-diagnose --
  @statix check --config modules/maintenance/development/statix.toml
  @just repo _tracked-files '*.sh' | xargs -0 -r shellcheck
  @git diff --check HEAD

test: _source-ready
  @nix flake check --no-update-lock-file --no-write-lock-file

# Read packages/update.list line by line and use nix-update to check and update remote-source packages
# not shaped as flake inputs; node order, retries, and failure summary live in scripts/sh/update.sh.
pkg-update:
  scripts/sh/update.sh pkg

update *inputs:
  scripts/sh/update.sh all {{inputs}}

# The Git index still lists worktree-deleted paths until their deletions are staged; broken symlinks are still handed to the checker to report.
_tracked-files PATTERN:
  @git ls-files -z -- {{quote(PATTERN)}} | \
    xargs -0 -r sh -c 'for path; do if [ -e "$path" ] || [ -L "$path" ]; then printf "%s\0" "$path"; fi; done' sh

_source-ready:
  @untracked="$(git ls-files --others --exclude-standard)" || exit "$?"; \
    if [ -n "$untracked" ]; then \
      printf 'Untracked files must be explicitly tracked, moved out, or ignored before checking:\n%s\n' "$untracked" >&2; \
      exit 1; \
    fi
