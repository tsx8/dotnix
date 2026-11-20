#!/usr/bin/env bash
# Clients in the same session share their current window; attach only to detached sessions.
set -uo pipefail

GC_AGE=${TMUX_AUTO_GC_AGE:-86400}
SHELLS='fish|bash|zsh|sh|dash'
FORMAT=$'#{session_attached}\t#{session_activity}\t#{session_created}\t#{session_name}'

restore_target() {
  tmux list-sessions -F "$FORMAT" 2>/dev/null |
    awk -F'\t' '$1 == 0' |
    sort -t$'\t' -k2,2nr -k3,3nr |
    head -n 1 |
    cut -f4-
}

gc() {
  local now target attached activity name panes count
  now=$(date +%s)
  target=$(restore_target)
  while IFS=$'\t' read -r attached activity _ name; do
    [[ -n $name ]] || continue
    [[ $attached == 0 ]] || continue
    [[ $name != "$target" ]] || continue
    ((now - activity > GC_AGE)) || continue
    # Preserve multi-pane layouts even when every pane is running a shell.
    panes=$(tmux list-panes -s -t "$name" -F '#{pane_current_command}' 2>/dev/null)
    count=$(printf '%s\n' "$panes" | grep -c . || true)
    [[ $count == 1 ]] || continue
    [[ $panes =~ ^($SHELLS)$ ]] || continue
    tmux kill-session -t "$name" 2>/dev/null
  done < <(tmux list-sessions -F "$FORMAT" 2>/dev/null)
}

new_session_name() {
  local i
  for i in $(seq 1 99); do
    tmux has-session -t "t$i" 2>/dev/null || {
      printf 't%s' "$i"
      return
    }
  done
  printf 't%s' "$$"
}

fallback() {
  printf 'tmux 不可用，使用普通 shell。\n' >&2
  TMUX_AUTO_SKIP=1 exec "${SHELL:-fish}"
}

attach_session() {
  if tmux attach -t "$1"; then
    exit 0
  fi
  printf '无法连接 tmux 会话 %s。\n' "$1" >&2
  fallback
}

main() {
  command -v tmux >/dev/null 2>&1 || fallback
  if [[ ${1:-} == gc ]]; then
    gc
    return 0
  fi
  gc
  local target name
  target=$(restore_target)
  if [[ -n $target ]]; then
    attach_session "$target"
    return
  fi
  name=$(new_session_name)
  if tmux new-session -d -s "$name" -c "$PWD"; then
    attach_session "$name"
  else
    fallback
  fi
}

main "$@"
