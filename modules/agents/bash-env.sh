# shellcheck shell=bash
_bash_load_direnv() {
  local status rc exports
  # direnv may start Bash itself; clearing BASH_ENV prevents recursive loading.
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
  # 空 DIRENV_LOG_FORMAT 抑制状态日志，加载错误不受影响（logError 不走该格式）；
  # 仅在 ConfDir 存在配置文件时被读取，由同模块部署的 /etc/direnv/config.toml 满足。
  exports="$(BASH_ENV='' DIRENV_LOG_FORMAT='' @direnv@ export bash)" || return
  eval "$exports"
}
_bash_load_direnv || exit "$?"
unset -f _bash_load_direnv
