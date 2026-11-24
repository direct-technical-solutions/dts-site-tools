# Changelog

What changed in each release, for the sites that use the tools. Each release names every new or
changed `site.json` field, and every change to what `bin/check` gives a site's own checks
(`tests/checks/*.sh`). The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions follow [Semantic Versioning](https://semver.org/), where below 1.0 a minor version may
change how a site calls the tools.

## [Unreleased]

## [0.1.0] - 2026-11-24

### Added

- The tools as first used by the site they were built in: `bin/dev-site`, `bin/test`,
  `bin/check`, `bin/deploy`, `bin/site-check`, `bin/accessibility-scan`, `bin/screenshots` and
  `bin/versions-check`, with their helpers in `tools/`, the dev site's recipe, and the shared
  browser and scenario tests.
- `site.json`'s fields as described in `tools/site-settings.md`.
- A site's own checks: `bin/check` loads each `tests/checks/*.sh` of the site in name order; each
  calls `run_check` from `tools/check-lib.sh`, with `TOOLS_DIR`, `PROJECT_DIR` and `SITE_DIR` set.
- The PHP checkers at exact versions: PHP_CodeSniffer 3.13.6, WordPress Coding Standards 3.4.1,
  PHPCSUtils 1.2.3, PHPCSExtra 1.5.1, PHPStan 2.3.5, PHPStan for WordPress 2.0.4 and the
  WordPress stubs 7.1.2.

[Unreleased]: https://github.com/direct-technical-solutions/dts-site-tools/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/direct-technical-solutions/dts-site-tools/releases/tag/v0.1.0
