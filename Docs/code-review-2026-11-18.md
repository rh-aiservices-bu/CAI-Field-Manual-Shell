# Code Review — CAI-Field-Manual-Shell (2026-11-18)

> Scope: full working tree at `ea45b4a` (main). Five reviewer slices were fanned out (layouts, JS, config/build, scripts/CI, security) at T+0 and were **still running at T+4m+ when this document was authored** — none had delivered a final output (verified via `proc://` and `agent://`/`history://` reads). **This document is therefore a single-pass review by the integration session, not an integration of sub-agent findings.** When sub-agents deliver, their findings must be merged and explicitly attributed (or deltas noted). No behavioral changes were made.

---

## Summary

| Severity | Count | Meaning |
|----------|------:|---------|
| 🟠 Medium | 11 | Should-fix, low risk to defer one cycle |
| 🟡 Low | 10 | Polish / hygiene |
| **Total** | **21** | |

The repo is in good shape: XSS posture is solid, shell scripts are well-commented, and the variant/customize system is unusually careful for a docs theme. Most findings are edge cases, stale docs, or hardening.

Corrections from the prior draft (which erroneously implied sub-agent coverage):
- **H-1 (withdrawn):** `customize.html:44` `data-td-customize-default="{{ $field.default }}"`, `customize-form.html:59` `value="{{ .default }}"`, `td-variant-selector.html:26` `title="{{ .label }}"` are in `html/template` HTML-attribute context and are **auto-escaped by Go's contextual escaper**. Piping through `| htmlEscape` risks double-escaping; `hugo.yaml` `params.customize` is first-party content, not an attacker-controlled XSS boundary. Withdrawn as a High; noted here for the record.
- **H-2 → M-3 (demoted + corrected):** `scripts/check-contracts.sh:44` `if ! grep -qE "^    - id: $axis\$" hugo.yaml; then echo … fail=1` does **not** silently pass on reformat — it **loudly false-fails** (every variant pair emits `CONTRACT variant-axis: axis '…' not declared …`). The real defect is brittleness/noise from indent-sensitive YAML parsing, not missed validation.
- **M-4 (withdrawn):** `go 1.27.3` (per `go.mod:3` and `AGENTS.md:19`) **is released and is the declared toolchain** — do not recommend downgrading to `1.22`.

---

## 🟠 Medium

### M-1 — `publication-gate.sh` missing `pipefail` — WARN check can be masked

**File:** `scripts/publication-gate.sh:13`, `27`
`set -eu` without `set -o pipefail` means `grep -i warn "$log" | grep -qv '…'` can exit 0 even if first grep fails (pipe status = last command). A corrupted `build-gate.log` could green-light the gate.

**Fix:** `set -euo pipefail` or check each stage explicitly.

### M-2 — `publication-gate.sh` writes `build-gate.log` in repo root

**File:** `scripts/publication-gate.sh:15-16`
Pollutes `git status` if the trap fails (e.g. `kill -9`). Should use `mktemp`.

**Fix:** `log=$(mktemp -t build-gate.XXXXXX)` and trap `rm -f "$log"`; or write to `$RUNNER_TEMP` in CI.

### M-3 — `check-contracts.sh` brittle `hugo.yaml` parsing causes false failures (not silent passes)

**File:** `scripts/check-contracts.sh:44`, `49`
```sh
grep -qE "^    - id: $axis\$" hugo.yaml
axis_block=$(sed -n "/- id: $axis\$/,/^    - id:/p" hugo.yaml)
```
Assumes exactly 4-space indent and no comments/trailing keys. A reformat (e.g. `yamlfmt`) would not silently pass — it would **loudly false-fail** with one `CONTRACT variant-axis` error per pair (the `fail=1` path). Separately, `"$axis"` is regex-interpolated without escaping (axis is `[a-z_]+` today, safe but fragile).

**Fix:** parse with `yq` if available, fallback to indent-insensitive `awk` anchored on key name; or emit a warning when `grep` matches 0 axes.

### M-4 — `check-contracts.sh` word-splitting on `for pair in $(…)` / `for tok in $used_tokens`

**File:** `scripts/check-contracts.sh:27`, `41`, `50`
Unquoted expansions split on IFS. Works for current `[a-z_]+` ids but will break if variant options contain spaces/hyphens. SC2044/SC2066.

**Fix:** `while IFS= read -r` loop or `set -f` + quoted handling; add `# shellcheck disable` with justification.

### M-5 — `static/js/chat.js:739` — `innerHTML = safeMarkdown(answer)` trusts `safeMarkdown` fully

**File:** `static/js/chat.js:153-167`, `739`
`safeMarkdown` is careful (escape first, placeholder fences/lists), but if LLM returns ```` ``` ```` without closing fence the regex `/```([\w+-]*)\n([\s\S]*?)```/g` fails open and subsequent `inlineMarkdown` runs inside the fence. No XSS (escaped), but can produce broken markup / layout.

**Fix:** cap unclosed fences: after the main replace, if `s` still contains ```` ``` ```` wrap remainder as `<pre>`.

### M-6 — `static/js/chat.js` chat completion has no timeout

**File:** `static/js/chat.js:728-810`
Model-list fetch has `AbortSignal.timeout(10000)` (good), but the streaming `fetch(chatUrl…)` for completions has no timeout and `state.controller` is never timed out. A stalled gateway hangs the UI with "Thinking…" forever.

**Fix:** add `AbortSignal.timeout(120_000)` or idle timer resetting on each chunk.

### M-7 — `static/js/chat.js:428` `banner.innerHTML` uses static string — safe, but pattern invites future XSS

**File:** `static/js/chat.js:428`
Static HTML literal is fine, but the file already mixes `textContent` and `innerHTML`. Lint rule should enforce `textContent` + `createElement` for dynamic content.

**Fix:** add eslint rule `no-inner-html` with allowlist comment.

### M-8 — `assets/js/action-registry.js:128-140` markdown fetch cache never invalidates

**File:** `assets/js/action-registry.js:128-140`
`markdown` Map caches `fetchMarkdown(url)` forever. After navigating to a new page the old page's markdown is served incorrectly (key is URL, so cross-page is actually correct), but after content update without reload it is stale until tab close.

**Fix:** add TTL or `invalidateMarkdown()` on `visibilitychange`; document expected staleness.

### M-9 — `.github/workflows/omp.yml:23` `contains(body, '/omp')` is substring match

A comment containing code like `` `npm run /ompile` `` triggers the agent. Low probability but wastes minutes and posts noise.

**Fix:** `contains(github.event.comment.body, '/omp ') || startsWith(..., '/omp')` or regex `/(^|\n)\/omp(\s|$)/`.

### M-10 — `layouts/_partials/hooks/head-end.html:52` CSS attribute selector injection

**File:** `layouts/_partials/hooks/head-end.html:52`
Axis id is interpolated directly into CSS: `html[data-td-variant-{{ $axis }}='{{ $active }}']`. Hugo escapes for HTML but not for CSS identifiers. An axis id with `'` or `]` would break the stylesheet. Today ids are `[a-z_]+`, so not exploitable.

**Fix:** validate axis id against `^[a-z][a-z0-9_]*$` and warn/skip otherwise (already warned for empty id, extend to bad chars).

### M-11 — Stale `public/` and `resources/` on disk (7.6 MB) — misleading for contributors

Both are `.gitignore`d and 0 files tracked (verified), but `public/` from a prior `hugo --environment production` is present locally (30 files, 7.1 MB). Contributors can mistake it for committed output.

**Fix:** add `make clean` or document `rm -rf public resources` after verification; consider `hugo --cleanDestinationDir` already does, but note it in AGENTS.md.

---

## 🟡 Low

### L-1 — `favicons.html` uses `relURL` while hooks use `relLangURL`

**File:** `layouts/_partials/favicons.html:7-11` vs `layouts/_partials/hooks/head-end.html:112`, `body-end.html:9-10`
If the site ever enables multilingual (`defaultContentLanguageInSubdir`), favicons 404 on non-default language. Consistency: use `relLangURL` everywhere (or `absURL`).

### L-2 — `layouts/_partials/actions/context.html:54` `printf (T "ui_open_in_prompt")` — translation string with `%s` filled via `querify`

Works, but `T` strings are translator-editable; a translation dropping `%s` silently sends the wrong prompt. Already guarded in `action-registry.js:151-154` (`promptTemplate.indexOf('%s') < 0` → null), so the link just disables. Consider adding a build-time check.

### L-3 — `static/js/chat.js:84-93` `previewKey` leaks 6-char prefix of API key in DOM

Intentional for UX, but shows in page source / screenshots. Could be opt-in or show `••••` only.

### L-4 — `static/js/agent-setup.js:27` fallback repo literal is hardcoded

`REPO` fallback `'rh-aiservices-bu/CAI-Field-Manual-Hello-World'` will drift if the org renames the content repo. Prefer failing visibly (`No github_repo configured`) over silently cloning the wrong repo.

### L-5 — `Docs/` contains stale review docs referencing old repo name

`Docs/backlog.md:9` still mentions `CAI-Field-Manual-prototype`; `Docs/maas-guide.review.md:4` references `CAI-Field-Manual-prototype` as local site. Either archive or update `Docs/`.

### L-6 — `.hugo_build.lock` (0 B) present on disk — should not be committed and is already gitignored

Harmless, but `hugo` creates it with `flock`; on NFS it can linger. Already in `.gitignore` (`/.hugo_build.lock`), no action needed beyond awareness.

### L-7 — No `eslint` / `stylelint` / `shellcheck` in CI

Shell scripts and 1.4 kLOC of JS have no lint step. `check-contracts.sh` has SC2044/SC2066, `publication-gate.sh` needs SC2086 justification documented.

**Fix:** add a `lint` job (`shellcheck`, `eslint --no-warn`) or a `pre-commit` hook.

### L-8 — `layouts/_partials/shell/sidebar-tree.html:31-34` `$sidebarRootID` vs `$navRoot` inconsistency

`$sidebarRootID` is derived from `sidebar_root_enabled` check, but `$navRoot` can be overridden by `.sidebarRoot` param. When overridden, `data-td-sidebar-root-id` may not match the actual root. No visible bug (downstream JS tolerates missing ID), but confusing.

### L-9 — `hugo.yaml` missing `markup.goldmark.renderer.unsafe` comment

Shell overrides render shortcodes that emit raw HTML (`<code>`, `<div class="td-variant">`). Readers adding `markup.goldmark.renderer.unsafe: false` would break variants. Document the requirement in `hugo.yaml` comments.

### L-10 — `static/css/chat.css` / `agent-setup.css` use `color-mix()` / `backdrop-filter` without fallback

`agent-setup.css:14-17` `color-mix(... 30%, transparent)` and `backdrop-filter: blur(2px)` are not supported in older Firefox ESR. Graceful degradation (solid overlay) is fine, but add a `@supports` fallback comment for future maintainers.

---

## Positive notes (keep)

- `safeUrl()` allowlist (`http:`/`https:` only, rejects `//`, `\`) is correct and consistently applied.
- `action-registry.js` freezing descriptors and rejecting non-builtin `kind` prevents site-config JS injection — strong design.
- `td-variant-selector` inline JS correctly falls back to config `default` for unknown stored ids and sweeps stale keys — rare to see done right.
- `chat.js` `Local Network Access` diagnostic in `formatFetchError` is genuinely helpful; keep it.
- `agent-setup.js` dialog focus restore + `Esc` `stopPropagation` avoids double-close with page-actions menu — careful.
- Publication gate + contract checks are well split (gate = build must pass; contracts = content promises).

---

## Recommended next steps (priority order)

1. **Harden `check-contracts.sh` YAML parsing** (M-3) + shell word-splitting (M-4) — reduces false-fail noise.
2. **Add `pipefail` to `publication-gate.sh`** (M-1) + lint step to CI (L-7) — prevents silent green on corrupted gate log.
3. **Add chat completion timeout** (M-6) — user-visible hang.
4. **Archive/update `Docs/`** (L-5) and clean `public/` guidance (M-11).

---

*Revised single-pass review: working tree at `ea45b4a`; five reviewer slices fanned at T+0 and still running at T+4m+ — none delivered — so findings above are from the integration session only. Prior draft erroneously implied sub-agent coverage ("Reviews are in") and carried three wrong findings (H-1 false-positive XSS, H-2 inverted silent-pass premise, M-4 stale Go version). Sub-agent findings must be merged and attributed when they land.*
