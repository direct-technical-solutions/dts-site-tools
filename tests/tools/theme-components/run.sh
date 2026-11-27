#!/usr/bin/env bash
# Tests the theme's component checks (tools/theme-components.sh, template plan T30) on known
# examples, run by the tools' self-check every time: a theme whose named stylesheets, files and
# examples agree passes, and each broken one is refused, naming what is wrong. The examples are
# written fresh into a temporary folder, so nothing depends on any site's theme. Needs bash,
# find, grep, sed, sort and comm.
set -Euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly HERE
# shellcheck source=tools/theme-components.sh
source "$HERE/../../../tools/theme-components.sh"

log() { printf '%s [theme component tests] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

EXAMPLES_DIR=""

# The list as the shared theme writes it: block names (left out) mapped to component names.
readonly FUNCTIONS_PHP="<?php
const DTSTHEME_COMPONENT_STYLES = array(
	'core/group'  => array( 'site-hero', 'site-media' ),
	'core/button' => array( 'buttons' ),
);
const DTSTHEME_FORM_STYLESHEET = 'assets/css/components/form.css';
"
readonly VIDEO_FACADE_PHP="<?php
const DTSTHEME_VIDEO_FACADE_STYLESHEET = 'assets/css/components/video-facade.css';
"
readonly AGREEING_FILES='site-hero site-media buttons form video-facade'
readonly AGREEING_PAGE='<div class="wp-block-group site-hero"></div><p class="site-media-placeholder"></p>'

# Writes a theme with the given stylesheets (space-separated names), an example page with the
# given HTML, and the two PHP files.
write_example() {
  local files="$1" page="$2" name
  rm -rf "$EXAMPLES_DIR/theme" "$EXAMPLES_DIR/pages"
  mkdir -p "$EXAMPLES_DIR/theme/assets/css/components" "$EXAMPLES_DIR/theme/includes" "$EXAMPLES_DIR/theme/parts" "$EXAMPLES_DIR/pages"
  printf '%s' "$FUNCTIONS_PHP" >"$EXAMPLES_DIR/theme/functions.php"
  printf '%s' "$VIDEO_FACADE_PHP" >"$EXAMPLES_DIR/theme/includes/video-facade.php"
  for name in $files; do
    : >"$EXAMPLES_DIR/theme/assets/css/components/$name.css"
  done
  printf '%s\n' "$page" >"$EXAMPLES_DIR/pages/example.html"
}

all_problems() {
  theme_component_style_differences "$EXAMPLES_DIR/theme"
  theme_components_missing_examples "$EXAMPLES_DIR/theme" "$EXAMPLES_DIR/pages"
}

expect_none() {
  local what="$1" problems
  problems="$(all_problems)"
  [[ -z "$problems" ]] && { log "ok    $what"; return 0; }
  log "FAIL  $what was refused: $problems"
  return 1
}

# The problem must be named exactly, as one of the lines printed.
expect_problem() {
  local expected="$1" what="$2" problems
  problems="$(all_problems)"
  grep -qxF -- "$expected" <<<"$problems" && { log "ok    $what"; return 0; }
  log "FAIL  $what: expected \"$expected\", got: ${problems:-nothing}"
  return 1
}

expect_agreeing_themes() {
  local failed=0
  write_example "$AGREEING_FILES" "$AGREEING_PAGE"
  expect_none "a theme whose names, files and examples agree" || failed=1
  write_example "$AGREEING_FILES" '<p class="site-media"></p>'
  printf '<header class="site-hero"></header>\n' >"$EXAMPLES_DIR/theme/parts/header.html"
  expect_none "a component shown only in a template part" || failed=1
  return "$failed"
}

expect_style_problems() {
  local failed=0 dir="assets/css/components/"
  write_example 'site-hero site-media form video-facade' "$AGREEING_PAGE"
  expect_problem "named but no file in $dir: buttons" "a block component without its file" || failed=1
  write_example 'site-hero site-media buttons video-facade' "$AGREEING_PAGE"
  expect_problem "named but no file in $dir: form" "the form's stylesheet without its file" || failed=1
  write_example 'site-hero site-media buttons form' "$AGREEING_PAGE"
  expect_problem "named but no file in $dir: video-facade" "the video facade's stylesheet without its file" || failed=1
  write_example "$AGREEING_FILES extra" "$AGREEING_PAGE"
  expect_problem "file in $dir but not named: extra" "a stylesheet no list names" || failed=1
  return "$failed"
}

expect_list_problems() {
  local failed=0
  write_example "$AGREEING_FILES" "$AGREEING_PAGE"
  sed -i 's/DTSTHEME_/HBMUSIC_/' "$EXAMPLES_DIR/theme/functions.php"
  expect_problem "functions.php lists no component stylesheets under DTSTHEME_COMPONENT_STYLES" "a list under a site's own prefix" || failed=1
  rm "$EXAMPLES_DIR/theme/functions.php"
  expect_problem "missing file: functions.php" "functions.php missing" || failed=1
  return "$failed"
}

expect_example_problems() {
  local failed=0
  write_example "$AGREEING_FILES" '<p class="site-media"></p>'
  expect_problem "on no example page or template part: site-hero" "a component shown nowhere" || failed=1
  write_example "$AGREEING_FILES" '<div class="site-hero__photo"></div><p class="site-media"></p>'
  expect_problem "on no example page or template part: site-hero" "a component shown only as its __ element" || failed=1
  return "$failed"
}

main() {
  local failed=0
  # The script runs without errexit, so a failed mktemp must stop it here: an empty folder name
  # would point write_example's rm -rf and mkdir at the top of the disk.
  EXAMPLES_DIR="$(mktemp -d)" || { log "FAIL  could not create a temporary folder"; return 1; }
  trap 'rm -rf "$EXAMPLES_DIR"' EXIT
  expect_agreeing_themes || failed=1
  expect_style_problems || failed=1
  expect_list_problems || failed=1
  expect_example_problems || failed=1
  return "$failed"
}

main "$@"
