#!/usr/bin/env bash
# Tests how bin/check finds the site's own plugins (site_plugins_mount_arguments and
# site_plugin_folders in tools/site-settings.sh, template plan 2.2c), run by the tools' self-check
# every time, on stand-in sites: one without plugins/ (all its plugins downloaded), one with an
# empty plugins/, one with two plugins and a file beside them. A site without the folder must get
# no mount, since Docker would create it owned by root, and no plugin folders, since the names
# check would then make grep read its standard input. Needs bash and mktemp.
set -Euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly HERE
WORK="$(mktemp -d)"
readonly WORK
trap 'rm -rf "$WORK"' EXIT
# site-settings.sh reads the site's folder when it is loaded; the stand-ins live in WORK.
PROJECT_DIR="$WORK"
TOOLS_DIR="$WORK"
export PROJECT_DIR TOOLS_DIR
# shellcheck source=tools/site-settings.sh
source "$HERE/../../../tools/site-settings.sh"

log() { printf '%s [site plugins tests] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

write_stand_in_sites() {
  mkdir -p "$WORK/without-folder" "$WORK/empty-folder/plugins" \
    "$WORK/with-plugins/plugins/first-plugin" "$WORK/with-plugins/plugins/second-plugin"
  printf 'not a plugin\n' >"$WORK/with-plugins/plugins/README.md"
}

# Compares a helper's output with the expected lines (empty: no output), naming the example.
expect_output() {
  local what="$1" expected="$2" actual="$3"
  [[ "$actual" == "$expected" ]] || { log "FAIL  $what: expected \"$expected\", got \"$actual\""; return 1; }
  log "ok    $what"
}

main() {
  local failed=0 site
  write_stand_in_sites
  site="$WORK/without-folder"
  expect_output "no plugins/: no mount" "" \
    "$(site_plugins_mount_arguments "$site/plugins" /app/plugins)" || failed=1
  expect_output "no plugins/: no plugin folders" "" "$(site_plugin_folders "$site/plugins")" || failed=1
  [[ ! -e "$site/plugins" ]] || { log "FAIL  no plugins/: the helpers created the folder"; failed=1; }
  site="$WORK/empty-folder"
  expect_output "empty plugins/: mounted" "$(printf '%s\n' -v "$site/plugins:/app/plugins:ro")" \
    "$(site_plugins_mount_arguments "$site/plugins" /app/plugins)" || failed=1
  expect_output "empty plugins/: no plugin folders" "" "$(site_plugin_folders "$site/plugins")" || failed=1
  site="$WORK/with-plugins"
  expect_output "two plugins and a file: both folders, not the file" \
    "$(printf '%s\n' "$site/plugins/first-plugin" "$site/plugins/second-plugin")" \
    "$(site_plugin_folders "$site/plugins")" || failed=1
  return "$failed"
}

main "$@"
