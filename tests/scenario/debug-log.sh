#!/usr/bin/env bash
# The rule for WordPress's debug log on the dev site (template plan 1.5b, agreed with the user on
# 2026-11-22), sourced by tests/scenario/lib.sh and tested on sample logs by
# tests/tools/debug-log/run.sh. Every line is sorted:
#   - a message whose origin is the site's own code (its theme, its own plugins, DTS's plugins it
#     downloads, the dev site's must-use plugins) fails, whatever its level;
#   - a notice, warning or deprecation from other people's code (WordPress, WordPress.org's
#     plugins) is shown, not failed: their code is theirs to fix, and the browser tests show
#     whether it breaks anything;
#   - every other line fails: a fatal error (which PHP writes itself), or a message written
#     without an origin, so a gap in the sorting can only err on the strict side.
# The origins come from config/dev-mu-plugins/dev-error-origin.php's "DEV ORIGIN" lines. The
# sourcing script also loads tools/site-packages.sh.

readonly DEBUG_LOG_ORIGIN_LINE='^\[[^]]+\] DEV ORIGIN (Warning|Notice|Deprecated) ([^ ]+) \| '

# The site's own code, as paths under wp-content/, one per line, from the given site.json and the
# site's downloaded plugins' lock file (site-packages/composer.lock). DTS's plugins count as the
# site's own (template plan 2.2c): they moved out of the site's plugins/ into their own
# repositories (T25), and DTS fixes their notices as it did before the move. A site without the
# lock file downloads none.
own_code_places() {
  local settings_file="$1" site_packages_lock="$2"
  jq -r '"themes/\(.theme)/", (.localPlugins[] | "plugins/\(.)/"), "mu-plugins/"' "$settings_file"
  [[ -f "$site_packages_lock" ]] || return 0
  site_packages_dts_plugin_slugs "$site_packages_lock" | sed 's|.*|plugins/&/|'
}

# Sorts the log text (first argument) against the own-code places (second, one per line): prints
# "fail<TAB>line" or "shown<TAB>line" for each line that is not empty.
debug_log_verdicts() {
  local log_text="$1" own_places="$2" line origin place is_own
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    if [[ ! "$line" =~ $DEBUG_LOG_ORIGIN_LINE ]]; then
      printf 'fail\t%s\n' "$line"
      continue
    fi
    origin="${BASH_REMATCH[2]}"
    is_own=false
    while IFS= read -r place; do
      [[ -n "$place" && "$origin" == "$place"* ]] && is_own=true
    done <<<"$own_places"
    if [[ "$is_own" == true ]]; then printf 'fail\t%s\n' "$line"; else printf 'shown\t%s\n' "$line"; fi
  done <<<"$log_text"
}
