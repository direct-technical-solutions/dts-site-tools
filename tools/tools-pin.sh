#!/usr/bin/env bash
# The workflows that call the tools' reusable workflows (template plan 2.1c, T18, T22, T26), in a
# site's repository or a DTS plugin's, written from the templates for that kind of repository
# (tools/site-workflows/ or tools/plugin-workflows/) with the commit of the tools release its
# composer.lock installs, so the workflows' pin and Composer's pin name the same code.
# bin/tools-pin writes them; bin/check (a site) and bin/plugin-check (a plugin) compare the files
# with what bin/tools-pin would write, which catches a commit left behind (Dependabot raises the
# Composer pin, never a reusable workflow's commit: findings of template plan 2.1b-1) and a hand
# edit alike. Sourced, never run; the sourcing script defines TOOLS_DIR. Needs jq, sed and cmp.

readonly TOOLS_PACKAGE_NAME="dts/site-tools"
readonly SITE_WORKFLOW_TEMPLATES_DIR="$TOOLS_DIR/tools/site-workflows"
readonly PLUGIN_WORKFLOW_TEMPLATES_DIR="$TOOLS_DIR/tools/plugin-workflows"
# Composer's package type for a WordPress plugin, which composer/installers places in
# wp-content/plugins/; a repository whose composer.json has it is a plugin's.
readonly WORDPRESS_PLUGIN_PACKAGE_TYPE="wordpress-plugin"
# A full commit only: a short one could later match a second commit.
readonly TOOLS_COMMIT_PATTERN='^[0-9a-f]{40}$'
# The version is written into a comment beside the commit, for people; a release such as v0.2.0,
# or a branch such as dev-main while a tools change is tried on a site before its release. Limited
# to characters that cannot break the YAML line or the substitution.
readonly TOOLS_VERSION_PATTERN='^[A-Za-z0-9._/-]+$'

# Prints "<commit> <version>" of the tools release a composer.lock installs, or a message naming
# the problem on stderr and fails.
tools_pin_locked_release() {
  local lock_file="$1" release
  [[ -f "$lock_file" ]] || { printf '%s: no such file\n' "$lock_file" >&2; return 1; }
  jq empty "$lock_file" 2>/dev/null || { printf '%s: not JSON\n' "$lock_file" >&2; return 1; }
  release="$(jq -r --arg name "$TOOLS_PACKAGE_NAME" \
    '[(.packages // [])[], (."packages-dev" // [])[] | select(.name == $name)][0] // empty
     | "\(.source.reference // "") \(.version // "")"' "$lock_file" 2>/dev/null)" ||
    { printf '%s: not shaped like a Composer lock file (its package lists)\n' "$lock_file" >&2; return 1; }
  [[ -n "$release" ]] || { printf '%s: does not install %s\n' "$lock_file" "$TOOLS_PACKAGE_NAME" >&2; return 1; }
  tools_pin_release_is_valid "$lock_file" "${release%% *}" "${release#* }" || return 1
  printf '%s\n' "$release"
}

tools_pin_release_is_valid() {
  local lock_file="$1" commit="$2" version="$3"
  [[ "$commit" =~ $TOOLS_COMMIT_PATTERN ]] ||
    { printf '%s: %s has no full commit ("%s")\n' "$lock_file" "$TOOLS_PACKAGE_NAME" "$commit" >&2; return 1; }
  [[ "$version" =~ $TOOLS_VERSION_PATTERN ]] ||
    { printf '%s: %s has an unexpected version ("%s")\n' "$lock_file" "$TOOLS_PACKAGE_NAME" "$version" >&2; return 1; }
}

# Prints the templates folder for the repository given: a plugin's when its composer.json is of
# the WordPress plugin type, a site's otherwise.
tools_pin_templates_dir_of() {
  local repository_dir="$1"
  if [[ "$(jq -r '.type // ""' "$repository_dir/composer.json" 2>/dev/null)" == "$WORDPRESS_PLUGIN_PACKAGE_TYPE" ]]; then
    printf '%s\n' "$PLUGIN_WORKFLOW_TEMPLATES_DIR"
    return 0
  fi
  printf '%s\n' "$SITE_WORKFLOW_TEMPLATES_DIR"
}

# Prints one template with the release filled in. The commit and version were checked against
# their patterns, so neither can hold the substitution's delimiter or a line break.
tools_pin_render() {
  local template="$1" commit="$2" version="$3"
  sed -e "s|__TOOLS_COMMIT__|$commit|g" -e "s|__TOOLS_VERSION__|$version|g" "$template"
}

# Writes every template of the folder given into the repository's workflows folder; each file is
# written whole and then moved into place, so an interrupted run leaves no half-written workflow.
tools_pin_write() {
  local templates_dir="$1" workflows_dir="$2" commit="$3" version="$4" template target
  mkdir -p "$workflows_dir"
  for template in "$templates_dir"/*.yml; do
    target="$workflows_dir/$(basename "$template")"
    tools_pin_render "$template" "$commit" "$version" >"$target.tools-pin" && mv "$target.tools-pin" "$target"
  done
}

# Prints one line per caller (a template of the folder given) that is missing or differs from what
# bin/tools-pin writes for the release, starting with the file's name and a colon; nothing when
# every one matches. The repository's other workflows are not the tools' concern.
tools_pin_differences() {
  local templates_dir="$1" workflows_dir="$2" commit="$3" version="$4" template name
  for template in "$templates_dir"/*.yml; do
    name="$(basename "$template")"
    if [[ ! -f "$workflows_dir/$name" ]]; then
      printf '%s: missing\n' "$name"
    elif ! cmp -s <(tools_pin_render "$template" "$commit" "$version") "$workflows_dir/$name"; then
      printf '%s: differs from what bin/tools-pin writes for %s (%s)\n' "$name" "$version" "${commit:0:7}"
    fi
  done
}
