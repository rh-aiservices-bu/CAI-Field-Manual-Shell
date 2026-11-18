Rendered site: https://rh-aiservices-bu.github.io/CAI-Field-Manual-Hello-World/

# CAI Field Manual — Shell (chrome / rules module)

This repo is a **Hugo module** that provides the chrome and rules consumed by
content repos (e.g.
[`CAI-Field-Manual-Hello-World`](https://github.com/rh-aiservices-bu/CAI-Field-Manual-Hello-World))
via `hugo.yaml` → `module.imports`. It is **not a site** and has no GitHub
Pages deploy — the rendered site lives in the content repo.

## What it exports

**Layout overrides** (Hugo mounts merge these into the importing site):

- Pinned copies of oink v1.4.0 files — each headed by a provenance comment naming
  each of its deliberate changes (page-top selector call; Home promoted to the tree's
  top level with a small-screen Home row; pager rooted at the page's own section
  instead of the site root). Re-diff all seven against
  `~/go/pkg/mod/github.com/pgsty/oink@v<ver>/` on a theme bump:
  - `layouts/docs/baseof.html` — page-top selector call before version banner
  - `layouts/_partials/shell/sidebar-tree.html` — Home promoted to tree's top level with small-screen Home row
  - `layouts/_partials/pager-state.html` — pager rooted at the page's own section
  - `layouts/_partials/actions/context.html` — open_gemini + feed_agent rows (feed_agent gated on `params.github_repo`)
  - `layouts/_partials/actions/title-menu.html` — open_gemini + feed_agent rows (feed_agent gated on `params.github_repo`)
  - `assets/js/action-registry.js` — open_gemini + feed_agent action kinds
  - `assets/js/page-actions.js` — open_gemini + feed_agent bindings
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
  hugoVersion:
    extended: true
    min: 0.168.0
```

Update the shell:

```sh
hugo mod get github.com/rh-aiservices-bu/CAI-Field-Manual-Shell
hugo mod tidy
```

Then verify `hugo mod graph` still shows `github.com/pgsty/oink v1.4.0` (the pinned theme); do not use `-u` here — it upgrades transitive deps.

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
hugo --cleanDestinationDir --gc --minify --environment production --printPathWarnings
hugo --cleanDestinationDir --gc --minify --environment production --printPathWarnings 2>&1 | grep -i warn | grep -v "css.Sass: libsass"
sh ../CAI-Field-Manual-Shell/scripts/check-contracts.sh
unset HUGO_MODULE_WORKSPACE
```

Verify with `hugo mod graph` and `hugo config` that the replacement is active.
`hugo.work` is gitignored — never commit it.

## Disclaimers

- **Orientation, not a support statement.** Commands and versions reflect
  what worked during field work when the manual was written; verify against
  the current official product documentation before relying on them.
- **Not official product documentation.** These are field notes from
  prototypes, maintained by project contributors.
- **Prototype.** Structure, pages, and URLs are under development and may
  change or move.
