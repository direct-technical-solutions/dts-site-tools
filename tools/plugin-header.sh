#!/usr/bin/env bash
# Reading a WordPress plugin's main file header, as WordPress reads it (the file's first 8 KB):
# which file it is, the version it names, and whether it keeps WordPress.org from updating it.
# Used for the plugins a site downloads (tools/site-packages.sh), a site's own plugins (bin/check)
# and a DTS plugin's own repository (tools/plugin-rules.sh). Sourced, never run.

# A plugin's main file in its folder: the top-level PHP file whose header names the plugin, as
# WordPress finds it (it reads a file's first 8 KB for the header).
plugin_main_file() {
  local plugin_dir="$1" php_file
  for php_file in "$plugin_dir"/*.php; do
    [[ -f "$php_file" ]] || continue
    head -c 8192 "$php_file" | grep -qE '^[[:space:]*#@/]*Plugin Name:' && { printf '%s' "${php_file##*/}"; return 0; }
  done
  return 1
}

# The Version in a plugin main file's header; nothing when it has none.
plugin_header_version() {
  local main_file="$1"
  head -c 8192 "$main_file" | sed -nE 's/^[[:space:]*#@/]*Version:[[:space:]]*([^[:space:]]+).*$/\1/p' | head -n 1
}

# Succeeds when the main file declares "Update URI: false". Without it WordPress would offer a
# WordPress.org plugin of the same name as an update and replace the site's code with a
# stranger's (plan step 8b).
plugin_never_updated_from_wordpress_org() {
  local main_file="$1"
  grep -qE '^ \* Update URI: +false$' "$main_file" 2>/dev/null
}
