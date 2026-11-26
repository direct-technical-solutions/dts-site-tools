#!/usr/bin/env bash
# Tests a DTS plugin's file rules (tools/plugin-rules.sh, template plan T25, T26) and
# bin/plugin-check's arguments, run by the tools' self-check every time. A stand-in plugin that
# keeps every rule (good/) is accepted; copies of it with one fault each are refused, the refusal
# naming the file or tag at fault (its wording around that is not checked). bin/plugin-check
# refuses wrong arguments before it starts any container. Needs bash, jq, git, cp and mktemp;
# nothing goes over the network.
set -Euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly HERE
TOOLS_DIR="$(cd "$HERE/../../.." && pwd)"
readonly TOOLS_DIR
# shellcheck source=tools/plugin-rules.sh
source "$TOOLS_DIR/tools/plugin-rules.sh"

log() { printf '%s [plugin-check tests] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

WORK=""

# A fresh copy of the good stand-in, as a git repository (git reads .gitattributes there).
fresh_plugin() {
  local plugin="$WORK/plugin-$RANDOM$RANDOM"
  cp -r "$HERE/good" "$plugin"
  git -C "$plugin" init -q
  printf '%s\n' "$plugin"
}

expect_accepted() {
  local what="$1" problems="$2"
  [[ -z "$problems" ]] && { log "ok    $what"; return 0; }
  log "FAIL  $what: expected no problem, got: $problems"
  return 1
}

# A problem line starts with what it is about, then a colon.
expect_refused() {
  local what="$1" named="$2" problems="$3"
  cut -d: -f1 <<<"$problems" | grep -qxF -- "$named" && { log "ok    $what"; return 0; }
  log "FAIL  $what: expected a problem naming $named, got: ${problems:-nothing}"
  return 1
}

composer_examples() {
  local plugin failed=0
  plugin="$(fresh_plugin)"
  jq '.name = "acme/example-plugin"' "$HERE/good/composer.json" >"$plugin/composer.json"
  expect_refused "a name outside dts/" composer.json "$(plugin_rules_problems "$plugin")" || failed=1
  plugin="$(fresh_plugin)"
  jq '.name = "dts/Example_Plugin"' "$HERE/good/composer.json" >"$plugin/composer.json"
  expect_refused "a slug WordPress would not use" composer.json "$(plugin_rules_problems "$plugin")" || failed=1
  plugin="$(fresh_plugin)"
  jq '.type = "library"' "$HERE/good/composer.json" >"$plugin/composer.json"
  expect_refused "a type composer/installers would not place" composer.json "$(plugin_rules_problems "$plugin")" || failed=1
  plugin="$(fresh_plugin)"
  printf 'not json\n' >"$plugin/composer.json"
  expect_refused "a composer.json that is not JSON" composer.json "$(plugin_rules_problems "$plugin")" || failed=1
  return "$failed"
}

main_file_examples() {
  local plugin failed=0
  plugin="$(fresh_plugin)"
  mv "$plugin/example-plugin.php" "$plugin/other-name.php"
  expect_refused "a main file not named after the slug" other-name.php "$(plugin_rules_problems "$plugin")" || failed=1
  plugin="$(fresh_plugin)"
  sed -i '/Update URI/d' "$plugin/example-plugin.php"
  expect_refused "a header without Update URI: false" example-plugin.php "$(plugin_rules_problems "$plugin")" || failed=1
  plugin="$(fresh_plugin)"
  sed -i 's/Version:     1.0.0/Version:     1.0/' "$plugin/example-plugin.php"
  expect_refused "a version that is not a plain release number" example-plugin.php "$(plugin_rules_problems "$plugin")" || failed=1
  return "$failed"
}

changelog_and_download_examples() {
  local plugin failed=0
  plugin="$(fresh_plugin)"
  sed -i 's/Version:     1.0.0/Version:     1.1.0/' "$plugin/example-plugin.php"
  expect_refused "a version the changelog has no release for" CHANGELOG.md "$(plugin_rules_problems "$plugin")" || failed=1
  plugin="$(fresh_plugin)"
  sed -i '/^## \[[0-9]/,$d' "$plugin/CHANGELOG.md"
  expect_refused "a changelog with only Unreleased" CHANGELOG.md "$(plugin_rules_problems "$plugin")" || failed=1
  plugin="$(fresh_plugin)"
  sed -i '/phpstan.neon.dist/d' "$plugin/.gitattributes"
  expect_refused "a check setting left in the download" .gitattributes "$(plugin_download_problems "$plugin")" || failed=1
  plugin="$(fresh_plugin)"
  expect_accepted "the stand-in's download leaves every check setting out" "$(plugin_download_problems "$plugin")" || failed=1
  return "$failed"
}

tag_examples() {
  local plugin failed=0
  plugin="$(fresh_plugin)"
  expect_accepted "the stand-in that keeps every rule" "$(plugin_rules_problems "$plugin")" || failed=1
  expect_accepted "its release tag v1.0.0" "$(plugin_rules_problems "$plugin" v1.0.0)" || failed=1
  expect_refused "a tag naming another version" "tag v1.0.1" "$(plugin_rules_problems "$plugin" v1.0.1)" || failed=1
  expect_refused "a tag without its v" "tag 1.0.0" "$(plugin_rules_problems "$plugin" 1.0.0)" || failed=1
  return "$failed"
}

# bin/plugin-check, in a stand-in plugin with the tools apart, started through Composer's bin
# folder as a plugin starts it; a stand-in docker records any call, which must not happen.
run_plugin_check() {
  local plugin="$1"
  shift
  (cd "$WORK" && env PATH="$WORK/fakes:$PATH" COMPOSER_RUNTIME_BIN_DIR="$plugin/bin" \
    bash "$TOOLS_DIR/bin/plugin-check" "$@") >/dev/null 2>&1
}

expect_arguments_refused() {
  local what="$1" plugin="$2"
  shift 2
  rm -f "$WORK/docker-called"
  run_plugin_check "$plugin" "$@" && { log "FAIL  $what: accepted"; return 1; }
  [[ -e "$WORK/docker-called" ]] && { log "FAIL  $what: started a container first"; return 1; }
  log "ok    $what"
}

argument_examples() {
  local plugin failed=0
  plugin="$(fresh_plugin)"
  mkdir -p "$plugin/bin" "$WORK/fakes"
  printf '{"packages": [], "packages-dev": []}\n' >"$plugin/composer.lock"
  printf '#!/usr/bin/env bash\ntouch "%s/docker-called"\n' "$WORK" >"$WORK/fakes/docker"
  chmod +x "$WORK/fakes/docker"
  expect_arguments_refused "bin/plugin-check refuses an unknown argument" "$plugin" --release || failed=1
  expect_arguments_refused "bin/plugin-check refuses --tag without a tag" "$plugin" --tag || failed=1
  expect_arguments_refused "bin/plugin-check refuses a second tag" "$plugin" --tag v1.0.0 v1.0.1 || failed=1
  return "$failed"
}

main() {
  local failed=0
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  composer_examples || failed=1
  main_file_examples || failed=1
  changelog_and_download_examples || failed=1
  tag_examples || failed=1
  argument_examples || failed=1
  return "$failed"
}

main "$@"
