# dts-site-tools

The commands that check, test and deploy a WordPress site built by Direct Technical Solutions:
a local dev site, static checks, browser and scenario tests, the deploy to staging and live, and
the page and accessibility checks. They run on the developer's computer and in GitHub Actions;
they are never installed on the website.

## Using them in a site

A site requires the tools through Composer, at an exact version, with its commands placed in the
site's own `bin/` (both `vendor/` and `bin/` ignored by the site's git):

```json
{
    "repositories": [
        { "type": "vcs", "url": "https://github.com/direct-technical-solutions/dts-site-tools" }
    ],
    "require-dev": { "dts/site-tools": "0.1.0" },
    "config": {
        "bin-dir": "bin",
        "allow-plugins": { "dealerdirect/phpcodesniffer-composer-installer": true }
    }
}
```

After a fresh clone, and after each change to `composer.lock`, the site installs the tools with
Composer in its pinned container (the same command the shared workflows run):

```sh
mkdir -p vendor bin && docker run --rm -w /app -v "$PWD/composer.json:/app/composer.json:ro" -v "$PWD/composer.lock:/app/composer.lock:ro" -v "$PWD/vendor:/app/vendor" -v "$PWD/bin:/app/bin" composer:2.11.1 composer install --no-interaction --no-progress
```

The site's GitHub workflows (`check.yml`, `versions.yml`, `plugin-updates.yml`) are a few lines
each, calling the shared ones in `.github/workflows/site-*.yml` pinned by commit. `bin/tools-pin`
writes them from `tools/site-workflows/` for the release `composer.lock` installs; `bin/check`
fails when they differ from what it writes. After a tools update (Dependabot raises the Composer
pin, never the workflows' commit), `bin/tools-pin` is run on the update's branch and its three
files committed there. The required checks, in the site's branch protection and for `bin/deploy`,
are the shared workflow's two jobs as GitHub names them when called: `check / check` and
`check / dev-site`.

The site describes itself in `site.json` (each field explained in
[`tools/site-settings.md`](tools/site-settings.md)). What each command does:
[`docs/TOOLS.md`](docs/TOOLS.md). The commands need Docker and `jq`; `bin/deploy` also needs
`git`, `gh`, `rsync`, `ssh`, `curl` and `flock`.

## Working on the tools

`tests/tools/check-tools.sh` is the tools' self-check, run by the `check` workflow on every pull
request and weekly. A change is proven on a real dev site by a site that uses it before it is
released. Releases are Git tags (`v0.1.0`), never moved once published; what changed, and above
all any new `site.json` field, is in [`CHANGELOG.md`](CHANGELOG.md). Versions below 1.0 may still
change how a site calls the tools.

## License

GPL-2.0-or-later, as WordPress. See [`LICENSE`](LICENSE).
