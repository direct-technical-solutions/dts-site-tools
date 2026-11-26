#!/usr/bin/env bash
# Tests bin/tools-update, run by the tools' self-check every time, on a stand-in copy of the tools'
# repository: the real script and tools/versions.sh, small manifests and lock files, and no
# site.json, as in the real tools' repository. Docker is a stand-in on PATH that records each call
# and writes a lock file into the folder mounted as the container's working folder, as Composer and
# npm would; nothing is downloaded. The command is started from an unrelated folder, without the
# two settings that name a site, so a script that still looked for a site would show.
#
# What is held: it runs without any site; it writes the four lock files; Composer and npm each see
# only a temporary copy, never the repository; npm runs no install scripts and keeps the release
# wait; it refuses an installed copy (no .git) before writing anything; a failing update leaves the
# lock files as they were. Needs bash, cp, grep and mktemp.
set -Euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly HERE
readonly REAL_TOOLS="$HERE/../../.."
readonly LOCK_FILES=(composer.lock tests/e2e/package-lock.json tools/css-lint/package-lock.json tools/js-check/package-lock.json)
readonly OLD_LOCK_TEXT="old lock"
readonly NEW_LOCK_TEXT="lock written by the stand-in"

log() { printf '%s [tools-update tests] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

WORK=""
OUTPUT=""
STATUS=0

# The stand-in docker: records its arguments, one call per line, then writes a lock file into the
# folder mounted at its working folder (-w): composer.lock for "composer update", package-lock.json
# for npm. STANDIN_DOCKER_FAILS=composer makes the Composer call fail, as a broken update would.
write_standin_docker() {
  mkdir -p "$WORK/standin-bin"
  cat >"$WORK/standin-bin/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STANDIN_DOCKER_CALLS"
workdir="" mounted=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  [[ "${args[i]}" == -w ]] && workdir="${args[i + 1]}"
done
for ((i = 0; i < ${#args[@]}; i++)); do
  [[ "${args[i]}" == -v && "${args[i + 1]}" == *":$workdir" ]] && mounted="${args[i + 1]%%:*}"
done
case " $* " in
  *" composer update "*)
    [[ "${STANDIN_DOCKER_FAILS:-}" == composer ]] && exit 1
    printf '%s\n' "$STANDIN_NEW_LOCK_TEXT" >"$mounted/composer.lock" ;;
  *" npm install "*) printf '%s\n' "$STANDIN_NEW_LOCK_TEXT" >"$mounted/package-lock.json" ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$WORK/standin-bin/docker"
}

# A stand-in tools repository: the real script and versions file, a manifest and an old lock file
# for each of the four, a .git marker when the second argument is "repository".
write_tools_folder() {
  local folder="$1" kind="$2" lock_file
  mkdir -p "$folder/bin" "$folder/tools"
  cp "$REAL_TOOLS/bin/tools-update" "$folder/bin/"
  cp "$REAL_TOOLS/tools/versions.sh" "$folder/tools/"
  printf '{}\n' >"$folder/composer.json"
  for lock_file in "${LOCK_FILES[@]}"; do
    mkdir -p "$(dirname "$folder/$lock_file")"
    [[ "$lock_file" == composer.lock ]] || printf '{}\n' >"$(dirname "$folder/$lock_file")/package.json"
    printf '%s\n' "$OLD_LOCK_TEXT" >"$folder/$lock_file"
  done
  [[ "$kind" == repository ]] && mkdir "$folder/.git"
  return 0
}

# Runs the stand-in's bin/tools-update from the unrelated folder, with the stand-in docker first on
# PATH and neither setting that names a site; extra settings (NAME=value ...) are passed on.
run_tools_update() {
  local folder="$1"
  shift
  : >"$WORK/docker-calls"
  STATUS=0
  OUTPUT="$(cd "$WORK/elsewhere" && env -u COMPOSER_RUNTIME_BIN_DIR -u SITE_DIR \
    PATH="$WORK/standin-bin:$PATH" STANDIN_DOCKER_CALLS="$WORK/docker-calls" \
    STANDIN_NEW_LOCK_TEXT="$NEW_LOCK_TEXT" "$@" bash "$folder/bin/tools-update" 2>&1)" || STATUS=$?
}

# Prints the lock files of the folder that do not hold the given text.
lock_files_not_holding() {
  local folder="$1" text="$2" lock_file
  for lock_file in "${LOCK_FILES[@]}"; do
    [[ "$(<"$folder/$lock_file")" == "$text" ]] || printf '%s\n' "$lock_file"
  done
}

pass() { log "ok    $1"; }
fail() { log "FAIL  $1"; return 1; }

runs_without_a_site_and_writes_every_lock() {
  local folder="$WORK/tools" not_written
  run_tools_update "$folder"
  not_written="$(lock_files_not_holding "$folder" "$NEW_LOCK_TEXT")"
  [[ "$STATUS" -eq 0 && -z "$not_written" ]] && { pass "runs with no site.json and writes the four lock files"; return 0; }
  fail "runs with no site.json and writes the four lock files: exit status $STATUS, not written: ${not_written:-none}
$OUTPUT"
}

# Each container's working folder is a temporary copy, gone afterwards, never the repository.
containers_see_only_temporary_copies() {
  local folder="$WORK/tools" sources source problems=""
  sources="$(grep -oE -- '-v [^ ]+:/(app|npm) ' "$WORK/docker-calls" | sed -E 's/^-v ([^ ]+):\/(app|npm) $/\1/')"
  [[ "$(grep -c . <<<"$sources")" -eq 4 ]] || problems+=" expected 4 working folders, got: $sources;"
  while IFS= read -r source; do
    [[ "$source" == "$folder"* ]] && problems+=" $source is in the repository;"
    [[ -e "$source" ]] && problems+=" $source was not removed;"
  done <<<"$sources"
  [[ -z "$problems" ]] && { pass "Composer and npm see only temporary copies, removed afterwards"; return 0; }
  fail "Composer and npm see only temporary copies, removed afterwards:$problems"
}

npm_runs_no_scripts_and_keeps_the_wait() {
  local npm_calls safe_calls
  npm_calls="$(grep -c ' npm install ' "$WORK/docker-calls")"
  safe_calls="$(grep ' npm install ' "$WORK/docker-calls" | grep -- '--ignore-scripts' | grep -c -- '--before=')"
  [[ "$npm_calls" -eq 3 && "$safe_calls" -eq 3 ]] && { pass "npm runs without install scripts and only on releases past the wait"; return 0; }
  fail "npm runs without install scripts and only on releases past the wait: $safe_calls of $npm_calls npm calls carry both"
}

refuses_an_installed_copy() {
  local folder="$WORK/installed-copy" changed
  write_tools_folder "$folder" installed-copy
  run_tools_update "$folder"
  changed="$(lock_files_not_holding "$folder" "$OLD_LOCK_TEXT")"
  [[ "$STATUS" -ne 0 && -z "$changed" && ! -s "$WORK/docker-calls" ]] && { pass "refuses a copy without .git before writing anything"; return 0; }
  fail "refuses a copy without .git before writing anything: exit status $STATUS, changed: ${changed:-none}, docker called: $(grep -c . "$WORK/docker-calls")"
}

failed_update_keeps_the_lock_files() {
  local folder="$WORK/failing" changed
  write_tools_folder "$folder" repository
  run_tools_update "$folder" STANDIN_DOCKER_FAILS=composer
  changed="$(lock_files_not_holding "$folder" "$OLD_LOCK_TEXT")"
  [[ "$STATUS" -ne 0 && -z "$changed" ]] && { pass "a failed update leaves the lock files as they were"; return 0; }
  fail "a failed update leaves the lock files as they were: exit status $STATUS, changed: ${changed:-none}"
}

main() {
  local failures=0
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  mkdir -p "$WORK/elsewhere"
  printf '{}\n' >"$WORK/elsewhere/site.json"
  write_standin_docker
  write_tools_folder "$WORK/tools" repository
  runs_without_a_site_and_writes_every_lock || failures=$((failures + 1))
  containers_see_only_temporary_copies || failures=$((failures + 1))
  npm_runs_no_scripts_and_keeps_the_wait || failures=$((failures + 1))
  refuses_an_installed_copy || failures=$((failures + 1))
  failed_update_keeps_the_lock_files || failures=$((failures + 1))
  log "$((5 - failures)) of 5 passed"
  [[ "$failures" -eq 0 ]]
}

main "$@"
