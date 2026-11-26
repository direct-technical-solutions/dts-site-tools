# Changelog

What changed in each release, for the sites that use the tools. Each release names every new or
changed `site.json` field, and every change to what `bin/check` gives a site's own checks
(`tests/checks/*.sh`). The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions follow [Semantic Versioning](https://semver.org/), where below 1.0 a minor version may
change how a site calls the tools.

## [Unreleased]

## [0.3.1] - 2026-11-26

### Changed

- `bin/deploy`'s messages made simple to read: five sections (what goes out; the downloaded
  plugins; what rsync will change, before "yes"; what rsync changed; after the copy), each a
  header with its time and source and its lines indented. rsync's lists are one list, each line
  naming the file by its path under `wp-content/` (`--out-format='%i %o <folder path>/%n'`
  replaces `--itemize-changes`), under one line naming every folder compared, and
  `no file will change` when nothing does. Git's full list is gone: git is a one-line
  cross-check of rsync's list for the site's own code, or names each file only one side lists.
  The downloaded plugins' section says whether their pins changed since the place's commit, and
  the plugins whose every file matches share one line.
- `bin/deploy`'s tested-commit line no longer says "by squash or rebase": GitHub does not record
  a pull request's merge method, and the proof, the same files as its tested last commit, does
  not need one.

## [0.3.0] - 2026-11-26

### Changed

- `bin/deploy`'s messages come straight from git and rsync. Before "yes": what git says changed
  in the site's own code since the commit the server's note names, and rsync's dry run of
  exactly the copy that follows, folder by folder, with one line when the two disagree about the
  site's own code. After "yes": rsync's own list for each folder and whether it matches the
  preview. The per-folder change counts and the `copies, in order` line are gone.
- `bin/deploy` no longer copies file times (`-t`), so a file with the same content is neither
  listed nor touched. Each file it does copy gets the time of the copy on the server.
- `bin/deploy` makes a second dry run after the copy, and stops without writing the note when it
  still lists anything.
- The tested-commit line says the pull request was merged by squash or rebase, and that the
  merge made a new commit with the same files as its tested last commit.
- `site-plugin-updates.yml` merges Dependabot's plugin updates by squash (it rebased), passing
  Dependabot's own commit message and binding the merge to the head commit it checked; a pull
  request with more than one commit waits for review. **A site switching to this release must
  allow squash merges** in its repository's settings, or its plugin updates stop merging
  themselves.
- The README names the trap in a site that once committed its own `bin/`, and its fix.
- PHPStan 2.3.6 (was 2.3.5), and the CSS linter's `@stylistic/stylelint-plugin` 6.0.1 (was
  6.0.0).

### Fixed

- `bin/tools-update` runs in the tools' own repository again: it looked for a site's
  `site.json` and refused there. It now works on the tools' folder alone, refuses an installed
  copy (no `.git`), and shares the self-check's caches; its safeguards are unchanged. The
  self-check tests it with a stand-in Docker.
- `bin/check`'s message for a missing `composer.lock` no longer sends a site to
  `bin/tools-update`, which a site does not have.

## [0.2.0] - 2026-11-24

### Added

- The shared workflows a site calls, pinned by commit: `site-check.yml` (the `check` and
  `dev-site` jobs), `site-versions.yml` and `site-plugin-updates.yml`. Each installs the tools
  from the site's `composer.lock` first, giving Composer the run's read-only token.
- `bin/tools-pin`: writes the site's `check.yml`, `versions.yml` and `plugin-updates.yml` workflows
  from `tools/site-workflows/`, pinned to the commit of the tools release `composer.lock` installs.
- `bin/check`, in a site that installs the tools: the site's three workflows must be exactly what
  `bin/tools-pin` writes. A site switching to this release runs `bin/tools-pin` and commits its
  three files; the required checks' names on GitHub change with them.

### Changed

- `bin/deploy` requires the checks `check / check` and `check / dev-site`, the names GitHub gives
  the shared workflow's jobs when a site calls it (it required `check` and `dev-site`). A site
  switching to this release sets its branch protection to the new names; a commit tested only
  under the old names is refused until its checks run again.
- The install command for a fresh clone, in the README.
- The self-check: every command in `bin/` is one Composer installs into a site (`composer.json`'s
  `bin`), apart from the tools repository's own `bin/tools-update`.

### Fixed

- `bin/tools-pin` is installed into a site's `bin/` (it was missing from `composer.json`'s `bin`).
- The deploy tests work on their own stand-in site even when run from a site's `bin/test`: they
  cleared GitHub's tokens but not `COMPOSER_RUNTIME_BIN_DIR` or `SITE_DIR`, so `bin/deploy` worked
  on the real site and refused its commit.
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

[Unreleased]: https://github.com/direct-technical-solutions/dts-site-tools/compare/v0.3.1...HEAD
[0.3.1]: https://github.com/direct-technical-solutions/dts-site-tools/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/direct-technical-solutions/dts-site-tools/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/direct-technical-solutions/dts-site-tools/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/direct-technical-solutions/dts-site-tools/releases/tag/v0.1.0
