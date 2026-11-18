# Repository Guidance — Shell (chrome / rules module)

This repo is a **Hugo module** consumed by content repos (e.g.
`CAI-Field-Manual-Hello-World`) for look-and-feel and build rules. It has no
own build — Shell changes are proven by building the Hello-World site against
this working tree via the `hugo.work` replacement described in README.md.

Content rules (manuals, writing doctrine, variant/customize conventions) live
in `CAI-Field-Manual-Hello-World`'s `AGENTS.md`.

## Before you declare a shell change done: the publication gate

The gate runs in **content repos' CI** as `shell/scripts/publication-gate.sh`
(the content repo checks out this repo at `shell/` and runs the gate there).
Locally, prove a shell change the same way — from a sibling clone of
`CAI-Field-Manual-Hello-World` with a `hugo.work` replacement:

```
go 1.27.3

use .

replace github.com/rh-aiservices-bu/CAI-Field-Manual-Shell => ../CAI-Field-Manual-Shell
```

Then from the Hello-World repo root:

```sh
HUGO_MODULE_WORKSPACE=hugo.work hugo --cleanDestinationDir --gc --minify --environment production \
  --printPathWarnings 2>&1 | grep -i warn | grep -v "css.Sass: libsass"
```

No output = clean. Build failure or any other WARN = not done. Fix and re-run.
`hugo.work` is gitignored — never commit it.

Changes to `scripts/publication-gate.sh` or `scripts/check-contracts.sh`
themselves are validated by Hello-World's build (which runs the updated scripts).

## Do not touch without re-diffing

Files under `layouts/` and `assets/js/` marked as pinned oink v1.4.0 copies
(`layouts/docs/baseof.html`, `layouts/_partials/shell/sidebar-tree.html`,
`layouts/_partials/pager-state.html`, `assets/js/action-registry.js`,
`assets/js/page-actions.js`, `layouts/_partials/actions/context.html`,
`layouts/_partials/actions/title-menu.html`) each carry a provenance comment
naming its one deliberate change. Any edit beyond that change requires
re-diffing against `~/go/pkg/mod/github.com/pgsty/oink@v1.4.0/`.
Sanctioned extension points (free to edit): `td-variant-selector.html`,
`hooks/head-end.html`, `hooks/body-end.html`, the customize shortcodes,
`static/js/`, `static/css/`, `hugo.yaml`, `assets/scss/_styles_project.scss`.

## Verification for JS changes

Interactive behavior lives in `static/js/` and `assets/js/`. If you change it,
verify the rendered page actually works (dev server + browser against the
Hello-World site via `hugo.work`), not just that the build passes.

