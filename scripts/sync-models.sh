#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 0 ]]; then
  echo "usage: $0" >&2
  exit 2
fi

repo_root="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
  pwd
)"
codex_dir="$(realpath -e -- "${CODEX_HOME:-$HOME/.codex}")"
cache_path="$codex_dir/models_cache.json"
catalog="$repo_root/codex/models.json"

if [[ ! -f "$cache_path" ]]; then
  echo "error: $cache_path is missing; start Codex with ChatGPT sign-in first" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
candidate=""
cleanup() {
  rm -rf -- "$tmp_dir"
  if [[ -n "$candidate" ]]; then
    rm -f -- "$candidate"
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

printf '{}\n' > "$tmp_dir/cache.json"
: > "$tmp_dir/config.toml"

# 普通配置可能固定模型目录；仅在子进程中屏蔽它，管理约束和认证仍由 Codex 读取。
isolate=(
  bwrap --die-with-parent
  --ro-bind / /
  --bind "$tmp_dir" "$tmp_dir"
  --bind "$tmp_dir/cache.json" "$(realpath -e -- "$cache_path")"
  --chdir "$tmp_dir"
)
for config_path in /etc/codex/config.toml "$codex_dir/config.toml"; do
  if [[ -e "$config_path" ]]; then
    isolate+=(--ro-bind "$tmp_dir/config.toml" "$(realpath -e -- "$config_path")")
  fi
done

codex_version="$(codex --version)"
codex_version="${codex_version#codex-cli }"
started_at="$(date +%s)"
timeout 120 "${isolate[@]}" -- codex debug models > /dev/null

# CLI 刷新失败也可能返回内置目录；只有本次请求写入的独立缓存可证明刷新成功。
if ! jq -e --arg version "$codex_version" '
  (.client_version == $version) and
  (.fetched_at | type == "string") and
  (.models | type == "array" and length > 0)
' "$tmp_dir/cache.json" > /dev/null; then
  echo "error: Codex did not write a fresh remote model catalog; existing models.json retained" >&2
  exit 1
fi
fetched_at="$(date -d "$(jq -r '.fetched_at' "$tmp_dir/cache.json")" +%s)"
if ((fetched_at < started_at || fetched_at > $(date +%s))); then
  echo "error: remote model catalog timestamp is outside this sync; existing models.json retained" >&2
  exit 1
fi

jq -e '
  ["gpt-6-astra", "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.5"] as $targets |
  if (all(.models[]; (.slug | type == "string" and length > 0)) | not) then
    error("model IDs must be nonempty strings")
  elif ([.models[].slug] | length != (unique | length)) then
    error("duplicate model IDs")
  elif ($targets - [.models[].slug] | length > 0) then
    error("required models missing: " + (($targets - [.models[].slug]) | join(", ")))
  else
    {models: [.models[] |
      if (.slug as $slug | $targets | index($slug)) != null then
        . + {context_window: 1050000, max_context_window: 1050000, auto_compact_token_limit: 386273}
      else . end
    ]}
  end
' "$tmp_dir/cache.json" > "$tmp_dir/updated.json"

catalog_override="$(jq -rn --arg path "$tmp_dir/updated.json" '"model_catalog_json=" + ($path | tojson)')"
timeout 120 "${isolate[@]}" -- codex -c "$catalog_override" debug models > /dev/null

if cmp -s -- "$tmp_dir/updated.json" "$catalog"; then
  echo "Model catalog is unchanged."
  exit 0
fi

candidate="$(mktemp "$repo_root/codex/.models.json.XXXXXX")"
cat "$tmp_dir/updated.json" > "$candidate"
chmod 644 "$candidate"
mv -f -- "$candidate" "$catalog"
candidate=""
echo "Updated $catalog from Codex $codex_version."
