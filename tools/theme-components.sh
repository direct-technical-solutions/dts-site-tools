#!/usr/bin/env bash
# The shared theme code's components (plan D29), held to two rules every site's theme follows
# (template plan T30; until 0.5.0 they were a site's own checks, tests/checks/components.sh):
# the component stylesheets the theme names and the files in assets/css/components/ match, both
# ways, since WordPress silently loads nothing for a name without a file; and every component of
# the theme's own (named site-…) appears on the components' example pages or in the theme's
# template parts, so the browser tests see it on neutral content whatever a site's pages hold
# (template plan T10). The theme's PHP names carry the fixed prefix every site shares (T30), never
# one taken from a site's slug. Sourced by bin/check and tested on known examples by
# tests/tools/theme-components/run.sh. Needs bash, find, grep, sed, sort and comm.

readonly THEME_COMPONENTS_PHP_PREFIX='DTSTHEME'

# The block components functions.php lists (<PREFIX>_COMPONENT_STYLES, block → components), one
# per line; the block names, which hold a slash, are left out by the pattern.
theme_components_in_block_list() {
  sed -n "/^const ${THEME_COMPONENTS_PHP_PREFIX}_COMPONENT_STYLES/,/^);/p" "$1/functions.php" |
    grep -oE "'[a-z0-9-]+'" | tr -d "'" | sort -u
}

# Every component stylesheet the theme names: the block components, the form's (loaded by page)
# and the video facade's (loaded with a page's videos, includes/video-facade.php).
theme_components_named() {
  local theme_dir="$1" php_files=()
  [[ -f "$theme_dir/includes/video-facade.php" ]] && php_files+=("$theme_dir/includes/video-facade.php")
  {
    theme_components_in_block_list "$theme_dir"
    sed -nE "s#^const ${THEME_COMPONENTS_PHP_PREFIX}_(FORM|VIDEO_FACADE)_STYLESHEET *= 'assets/css/components/([a-z0-9-]+)\.css';#\2#p" \
      "$theme_dir/functions.php" "${php_files[@]}"
  } | sort -u
}

theme_component_files() {
  find "$1/assets/css/components" -maxdepth 1 -name '*.css' -printf '%f\n' 2>/dev/null | sed 's/\.css$//' | sort -u
}

# Prints one line per problem, nothing when the names and the files agree: a missing
# functions.php, a list that names nothing (the list or its prefix changed), a name without a
# file, a file without a name.
theme_component_style_differences() {
  local theme_dir="$1" named
  [[ -f "$theme_dir/functions.php" ]] || { printf 'missing file: functions.php\n'; return 0; }
  [[ -n "$(theme_components_in_block_list "$theme_dir")" ]] ||
    { printf 'functions.php lists no component stylesheets under %s_COMPONENT_STYLES\n' "$THEME_COMPONENTS_PHP_PREFIX"; return 0; }
  named="$(theme_components_named "$theme_dir")"
  comm -23 <(printf '%s\n' "$named") <(theme_component_files "$theme_dir") | sed '/^$/d; s/^/named but no file in assets\/css\/components\/: /'
  comm -13 <(printf '%s\n' "$named") <(theme_component_files "$theme_dir") | sed '/^$/d; s/^/file in assets\/css\/components\/ but not named: /'
}

# Prints one line per site-… component that appears on no example page and in no template part.
# A class followed by a dash counts too, so site-media covers site-media-placeholder (grep's \b
# treats a dash as a boundary and an underscore as part of the word, so site-hero__photo alone
# does not cover site-hero); components named after a WordPress block (buttons) are seen wherever
# that block is, so they are not listed here.
theme_components_missing_examples() {
  local theme_dir="$1" examples_dir="$2" component
  [[ -f "$theme_dir/functions.php" ]] || { printf 'missing file: functions.php\n'; return 0; }
  for component in $(theme_components_in_block_list "$theme_dir" | grep '^site-'); do
    grep -qsE "class=\"[^\"]*\\b$component\\b" "$examples_dir"/*.html "$theme_dir"/parts/*.html && continue
    printf 'on no example page or template part: %s\n' "$component"
  done
}
