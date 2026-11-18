Rendered site: https://rh-aiservices-bu.github.io/CAI-Field-Manual-Hello-World/

# CAI Field Manual — Shell (chrome / rules module)

This repo is a **Hugo module** that provides the chrome and rules consumed by
content repos (e.g.
[`CAI-Field-Manual-Hello-World`](https://github.com/rh-aiservices-bu/CAI-Field-Manual-Hello-World))
via `hugo.yaml` → `module.imports`. It is **not a site** and has no GitHub
Pages deploy — the rendered site lives in the content repo.

## Prerequisites

- Hugo Extended ≥ 0.168.
- **Dart Sass on `PATH`** — `layouts/_partials/head-css.html` sets
  `transpiler: dartsass`; Hugo Extended does **not** bundle Dart Sass
  ([`oink` comment `head-css.html:2-3`](https://github.com/pgsty/oink/blob/main/layouts/_partials/head-css.html#L2)).
  Install with `brew install sass/sass/sass`, `npm i -g sass`, or
  `snap install dart-sass`. Without it the build fails before the publication
  gate's WARN filter runs.

## What it exports

**Layout overrides** (Hugo mounts merge these into the importing site):

- Pinned oink v1.4.0 overrides — layout/html files carry provenance comments
  naming their deliberate changes. Re-diff all eight against
  `~/go/pkg/mod/github.com/pgsty/oink@v<ver>/` on a theme bump:
  - `layouts/_partials/shell/sidebar-tree.html` — Home + `sidebar_root_for: self` promoted to tree's top level (`ul--1`/`ulNr 1`); small-screen `d-md-none` cover row is `IsHome`-only (self-roots already have the always-visible `td-shell-root--static` selector in the header)
  - `layouts/_partials/pager-state.html` — pager rooted at the page's own section
  - `layouts/_partials/head-css.html` — switches to `transpiler: dartsass` (silences oink/Bootstrap `libSass` `@import` deprecations), fixes RTL `Integrity` scoping
  - `layouts/_partials/actions/context.html` — open_gemini + feed_agent rows (feed_agent gated on `params.github_repo`)
  - `layouts/_partials/actions/title-menu.html` — open_gemini + feed_agent rows (feed_agent gated on `params.github_repo`)
  - `assets/js/action-registry.js` — open_gemini + feed_agent action kinds *(pinned, no provenance header)*
  - `assets/js/page-actions.js` — open_gemini + feed_agent bindings *(pinned, no provenance header)*
- Sanctioned extension points — not copies, free to edit (the theme ships both hooks empty):
  - `layouts/_partials/td-variant-selector.html`
  - `layouts/_partials/hooks/head-end.html` (page-top selector + pre-paint persistence runtime)
  - `layouts/_partials/hooks/body-end.html` (chat + agent-setup injection)
  - `layouts/_shortcodes/customize.html` + `layouts/_shortcodes/customize-form.html`
  - `layouts/_shortcodes/variant.html`
  - `layouts/_shortcodes/feedback-demo.html`
- Shell fixup (not upstream): `layouts/_partials/favicons.html` — hardcodes
  Shell's known favicons so the split site still emits `<link rel="icon">`
  tags (upstream's `os.ReadDir "static"` probe misses module `static/`).
  Re-diff on theme bump is not needed; if you add/remove favicons in
  `static/`, update this file to match.
- Dart Sass compat overlay (not upstream): `assets/scss/td/_chroma.scss` + `assets/scss/td/chroma/_dark-wrapped.scss` — hoists oink's nested `@import 'chroma/dark'` out of its `@if/@selector` wrapper, which LibSass tolerated but Dart Sass rejects. The overlay is paired with `head-css.html`'s `dartsass` switch; drop both when upstream migrates to `@use`.
- `assets/js/agent-setup.js` + `assets/css/agent-setup.css` — the *Feed it to my AI Agent* copy-prompt modal
- `assets/js/chat.js` + `assets/css/chat.css` — the chat assistant runtime
- `assets/icons/logo-rh-cai.svg` + `assets/scss/_styles_project.scss` (nav, header, layout)
- `layouts/_partials/google_analytics.html` — GA4 partial (the theme's head.html calls it in production)
- `static/favicon*`, `static/apple-touch-icon.png`

**Scripts**:

- `scripts/publication-gate.sh` — runs in content repos' CI via a `shell/` checkout.
- `scripts/check-contracts.sh` — a local gate (add it to CI to enforce): validates dual-consumption contracts against
  the built `public/` (variant axes/options, customize tokens, variant labels,
  status-gate fences).

## How a content repo consumes it

```yaml
# content repo's hugo.yaml
module:
  imports:
    - path: github.com/rh-aiservices-bu/CAI-Field-Manual-Shell
      # Pinned to Shell commit 4968e45a45d7 on main; bump by editing this hash.
      version: 4968e45a45d7
  hugoVersion:
    extended: true
    min: 0.168.0
```

Update the shell — pin a specific commit, don't float to latest:

```sh
# 1) bump the pin in content repo's hugo.yaml (version: <sha>)
hugo mod get github.com/rh-aiservices-bu/CAI-Field-Manual-Shell@<sha>
hugo mod tidy
```

Verify `hugo mod graph` still shows `github.com/pgsty/oink v1.4.0` and that
`hugo.yaml:version` matches the `go.mod`/`go.sum` hash. Do not use `-u`
here — it upgrades transitive deps.

Content repo CI must install Dart Sass before the publication gate (see content repo's `.github/workflows/github-pages.yaml` — both `build` and `pr-gate` jobs):

```yaml
      - name: Install Dart Sass
        run: npm install -g sass   # or brew / snap equivalent on self-hosted
```

Without this the `head-css.html` override's `transpiler: dartsass` has no
binary and the build errors before WARN filtering.

## Verifying shell changes locally

Shell changes are proven by building the Hello-World site against this working
tree (the Shell repo has no own build). From a sibling clone of
`CAI-Field-Manual-Hello-World`, create `hugo.work` containing:

```
go 1.27.3

use .

replace github.com/rh-aiservices-bu/CAI-Field-Manual-Shell => ../CAI-Field-Manual-Shell
```

Then build from the Hello-World repo root with the workspace active:

```sh
export HUGO_MODULE_WORKSPACE=hugo.work
hugo --cleanDestinationDir --gc --minify --environment production --printPathWarnings 2>&1 | grep -E '^WARN' | grep -v "css.Sass: libsass"
sh ../CAI-Field-Manual-Shell/scripts/check-contracts.sh
unset HUGO_MODULE_WORKSPACE
```

Verify `sass --version` prints a Dart Sass version before running — the gate
needs it on this machine too. Then verify with `hugo mod graph` and
`hugo config` that the replacement is active.
`hugo.work` is gitignored — never commit it.

## Disclaimers

- **Orientation, not a support statement.** Commands and versions reflect
  what worked during field work when the manual was written; verify against
  the current official product documentation before relying on them.
- **Not official product documentation.** These are field notes from
  prototypes, maintained by project contributors.
- **Prototype.** Structure, pages, and URLs are under development and may
  change or move.
