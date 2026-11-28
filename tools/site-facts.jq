# The rules for a theme's site-facts.json (template plan 2.4b-2, T31): the site's facts that the
# shared theme code reads (its old addresses, its organization's types, the towns it serves, the
# outside sources its pages need), each field's type, whether it is required, and for text the
# form it must have. Checked by the same engine as site.json (rules_problems_at in
# tools/site-settings.jq). Loaded with `jq -L tools 'include "site-facts"; ...'`.
#
# The theme reads the file on every page load and leaves a fact it cannot use at its default
# (Dtstheme_Site_Facts); these rules are stricter, so a mistake is found before a commit, named,
# instead of showing on a server as a missing redirect or a blocked frame.
include "site-settings";

# Every entry says why it is there: JSON has no comments, and a reason left out or gone stale is
# what a comment cannot be checked for.
def site_facts_reason_rules: {
  type: "string", required: true, pattern: "\\S", patternMeaning: "the reason for this entry, in words"
};

# A page's path as WordPress's request names it (no slashes at the ends; lower case, since the
# theme compares the request in lower case): an address with capitals would never match.
def site_facts_path_rules: {
  type: "string", required: true,
  pattern: "^[a-z0-9]([a-z0-9_/-]*[a-z0-9])?$",
  patternMeaning: "a page's path without slashes at the ends: lower-case letters, digits, dashes, underscores and inner slashes, such as old-page or parent/child"
};

def site_facts_rules: {
  type: "object",
  fields: {
    oldAddresses: {
      type: "array", required: true,
      items: {
        type: "object",
        fields: { from: site_facts_path_rules, to: site_facts_path_rules, reason: site_facts_reason_rules }
      }
    },
    organizationTypes: {
      type: "object", required: true,
      fields: {
        # schema.org's type names: capitalized words run together, such as LocalBusiness.
        types: { type: "array", required: true, items: { type: "string", pattern: "^[A-Z][A-Za-z]*$", patternMeaning: "a schema.org type name, such as Organization or LocalBusiness" } },
        reason: site_facts_reason_rules
      }
    },
    areasServed: {
      type: "object", required: true,
      fields: {
        towns: { type: "array", required: true, items: { type: "string", pattern: "\\S", patternMeaning: "a town's name as the page text names it, such as 'Town, State'" } },
        reason: site_facts_reason_rules
      }
    },
    outsideSources: {
      type: "array", required: true,
      items: {
        type: "object",
        fields: {
          # The directives and the source's form that the Site Hardening plugin accepts
          # (SITEHARDENING_CSP_EXTENSIBLE_DIRECTIVES and SITEHARDENING_CSP_SOURCE_PATTERN in its
          # includes/security-headers.php): anything else it drops, so the page that needed it
          # would break on the server with nothing named.
          directive: { type: "string", required: true, allowedValues: ["script-src", "style-src", "img-src", "font-src", "connect-src", "frame-src"] },
          source: { type: "string", required: true, pattern: "^https://[a-z0-9.-]+(:[0-9]{1,5})?(/[A-Za-z0-9._~/-]*)?$", patternMeaning: "an https:// address: a lower-case host, optionally a port and a path, such as https://www.youtube.com" },
          reason: site_facts_reason_rules
        }
      }
    }
  }
};

# Rules across entries, which the field-by-field rules cannot see. Each checked only where the
# field has the right type; its own rules report anything else.
# - Yoast SEO builds the organization's piece as an Organization; the theme replaces its type with
#   this list, so leaving Organization out would drop it.
# - Each old address redirects to one page: a second entry for the same address would be ignored.
def site_facts_cross_problems:
  (.organizationTypes?.types? // null) as $types
  | (.oldAddresses? // null) as $old_addresses
  | (if ($types | type) == "array" and ($types | index("Organization") | not) then
       "organizationTypes.types: must include \"Organization\", Yoast SEO's own type"
     else empty end),
    (if ($old_addresses | type) == "array" then
       $old_addresses | to_entries | map(select(.value | type == "object"))
       | group_by(.value.from)[] | select(length > 1)
       | "oldAddresses[\(.[1].key)].from: \(.[0].value.from | tojson) is already oldAddresses[\(.[0].key)].from; each old address redirects to one page"
     else empty end);

def site_facts_problems: rules_problems_at(site_facts_rules; ""; "site-facts.json"), site_facts_cross_problems;
