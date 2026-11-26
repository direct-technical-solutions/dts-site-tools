#!/usr/bin/env bash
# The file rules of a DTS plugin's repository (template plan T25, T26), which bin/plugin-check
# runs: the Composer name and type a site installs it by, the main file that name leads to, the
# header that keeps WordPress.org from updating it, the version the changelog's newest release
# names, what the release download leaves out and, before and on a release, the tag. Each rule
# prints one line per problem, starting with the file or tag it is about, then a colon; nothing
# when the rule holds. Needs jq and git. Sourced, never run; the sourcing script defines TOOLS_DIR.

# shellcheck source=tools/plugin-header.sh
source "$TOOLS_DIR/tools/plugin-header.sh"

# Composer's name for a DTS plugin, "dts/<slug>" (tools/site-packages.sh reads it the same way).
# composer/installers puts it in wp-content/plugins/<slug>/, so the slug is the plugin's folder
# and WordPress's name for it: lower-case words joined by single dashes.
readonly PLUGIN_COMPOSER_NAME_PATTERN='^dts/[a-z0-9]+(-[a-z0-9]+)*$'
readonly PLUGIN_COMPOSER_TYPE="wordpress-plugin"
# A release tag is "v" and the version, as the tools' own tags are; the version is plain numbers,
# so the tag, the header and the changelog compare as text.
readonly PLUGIN_VERSION_PATTERN='^[0-9]+\.[0-9]+\.[0-9]+$'
# Keep a Changelog's release heading, "## [0.2.1] - 2026-11-26"; "## [Unreleased]" is not a release.
readonly CHANGELOG_RELEASE_PATTERN='^## \[([0-9]+\.[0-9]+\.[0-9]+)\]'

# Prints the slug from composer.json's name, or nothing when the name is not a DTS plugin's.
plugin_slug_of() {
  local plugin_dir="$1" name
  name="$(jq -r '.name // ""' "$plugin_dir/composer.json" 2>/dev/null)"
  [[ "$name" =~ $PLUGIN_COMPOSER_NAME_PATTERN ]] && printf '%s\n' "${name#dts/}"
  return 0
}

# composer.json names a DTS plugin, of the type composer/installers places as a plugin.
plugin_composer_problems() {
  local plugin_dir="$1" composer_file="$1/composer.json" name type
  [[ -f "$composer_file" ]] || { printf 'composer.json: missing\n'; return 0; }
  jq empty "$composer_file" 2>/dev/null || { printf 'composer.json: not JSON\n'; return 0; }
  name="$(jq -r '.name // ""' "$composer_file")"
  type="$(jq -r '.type // ""' "$composer_file")"
  [[ "$name" =~ $PLUGIN_COMPOSER_NAME_PATTERN ]] ||
    printf 'composer.json: the name "%s" is not dts/<slug> (lower-case words joined by dashes)\n' "$name"
  [[ "$type" == "$PLUGIN_COMPOSER_TYPE" ]] ||
    printf 'composer.json: the type "%s" is not %s, so composer/installers would not place it as a plugin\n' "$type" "$PLUGIN_COMPOSER_TYPE"
  return 0
}

# The main file is <slug>.php at the top, the file WordPress reads the header from: a site's
# checks and its deploy read the header there (tools/site-packages.sh), and the slug is the
# folder the plugin is installed into.
plugin_main_file_problems() {
  local plugin_dir="$1" slug main_file
  slug="$(plugin_slug_of "$plugin_dir")"
  [[ -n "$slug" ]] || return 0
  main_file="$(plugin_main_file "$plugin_dir")" || { printf '%s.php: missing, or its header has no "Plugin Name:"\n' "$slug"; return 0; }
  [[ "$main_file" == "$slug.php" ]] ||
    printf '%s: the header is here, but the main file must be %s.php, after the slug in composer.json\n' "$main_file" "$slug"
  return 0
}

# The header's "Update URI: false" and a plain version.
plugin_header_problems() {
  local plugin_dir="$1" slug main_file version
  slug="$(plugin_slug_of "$plugin_dir")"
  main_file="$plugin_dir/$slug.php"
  [[ -n "$slug" && -f "$main_file" ]] || return 0
  plugin_never_updated_from_wordpress_org "$main_file" ||
    printf '%s.php: no "Update URI: false" header, so WordPress.org could replace it with a plugin of the same name\n' "$slug"
  version="$(plugin_header_version "$main_file")"
  [[ "$version" =~ $PLUGIN_VERSION_PATTERN ]] ||
    printf '%s.php: the header'"'"'s Version "%s" is not a plain release number such as 1.2.3\n' "$slug" "$version"
  return 0
}

# The version a release carries is written down: CHANGELOG.md's newest release is the header's
# version. Checked on every pull request, so a release is right before it is tagged; a pushed tag
# can be removed only by switching its ruleset off (template plan T26).
plugin_changelog_problems() {
  local plugin_dir="$1" changelog="$1/CHANGELOG.md" slug version newest
  slug="$(plugin_slug_of "$plugin_dir")"
  [[ -n "$slug" && -f "$plugin_dir/$slug.php" ]] || return 0
  version="$(plugin_header_version "$plugin_dir/$slug.php")"
  [[ -f "$changelog" ]] || { printf 'CHANGELOG.md: missing\n'; return 0; }
  newest="$(sed -nE "s/$CHANGELOG_RELEASE_PATTERN.*/\\1/p" "$changelog" | head -n 1)"
  [[ "$newest" == "$version" ]] ||
    printf 'CHANGELOG.md: the newest release is "%s", the header of %s.php says "%s"\n' "${newest:-(none)}" "$slug" "$version"
  return 0
}

# A release tag names the header's version: "v" and the version.
plugin_tag_problems() {
  local plugin_dir="$1" tag="$2" slug version
  slug="$(plugin_slug_of "$plugin_dir")"
  [[ -n "$slug" && -f "$plugin_dir/$slug.php" ]] || return 0
  version="$(plugin_header_version "$plugin_dir/$slug.php")"
  [[ "$tag" == "v$version" ]] ||
    printf 'tag %s: does not name the version of %s.php, which would be tagged v%s\n' "$tag" "$slug" "$version"
  return 0
}

# What only the checks need, never a site that installs the plugin: GitHub's archive of a release
# leaves these out (.gitattributes' export-ignore), so they are never deployed (T25, D4).
readonly PLUGIN_FILES_LEFT_OUT_OF_DOWNLOAD=(.gitattributes .github composer.lock phpcs.xml.dist phpstan.neon.dist)

# Each of those paths is export-ignore, as git reads .gitattributes (GitHub builds its archive with
# git); needs the plugin's folder to be a git repository.
plugin_download_problems() {
  local plugin_dir="$1" path
  for path in "${PLUGIN_FILES_LEFT_OUT_OF_DOWNLOAD[@]}"; do
    [[ "$(git -C "$plugin_dir" check-attr export-ignore -- "$path" 2>/dev/null)" == "$path: export-ignore: set" ]] ||
      printf '.gitattributes: %s is not export-ignore, so the release download would carry it\n' "$path"
  done
  return 0
}

# Every file rule, then the tag's when one is given.
plugin_rules_problems() {
  local plugin_dir="$1" tag="${2:-}"
  plugin_composer_problems "$plugin_dir"
  plugin_main_file_problems "$plugin_dir"
  plugin_header_problems "$plugin_dir"
  plugin_changelog_problems "$plugin_dir"
  [[ -z "$tag" ]] || plugin_tag_problems "$plugin_dir" "$tag"
}
