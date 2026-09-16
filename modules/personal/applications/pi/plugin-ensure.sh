#!/usr/bin/env bash
# 以声明清单维护 pi 插件市场与已装插件，替代 /plugins marketplace add 的手工步骤。
# 写入格式复刻 pi-plugins dist/host.js 的 addMarketplace/installPlugin 本地源路径
# （source.json、checkout、.pi-plugin.json 回执、目录跳过表）；升级 pi-plugins 时
# 须对照该源码核对本脚本。store 路径随输入变化即整体重建并重装；重装保留
# .disabled/.auto-update 等宿主权威标记，用户自装的其他插件与市场不受影响。
set -euo pipefail

usage() {
  echo "usage: plugin-ensure.sh AGENT_DIR NAME=SOURCE... [-- MARKET:PLUGIN...]" >&2
  exit 2
}

(( $# >= 1 )) || usage
agent_dir=$1
shift

declare -A sources=()
while (( $# > 0 )) && [[ $1 != -- ]]; do
  name=${1%%=*}
  path=${1#*=}
  [[ $name != "" && $path != "" && $name != */* ]] || usage
  sources[$name]=$path
  shift
done
[[ ${1:-} == -- ]] && shift

markets_root=$agent_dir/plugin-host/marketplaces
plugins_root=$agent_dir/plugin-host/plugins
data_root=$agent_dir/plugin-host/data
mkdir -p "$markets_root" "$plugins_root" "$data_root"

# readMarketplaceCatalog 的读取顺序。
catalog_paths=(
  ".agents/plugins/marketplace.json"
  ".claude-plugin/marketplace.json"
)

find_catalog_file() {
  local candidate
  for candidate in "${catalog_paths[@]}"; do
    if [[ -f $1/$candidate ]]; then
      printf '%s\n' "$1/$candidate"
      return 0
    fi
  done
  return 1
}

find_plugin_entry() {
  local checkout=$1 plugin=$2 candidate
  for candidate in "${catalog_paths[@]}"; do
    if [[ -f $checkout/$candidate ]] &&
      jq -e --arg name "$plugin" 'any(.plugins[]?; .name == $name)' "$checkout/$candidate" >/dev/null; then
      jq -c --arg name "$plugin" '.plugins[]? | select(.name == $name)' "$checkout/$candidate"
      return 0
    fi
  done
  return 1
}

# readPluginMetadata：按文件顺序合并，version/description 各取首个非空字符串。
bundle_metadata() {
  local bundle=$1
  local -a files=()
  local candidate
  for candidate in ".claude-plugin/plugin.json" ".codex-plugin/plugin.json" "plugin.json"; do
    [[ -f $bundle/$candidate ]] && files+=("$bundle/$candidate")
  done
  ((${#files[@]} > 0)) || return 0
  jq -s '
    reduce .[] as $m ({version: null, description: null};
      {
        version: (if (.version | type) == "string" then .version
                  elif ($m.version? | type) == "string" and ($m.version | length) > 0 then $m.version
                  else null end),
        description: (if (.description | type) == "string" then .description
                      elif ($m.description? | type) == "string" and ($m.description | length) > 0 then $m.description
                      else null end)
      })
  ' "${files[@]}"
}

replace_dir() {
  local target=$1 stage=$2 old
  if [[ -e $target ]]; then
    old=$(mktemp -d "${target%/*}/.replace-XXXXXX")
    rmdir "$old"
    mv -T "$target" "$old"
    mv -T "$stage" "$target"
    rm -rf "$old"
  else
    mv -T "$stage" "$target"
  fi
}

for name in "${!sources[@]}"; do
  source_path=${sources[$name]}
  market_root=$markets_root/$name
  rebuild=0
  if [[ ! -d $market_root ]]; then
    rebuild=1
  else
    current=$(jq -r 'select(.kind == "local") | .value // empty' "$market_root/source.json" 2>/dev/null || true)
    if [[ -z $current || $current != "$source_path" ]]; then
      rebuild=1
    fi
  fi
  if ((rebuild)); then
    catalog=$(find_catalog_file "$source_path") || {
      echo "pi marketplace '$name': no catalog under $source_path" >&2
      exit 1
    }
    actual=$(jq -r '.name // empty' "$catalog")
    [[ $actual == "$name" ]] || {
      echo "pi marketplace '$name': catalog name is '$actual'" >&2
      exit 1
    }
    stage=$(mktemp -d "$markets_root/.marketplace-XXXXXX")
    mkdir "$stage/checkout"
    cp -a "$source_path/." "$stage/checkout/"
    chmod -R u+w "$stage/checkout"
    jq -n --arg value "$source_path" '{kind: "local", value: $value}' > "$stage/source.json"
    replace_dir "$market_root" "$stage"
  fi

  for pair in "$@"; do
    market=${pair%%:*}
    [[ $market == "$name" ]] || continue
    plugin=${pair#*:}
    [[ $plugin != "" && $plugin != */* ]] || usage
    plugin_root=$plugins_root/$market/$plugin
    if [[ -d $plugin_root ]] && ((rebuild == 0)); then
      continue
    fi
    entry=$(find_plugin_entry "$market_root/checkout" "$plugin") || {
      echo "pi plugin '$plugin': no catalog entry in marketplace '$market'" >&2
      exit 1
    }
    # parsePluginSource 规范化：只支持本地源条目，回执存 {kind:"local", path}。
    source_json=$(jq -c '
      if (.source | type) == "string" then {kind: "local", path: .source}
      elif .source.source? == "local" then {kind: "local", path: .source.path}
      else error("unsupported plugin source; only local entries are declaratively installable")
      end
    ' <<<"$entry") || {
      echo "pi plugin '$plugin': unsupported source type" >&2
      exit 1
    }
    rel=$(jq -r '.path // empty' <<<"$source_json")
    [[ -n $rel && $rel != /* && $rel != *..* ]] || {
      echo "pi plugin '$plugin': unsafe source path '$rel'" >&2
      exit 1
    }
    bundle=$market_root/checkout/$rel
    [[ -d $bundle ]] || {
      echo "pi plugin '$plugin': bundle missing at '$rel'" >&2
      exit 1
    }
    mkdir -p "$plugins_root/$market"
    stage=$(mktemp -d "$plugins_root/$market/.${plugin}-XXXXXX")
    cp -a "$bundle/." "$stage/"
    rm -rf "$stage/.git" "$stage/.pi-plugin.json" "$stage/.disabled" "$stage/.auto-update"
    meta=$(bundle_metadata "$stage")
    description=$(jq -r '.description // empty' <<<"$entry")
    [[ -n $description ]] || description=$(jq -r '.description // empty' <<<"$meta")
    version=$(jq -r '.version // empty' <<<"$meta")
    [[ -n $version ]] || version=$(jq -r '.version // empty' <<<"$entry")
    jq -n \
      --arg marketplace "$market" --arg plugin "$plugin" \
      --arg description "$description" --arg version "$version" \
      --argjson source "$source_json" '
      {marketplace: $marketplace, plugin: $plugin}
      + (if ($description | length) > 0 then {description: $description} else {} end)
      + (if ($version | length) > 0 then {version: $version} else {} end)
      + {source: $source}
    ' > "$stage/.pi-plugin.json"
    for marker in .disabled .auto-update; do
      if [[ -f $plugin_root/$marker ]]; then
        : > "$stage/$marker"
      fi
    done
    replace_dir "$plugin_root" "$stage"
    mkdir -p "$data_root/$market/$plugin"
  done
done
