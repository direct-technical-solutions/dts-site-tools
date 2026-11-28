#!/usr/bin/env bash
# Scenario (dev site): the theme reads the site's facts from a site-facts.json (template plan
# 2.4b-2, T31; Dtstheme_Site_Facts) and keeps the site working when it cannot: a missing file and
# a broken one leave every fact at its default, a fact of the wrong shape leaves only that fact at
# its default, and each writes a line to the PHP error log naming what was wrong, since WordPress's
# own JSON reader is silent with WP_DEBUG off. Run through WordPress with the theme loaded, on
# stand-in files in the container's temporary folder, so it holds for any site's facts; the site's
# own facts are checked on its pages by the site's tests. The error log is pointed at a temporary
# file for each case, so nothing reaches the dev site's debug log.
set -Eeuo pipefail
# shellcheck source=tests/scenario/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

# Each case's facts, as the theme read them, and its log lines, as one JSON object by case.
read_stand_in_facts() {
  dev_compose run --rm -T cli wp eval-file - <<'PHP'
<?php
ini_set( 'display_errors', '0' );
$cases = array(
	'good'      => '{"oldAddresses":[{"from":"old-page","to":"new-page","reason":"r"}],"organizationTypes":{"types":["Organization","LocalBusiness"],"reason":"r"},"areasServed":{"towns":["Town A, State"],"reason":"r"},"outsideSources":[{"directive":"frame-src","source":"https://a.example","reason":"r"},{"directive":"frame-src","source":"https://b.example","reason":"r"}]}',
	'broken'    => '{ "oldAddresses": [',
	'one-wrong' => '{"oldAddresses":"not a list","organizationTypes":{"types":["Organization","LocalBusiness"],"reason":"r"},"areasServed":{"towns":["Town A, State"],"reason":"r"},"outsideSources":[]}',
	'missing'   => null,
);
$results = array();
foreach ( $cases as $name => $text ) {
	$path = sys_get_temp_dir() . "/site-facts-$name.json";
	$log  = sys_get_temp_dir() . "/site-facts-$name.log";
	if ( null !== $text ) {
		file_put_contents( $path, $text );
	}
	ini_set( 'error_log', $log );
	$facts            = Dtstheme_Site_Facts::from_file( $path );
	$results[ $name ] = array(
		'facts' => get_object_vars( $facts ),
		'log'   => is_file( $log ) ? (string) file_get_contents( $log ) : '',
	);
}
echo wp_json_encode( $results );
PHP
}

# The defaults a site gets for facts it cannot read: no redirects, Yoast's own type, no towns, no
# outside sources (PHP's empty lists come out of JSON as []).
readonly DEFAULT_FACTS='{"old_addresses": [], "organization_types": ["Organization"], "areas_served": [], "outside_sources": []}'

expect_case() {
  local results="$1" case_name="$2" condition="$3" meaning="$4"
  # The conditions name the defaults as the jq function "defaults".
  jq -e --argjson default_facts "$DEFAULT_FACTS" "def defaults: \$default_facts; .[\"$case_name\"] | $condition" <<<"$results" >/dev/null && return 0
  fail "$case_name: $meaning; read: $(jq -c ".[\"$case_name\"]" <<<"$results" | cut -c1-400)"
}

main() {
  local results
  load_settings
  results="$(read_stand_in_facts)"
  jq -e 'type == "object"' <<<"$results" >/dev/null 2>&1 || fail "the theme's reader printed no result: ${results:0:400}"
  expect_case "$results" good '.facts == {"old_addresses": {"old-page": "new-page"},
      "organization_types": ["Organization", "LocalBusiness"], "areas_served": ["Town A, State"],
      "outside_sources": {"frame-src": ["https://a.example", "https://b.example"]}} and .log == ""' \
    "a valid file was not read as written, or wrote to the log"
  expect_case "$results" missing '.facts == defaults and (.log | test("site-facts.json"))' \
    "a missing file did not leave every fact at its default with a log line"
  expect_case "$results" broken '.facts == defaults and (.log | test("site-facts.json"))' \
    "a broken file did not leave every fact at its default with a log line"
  expect_case "$results" one-wrong '.facts.old_addresses == [] and .facts.areas_served == ["Town A, State"]
      and .facts.organization_types == ["Organization", "LocalBusiness"] and (.log | test("oldAddresses"))' \
    "a fact of the wrong shape did not leave only that fact at its default, named in the log"
  log "a valid file is read as written; a missing or broken file, or one wrong fact, leaves its defaults and a log line"
}

main "$@"
