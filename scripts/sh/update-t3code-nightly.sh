#!/usr/bin/env bash
set -euo pipefail

# Update the T3 Code nightly pin as a transaction. nix-update runs only in a writable copy of the
# current tree; the working tree's release file changes only after that candidate builds and reports
# the pinned version from its own binaries and service. A failed candidate leaves the old pin intact.

# The candidate carries .envrc but no direnv authorization; an inherited hook would fail in every
# child process that starts there and contaminate the JSON and hash output. A caller's Git environment
# would also redirect the temporary baseline away from $git_dir.
unset BASH_ENV DIRENV_DIR DIRENV_FILE DIRENV_DIFF DIRENV_WATCHES GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd -- "$repo_root"

attr=t3code-nightly
release_rel=packages/t3code-nightly/release.nix
adapter_rel=packages/t3code-nightly/package.nix
lock_dir="${TMPDIR:-/tmp}/dotnix-t3code-nightly.lock"
lock_owned=0
tmp=
server_pid=

cleanup() {
  if [[ -n "$server_pid" ]]; then
    kill -KILL -- "-$server_pid" 2>/dev/null || kill -KILL "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  rm -rf -- "$lock_dir.$$"
  if ((lock_owned)); then
    rm -rf -- "$lock_dir"
  fi
  [[ -z "$tmp" ]] || rm -rf -- "$tmp"
}
trap cleanup EXIT

die() {
  printf 't3code-nightly: %s\n' "$*" >&2
  exit 1
}

# One updater per tree; the package edit and the promotion must not interleave with another run.
# A PID inside the lock directory lets the next run clear a claim whose owner was killed, rather than
# leaving the package blocked until someone removes a stale file.
claim="$lock_dir.$$"
mkdir -p -- "$claim" || die "cannot create $claim"
printf '%s\n' "$$" >"$claim/pid" || die "cannot write $claim/pid"
if ! mv -T -- "$claim" "$lock_dir" 2>/dev/null; then
  holder=$(cat -- "$lock_dir/pid" 2>/dev/null || true)
  if [[ -n "$holder" ]] && kill -0 "$holder" 2>/dev/null; then
    die "another update (pid $holder) holds $lock_dir"
  fi
  rm -rf -- "$lock_dir"
  mv -T -- "$claim" "$lock_dir" 2>/dev/null || die "cannot claim $lock_dir"
fi
lock_owned=1

for path in "$release_rel" "$adapter_rel"; do
  [[ -f "$path" ]] || die "missing $path"
done
git ls-files --error-unmatch -- "$release_rel" "$adapter_rel" >/dev/null 2>&1 ||
  die "$release_rel and $adapter_rel must be tracked by Git before updating"

before_release=$(sha256sum "$release_rel" | cut -d' ' -f1)
before_adapter=$(sha256sum "$adapter_rel" | cut -d' ' -f1)
before_lock=$(sha256sum flake.lock | cut -d' ' -f1)
old_version=$(nix eval --raw --no-write-lock-file ".#$attr.version")
old_src=$(nix eval --raw --no-write-lock-file ".#$attr.src.outputHash")

snapshot=$(nix flake prefetch --no-write-lock-file --json . | jq -r .storePath)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/dotnix-t3code-nightly.XXXXXX")
candidate="$tmp/candidate"
mkdir -p "$candidate"
cp -a "$snapshot/." "$candidate/"
chmod -R u+w -- "$candidate"

# Keep nix-update's Git diff baseline outside the tree: a .git directory would turn the candidate into
# a Git flake and hand nix-build lazy store paths that do not exist after each edit.
git_dir="$tmp/git"
git init -q --bare "$git_dir"
GIT_DIR="$git_dir" GIT_WORK_TREE="$candidate" git add -A
GIT_DIR="$git_dir" GIT_WORK_TREE="$candidate" \
  git -c user.name=dotnix-update -c user.email=dotnix-update@invalid commit -qm baseline

(
  cd -- "$candidate"
  export GIT_DIR="$git_dir" GIT_WORK_TREE="$candidate"
  nix-update "$attr" --flake --format \
    --use-github-releases --github-releases-limit 100 \
    --version=unstable \
    --version-regex '^v([0-9]+\.[0-9]+\.[0-9]+-nightly\.[0-9]{8}\.[0-9]+)$' \
    --override-filename "$release_rel" \
    --subpackage resourceMonitor --subpackage hyprlandSnapShot --subpackage kdeSnapShot
)

new_version=$(cd -- "$candidate" && nix eval --raw --no-write-lock-file ".#$attr.version")
if [[ "$new_version" == "$old_version" ]]; then
  printf 'Not updating version, already %s\n' "$old_version"
  exit 0
fi
[[ "$(printf '%s\n%s\n' "$old_version" "$new_version" | sort -V | tail -n 1)" == "$new_version" ]] ||
  die "candidate $new_version is older than the pinned $old_version"

new_src=$(cd -- "$candidate" && nix eval --raw --no-write-lock-file ".#$attr.src.outputHash")
[[ "$new_src" != "$old_src" ]] ||
  die "candidate $new_version keeps the old source hash; refusing to relabel it"

build_json=$(cd -- "$candidate" && nix build --no-link --no-write-lock-file --json ".#$attr^out,desktop")
out=$(jq -r '.[0].outputs.out' <<<"$build_json")
desktop=$(jq -r '.[0].outputs.desktop' <<<"$build_json")
[[ -x "$out/bin/t3" && -x "$desktop/bin/t3code-desktop" ]] ||
  die "candidate build is missing the CLI or desktop executable"

smoke_home="$tmp/home"
smoke_t3_home="$tmp/t3home"
mkdir -p "$smoke_home" "$smoke_t3_home"
# A temporary HOME would make the inherited BASH_ENV direnv hook fail before the app starts.
smoke_env=(
  env -u BASH_ENV -u DIRENV_DIR -u DIRENV_FILE -u DIRENV_DIFF -u DIRENV_WATCHES
  HOME="$smoke_home" T3CODE_HOME="$smoke_t3_home"
)
run_version=$(timeout 30 "${smoke_env[@]}" "$out/bin/t3" --version) || die "CLI --version did not finish"
run_version=${run_version##* }
run_version=${run_version#v}
[[ "$run_version" == "$new_version" ]] ||
  die "CLI reports '$run_version', expected '$new_version'"
desktop_version=$(timeout 30 "${smoke_env[@]}" "$desktop/bin/t3code-desktop" --version) ||
  die "desktop --version did not finish"
desktop_version=$(printf '%s' "$desktop_version" | tr -d '[:space:]')
[[ "$desktop_version" == "$new_version" ]] ||
  die "desktop reports '$desktop_version', expected '$new_version'"

port=$((20000 + RANDOM % 20000))
setsid "${smoke_env[@]}" "$out/bin/t3" serve --host 127.0.0.1 --port "$port" --no-browser >"$tmp/serve.log" 2>&1 &
server_pid=$!

environment=
for _ in {1..60}; do
  if ! kill -0 "$server_pid" 2>/dev/null; then
    cat "$tmp/serve.log" >&2 || true
    die "candidate service exited before serving"
  fi
  if environment=$(curl -fsS --max-time 1 "http://127.0.0.1:$port/.well-known/t3/environment" 2>/dev/null); then
    break
  fi
  sleep 0.5
done
[[ -n "$environment" ]] || die "candidate service did not answer on port $port"
served_version=$(jq -r '.serverVersion' <<<"$environment")
[[ "$served_version" == "$new_version" ]] ||
  die "service reports '$served_version', expected '$new_version'"

home_html=$(curl -fsS --max-time 5 "http://127.0.0.1:$port/") || die "candidate service served no home page"
asset=$(printf '%s' "$home_html" | grep -oE '"/[^"]+\.js"' | head -n 1 | tr -d '"') || true
[[ -n "$asset" ]] || die "candidate home page references no JavaScript bundle"
asset=${asset#/}
curl -fsS --max-time 5 "http://127.0.0.1:$port/$asset" >/dev/null || die "candidate service did not serve /$asset"

kill -TERM -- "-$server_pid" 2>/dev/null || true
for _ in {1..25}; do
  kill -0 "$server_pid" 2>/dev/null || break
  sleep 0.2
done
kill -KILL -- "-$server_pid" 2>/dev/null || true
wait "$server_pid" 2>/dev/null || true
server_pid=
for _ in {1..20}; do
  if ! (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
    break
  fi
  sleep 0.2
done
(exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null && die "candidate service still listens on port $port"

# Promote only after the candidate and the tree it was based on are both still the ones validated.
[[ "$(sha256sum "$release_rel" | cut -d' ' -f1)" == "$before_release" ]] ||
  die "$release_rel changed during the update; keeping the newer file"
[[ "$(sha256sum "$adapter_rel" | cut -d' ' -f1)" == "$before_adapter" ]] ||
  die "$adapter_rel changed during the update; keeping the newer file"
[[ "$(sha256sum flake.lock | cut -d' ' -f1)" == "$before_lock" ]] ||
  die "flake.lock changed during the update; keeping the newer file"
[[ "$(sha256sum "$candidate/$adapter_rel" | cut -d' ' -f1)" == "$before_adapter" ]] ||
  die "candidate adapter differs from the validated baseline"
[[ "$(sha256sum "$candidate/flake.lock" | cut -d' ' -f1)" == "$before_lock" ]] ||
  die "candidate lock differs from the validated baseline"

promoted=$(mktemp "$repo_root/packages/t3code-nightly/.release.nix.XXXXXX")
cp -- "$candidate/$release_rel" "$promoted"
chmod --reference="$release_rel" -- "$promoted"
mv -f -- "$promoted" "$release_rel"

printf 'Update %s -> %s in %s\n' "$old_version" "$new_version" "$attr"
