# OpaqueDB Documentation

Documentation for [OpaqueDB](https://github.com/opaquedb/opaquedb), built with
[MkDocs](https://www.mkdocs.org/) and
[Material for MkDocs](https://squidfunk.github.io/mkdocs-material/).

## Develop locally

All common tasks live in the [`Makefile`](Makefile). Run `make` (or `make help`)
to list them:

```sh
make install   # create .venv and install dependencies
make serve     # live preview at http://127.0.0.1:8000
make build     # render the static site into site/
make clean     # remove the built site and caches
make deploy    # build and deploy to Cloudflare Pages
```

`make install` creates a `.venv/` virtual environment and installs
`requirements.txt` into it; the other targets use that environment.

> **Versions are pinned.** `requirements.txt` stays on `mkdocs-material` 9.6.x
> and `mkdocs` < 2.0. Material 9.7+ prints a "MkDocs 2.0" deprecation banner on
> every build, and MkDocs 2.0 itself drops the plugin system and theming the
> Material theme depends on.

## Layout

```
Makefile          common tasks (install, serve, build, deploy)
mkdocs.yml        site config and navigation
requirements.txt  Python dependencies (pinned)
wrangler.toml     Cloudflare Pages output config
docs/             Markdown sources, one file per nav entry
docs/assets/      images
```

Edit the Markdown under `docs/`, then update the `nav` in `mkdocs.yml` if you
add or rename a page.

A `.devcontainer/` is included. Open this folder in a dev container (or GitHub
Codespaces) to get Python with the dependencies installed; then run
`make serve`.

## Deploy to Cloudflare Pages

This site deploys to Cloudflare Pages as a static build.

### From your machine

`make deploy` builds the site and runs
`wrangler pages deploy site --project-name opaquedb-docs`. Wrangler is invoked
via `npx`, so it needs Node.js available and authentication — either run
`npx wrangler login` once, or set `CLOUDFLARE_API_TOKEN` (and
`CLOUDFLARE_ACCOUNT_ID`) in your environment.

### From the Cloudflare dashboard (CI build)

Alternatively, connect the repository in the Cloudflare dashboard and let
Cloudflare build it:

| Setting | Value |
| --- | --- |
| Build command | `pip install -r requirements.txt && mkdocs build` |
| Build output directory | `site` |
| Environment variable | `PYTHON_VERSION = 3.12` |

`wrangler.toml` pins the output directory (`pages_build_output_dir = "site"`).
If you keep this site in a subdirectory of a larger repo, set the Pages root
directory to that subdirectory.
