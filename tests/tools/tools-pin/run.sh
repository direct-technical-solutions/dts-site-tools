#!/usr/bin/env bash
# Tests the workflows' pin (tools/tools-pin.sh and bin/tools-pin, template plan T18, T22), run by
# the tools' self-check every time, on stand-in lock files and a stand-in site, with the tools apart
# from it as a site installs them. The release is read from the lock file (from require-dev or
# require), and a lock file without the tools, with a short commit or that is not JSON is refused,
# naming the problem; what bin/tools-pin writes matches, and a commit left behind, a hand edit or a
# missing file is each named by bin/check's comparison; bin/tools-pin started without a usable
# release writes nothing; in a DTS plugin's repository it writes the plugin's caller only. Needs bash, jq, cmp, cp and mktemp; nothing goes over the network.
set -Euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly HERE
TOOLS_DIR="$(cd "$HERE/../../.." && pwd)"
readonly TOOLS_DIR
# shellcheck source=tools/tools-pin.sh
source "$TOOLS_DIR/tools/tools-pin.sh"

log() { printf '%s [tools-pin tests] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

readonly OLD_COMMIT="1111111111111111111111111111111111111111"
readonly NEW_COMMIT="2222222222222222222222222222222222222222"
WORK=""

# A lock file installing the tools at a commit and version, in the given section.
write_lock() {
  local file="$1" section="$2" commit="$3" version="$4"
  jq -n --arg section "$section" --arg commit "$commit" --arg version "$version" \
    '{packages: [], "packages-dev": []}
     | .[$section] += [{name: "dts/site-tools", version: $version, source: {type: "git", reference: $commit}}]' >"$file"
}

expect_release() {
  local what="$1" lock_file="$2" expected="$3" release
  release="$(tools_pin_locked_release "$lock_file" 2>&1)" && [[ "$release" == "$expected" ]] &&
    { log "ok    $what"; return 0; }
  log "FAIL  $what: expected \"$expected\", got: $release"
  return 1
}

# A refusal fails and names what is wrong; its wording around that is not checked.
expect_release_refused() {
  local what="$1" lock_file="$2" named="$3" output
  output="$(tools_pin_locked_release "$lock_file" 2>&1)" &&
    { log "FAIL  $what: accepted, printed \"$output\""; return 1; }
  [[ "$output" == *"$named"* ]] && { log "ok    $what"; return 0; }
  log "FAIL  $what: expected a refusal naming $named, got: $output"
  return 1
}

release_examples() {
  local failed=0
  write_lock "$WORK/dev.lock" packages-dev "$NEW_COMMIT" v0.2.0
  expect_release "the release read from require-dev" "$WORK/dev.lock" "$NEW_COMMIT v0.2.0" || failed=1
  write_lock "$WORK/require.lock" packages "$NEW_COMMIT" dev-main
  expect_release "a branch read from require" "$WORK/require.lock" "$NEW_COMMIT dev-main" || failed=1
  jq -n '{packages: [{name: "other/package", version: "1.0.0", source: {reference: "x"}}]}' >"$WORK/without.lock"
  expect_release_refused "a lock file without the tools" "$WORK/without.lock" "dts/site-tools" || failed=1
  printf '{"packages": "not a list"}\n' >"$WORK/shape.lock"
  expect_release_refused "a lock file whose package list is not a list" "$WORK/shape.lock" "$WORK/shape.lock" || failed=1
  write_lock "$WORK/short.lock" packages-dev 2222222 v0.2.0
  expect_release_refused "a short commit" "$WORK/short.lock" "2222222" || failed=1
  write_lock "$WORK/version.lock" packages-dev "$NEW_COMMIT" 'v0.2.0 # x'
  expect_release_refused "a version that would break the line" "$WORK/version.lock" "v0.2.0 # x" || failed=1
  printf 'not json\n' >"$WORK/broken.lock"
  expect_release_refused "a lock file that is not JSON" "$WORK/broken.lock" "not JSON" || failed=1
  return "$failed"
}

expect_differences() {
  local what="$1" workflows_dir="$2" expected="$3" differences
  differences="$(tools_pin_differences "$SITE_WORKFLOW_TEMPLATES_DIR" "$workflows_dir" "$NEW_COMMIT" v0.2.0)"
  [[ "$differences" == "$expected" ]] && { log "ok    $what"; return 0; }
  log "FAIL  $what: expected \"${expected:-nothing}\", got: ${differences:-nothing}"
  return 1
}

# Only the file's name is checked, the start of each difference line, not the wording after it.
expect_difference_naming() {
  local what="$1" workflows_dir="$2" named="$3" differences
  differences="$(tools_pin_differences "$SITE_WORKFLOW_TEMPLATES_DIR" "$workflows_dir" "$NEW_COMMIT" v0.2.0)"
  [[ "$(cut -d: -f1 <<<"$differences")" == "$named" ]] && { log "ok    $what"; return 0; }
  log "FAIL  $what: expected one difference naming $named, got: ${differences:-nothing}"
  return 1
}

comparison_examples() {
  local workflows="$WORK/workflows" failed=0
  tools_pin_write "$SITE_WORKFLOW_TEMPLATES_DIR" "$workflows" "$NEW_COMMIT" v0.2.0
  expect_differences "what bin/tools-pin writes matches" "$workflows" "" || failed=1
  tools_pin_write "$SITE_WORKFLOW_TEMPLATES_DIR" "$workflows" "$OLD_COMMIT" v0.1.0
  expect_differences "a commit left behind is named in every caller" "$workflows" \
    "$(printf '%s: differs from what bin/tools-pin writes for v0.2.0 (2222222)\n' check.yml plugin-updates.yml versions.yml)" || failed=1
  tools_pin_write "$SITE_WORKFLOW_TEMPLATES_DIR" "$workflows" "$NEW_COMMIT" v0.2.0
  sed -i 's/17 6 \* \* 1/0 0 * * */' "$workflows/check.yml"
  expect_difference_naming "a hand edit is named" "$workflows" "check.yml" || failed=1
  tools_pin_write "$SITE_WORKFLOW_TEMPLATES_DIR" "$workflows" "$NEW_COMMIT" v0.2.0
  rm "$workflows/versions.yml"
  expect_difference_naming "a missing caller is named" "$workflows" "versions.yml" || failed=1
  tools_pin_write "$SITE_WORKFLOW_TEMPLATES_DIR" "$workflows" "$NEW_COMMIT" v0.2.0
  printf 'name: the site'"'"'s own\n' >"$workflows/own.yml"
  expect_differences "the site's other workflows are left alone" "$workflows" "" || failed=1
  return "$failed"
}

# A tools folder apart from a stand-in site, holding copies of what bin/tools-pin needs.
write_tools_apart() {
  local folder="$WORK/tools-apart"
  mkdir -p "$folder/bin" "$folder/tools" "$WORK/site/bin" "$WORK/elsewhere"
  cp "$TOOLS_DIR/bin/tools-pin" "$folder/bin/"
  cp "$TOOLS_DIR/tools/paths.sh" "$TOOLS_DIR/tools/tools-pin.sh" "$folder/tools/"
  cp -r "$TOOLS_DIR/tools/site-workflows" "$TOOLS_DIR/tools/plugin-workflows" "$folder/tools/"
}

# Started from an unrelated folder through Composer's bin folder, as a site (or, given its folder,
# a plugin) starts it.
run_tools_pin() {
  local repository="${1:-$WORK/site}"
  (cd "$WORK/elsewhere" && env COMPOSER_RUNTIME_BIN_DIR="$repository/bin" bash "$WORK/tools-apart/bin/tools-pin") >/dev/null 2>&1
}

command_examples() {
  local workflows="$WORK/site/.github/workflows" failed=0
  write_tools_apart
  jq -n '{packages: [], "packages-dev": []}' >"$WORK/site/composer.lock"
  run_tools_pin && { log "FAIL  bin/tools-pin accepted a lock file without the tools"; failed=1; }
  if [[ -e "$workflows" ]]; then
    log "FAIL  bin/tools-pin wrote workflows without a usable release"
    failed=1
  else
    log "ok    bin/tools-pin wrote nothing without a usable release"
  fi
  write_lock "$WORK/site/composer.lock" packages-dev "$NEW_COMMIT" v0.2.0
  run_tools_pin || { log "FAIL  bin/tools-pin failed on a usable release"; failed=1; }
  expect_differences "bin/tools-pin writes the site's callers for the installed release" "$workflows" "" || failed=1
  return "$failed"
}

plugin_caller_examples() {
  local plugin="$1" written
  written="$(find "$plugin/.github/workflows" -type f -printf '%f\n' 2>/dev/null)"
  if [[ "$written" == "check.yml" && -z "$(tools_pin_differences "$PLUGIN_WORKFLOW_TEMPLATES_DIR" "$plugin/.github/workflows" "$NEW_COMMIT" v0.2.0)" ]]; then
    log "ok    bin/tools-pin writes only the plugin's caller in a plugin's repository"
    return 0
  fi
  log "FAIL  bin/tools-pin in a plugin's repository wrote: ${written:-nothing}"
  return 1
}

# A DTS plugin's repository (composer.json of type wordpress-plugin, template plan T26) gets the
# plugin's caller only; a site's composer.json, of any other type or none, the site's callers.
plugin_examples() {
  local plugin="$WORK/plugin" failed=0
  mkdir -p "$plugin/bin" "$WORK/site-typed"
  printf '{"name": "dts/example-plugin", "type": "wordpress-plugin"}\n' >"$plugin/composer.json"
  printf '{"name": "example/site", "type": "project"}\n' >"$WORK/site-typed/composer.json"
  if [[ "$(tools_pin_templates_dir_of "$plugin")" == "$PLUGIN_WORKFLOW_TEMPLATES_DIR" &&
    "$(tools_pin_templates_dir_of "$WORK/site-typed")" == "$SITE_WORKFLOW_TEMPLATES_DIR" &&
    "$(tools_pin_templates_dir_of "$WORK/elsewhere")" == "$SITE_WORKFLOW_TEMPLATES_DIR" ]]; then
    log "ok    a plugin's repository gets the plugin's templates, any other the site's"
  else
    log "FAIL  the templates chosen by composer.json's type"
    failed=1
  fi
  write_lock "$plugin/composer.lock" packages-dev "$NEW_COMMIT" v0.2.0
  run_tools_pin "$plugin" || { log "FAIL  bin/tools-pin failed in a plugin's repository"; failed=1; }
  plugin_caller_examples "$plugin" || failed=1
  return "$failed"
}

main() {
  local failed=0
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  release_examples || failed=1
  comparison_examples || failed=1
  command_examples || failed=1
  plugin_examples || failed=1
  return "$failed"
}

main "$@"
