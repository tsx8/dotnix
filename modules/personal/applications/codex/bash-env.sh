# shellcheck shell=bash
_codex_load_direnv() {
  local status rc exports
  status="$(BASH_ENV='' @direnv@ status --json)" || return
  # direnv represents an authorized rc with allowed = 0.
  rc="$(@jq@ -er '
    .state.foundRC |
    if . == null then ""
    elif .allowed == 0 then .path
    else error("project environment is not authorized: " + .path)
    end
  ' <<< "$status")" || return
  if [[ -n $rc ]]; then
    BASH_ENV='' "$BASH" -n -- "$rc" || return
  fi
  exports="$(BASH_ENV='' @direnv@ export bash)" || return
  eval "$exports"
}
_codex_load_direnv || exit "$?"
unset -f _codex_load_direnv
