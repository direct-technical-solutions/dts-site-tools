# Changelog

What changed in each release, for the sites that use the tools. Each release names every new or
changed `site.json` field, and every change to what `bin/check` gives a site's own checks
(`tests/checks/*.sh`). The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions follow [Semantic Versioning](https://semver.org/), where below 1.0 a minor version may
change how a site calls the tools.

## [Unreleased]

### Added

- The shared workflows a site calls, pinned by commit: `site-check.yml` (the `check` and
  `dev-site` jobs), `site-versions.yml` and `site-plugin-updates.yml`. Each installs the tools
  from the site's `composer.lock` first, giving Composer the run's read-only token.
- `bin/tools-pin`: writes the site's `check.yml`, `versions.yml` and `plugin-updates.yml` workflows
  from `tools/site-workflows/`, pinned to the commit of the tools release `composer.lock` installs.
- `bin/check`, in a site that installs the tools: the site's three workflows must be exactly what
  `bin/tools-pin` writes. A site switching to this release runs `bin/tools-pin` and commits its
  three files; the required checks' names on GitHub change with them.
- The install command for a fresh clone, in the README.
- The self-check: every command in `bin/` is one Composer installs into a site (`composer.json`'s
  `bin`), apart from the tools repository's own `bin/tools-update`.

### Fixed

- `bin/tools-pin` is installed into a site's `bin/` (it was missing from `composer.json`'s `bin`).
- A new `.env` names the dev site's shared Compose file where the tools are installed
  (`vendor/dts/site-tools/compose.dev.yaml` in a site), so hand-typed `docker compose` commands
  find it. An existing `.env` keeps its line: a site switching to this release changes its
  `COMPOSE_FILE` by hand.

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
