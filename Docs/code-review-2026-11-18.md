# Code Review — CAI-Field-Manual-Shell (2026-11-18)

> Scope: full working tree at `ea45b4a` (main) and then at `212b89f` (this report's prior corrected draft). Five reviewer slices were fanned out (layouts, JS, config/build, scripts/CI, security) at T+0 and were **still running at T+4m+ when this document was authored** — none had delivered a final output (verified via `proc://` and `agent://`/`history://` reads at T+4m14s). **This document is therefore a single-pass review by the integration session, not an integration of sub-agent findings.** When sub-agents deliver, their findings must be merged and explicitly attributed (or deltas noted). No behavioral changes were made.

---

## Summary

| Severity | Count | Meaning |
|----------|------:|---------|
| 🟠 Medium | 11 | Should-fix, low risk to defer one cycle |
| 🟡 Low | 7 | Polish / hygiene |
| **Total** | **18** | |

The repo is in good shape: XSS posture is solid, shell scripts are well-commented, and the variant/customize system is unusually careful for a docs theme. Most findings are edge cases, stale docs, or hardening.

### Corrections log (this draft)

- **H-1 (withdrawn in 212b89f):** `customize.html:44` `data-td-customize-default="{{ $field.default }}"`, `customize-form.html:59` `value="{{ .default }}"`, `td-variant-selector.html:26` `title="{{ .label }}"` are in `html/template` HTML-attribute context and are **auto-escaped by Go's contextual escaper**. Piping through `| htmlEscape` risks double-escaping; `hugo.yaml` `params.customize` is first-party content. Withdrawn.
- **H-2 → M-3 (demoted in 212b89f):** `scripts/check-contracts.sh:44` `if ! grep -qE "^    - id: $axis\$" hugo.yaml` does **not** silently pass on reformat — it **loudly false-fails** (`CONTRACT variant-axis: axis '…' not declared …` per pair). Real defect is brittleness/noise, not missed validation.
- **go 1.27.3 (withdrawn in 212b89f):** `go.mod:3` / `AGENTS.md:19` declare `go 1.27.3` — released as of 2026-11-18. Prior recommendation to downgrade to 1.22 was wrong.
- **M-10 (withdrawn this draft):** `layouts/_partials/hooks/head-end.html:52` `html[data-td-variant-{{ $axis }}='{{ $active }}']` inside `<style>` is **CSS context** in `html/template` — the contextual escaper applies `cssValueFilter` (verified live: `'` → `\27`, `"><script>` → `\27\22\3e\3cscript\3e`). Same class as H-1; not a raw injection.
- **L-9 (withdrawn this draft):** `markup.goldmark.renderer.unsafe` only gates raw HTML **in markdown source**; shortcode templates (`layouts/_shortcodes/*.html`) emit HTML regardless. Setting it `false` does not break variants. Prior L-9 premise was inverted.
- **L-1 (withdrawn this draft):** `layouts/_partials/favicons.html` correctly uses `relURL` — Hugo copies `static/favicon.*` to the site root, not into per-language subdirs; `relLangURL` on non-multilingual sites behaves identically and would be unnecessary. Prior L-1 recommendation to "use `relLangURL` everywhere" was inverted.

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

### M-5 — `check-contracts.sh` hardcoded variant labels + `labels` never asserted

**File:** `scripts/check-contracts.sh:68-69`, `91-93`
`grep -cE '\*\*(RHAIE Version|Ops Mode): '` hardcodes the two current axis labels. A renamed axis label, or a new consumer with different `params.variants[].label`, yields `labels=0` and still prints `contracts OK` — because `labels` is only interpolated in the success banner (`echo "contracts OK — $pages pages, $labels variant labels, …"`), never asserted via `fail=1`. Contract 3 ("every variant block is labelled") can thus never fail.

**Fix:** derive expected labels from `hugo.yaml` `params.variants[].label` and assert `src_variants > 0 && out_labels == 0` → `fail=1`; or compare `src_variants` against `out_labels`.

### M-6 — `check-contracts.sh` only validates positional shortcode forms

**File:** `scripts/check-contracts.sh:26`, `41`
Line 26 `\{\{< customize [a-z_]+ >\}\}` and line 41 `\{\{< variant [a-z_]+ ("[^"]*"|[a-z0-9._-]+) >\}\}` only match the positional form (`{{< variant version "3.5" >}}`). But `layouts/_shortcodes/customize.html:16` and `variant.html:23` both branch on `if .IsNamedParams`, accepting named form (`{{< variant axis="version" id="3.5" >}}`). Named-param usages in content bypass the `declared in hugo.yaml` check entirely and the gate still prints "contracts OK". Separately, line 44's `grep -qE "^    - id: $axis\$" hugo.yaml` scans the whole file, so an axis id that collides with a `params.customize` field id (e.g. `user`) could validate against the wrong YAML block.

**Fix:** add a second regex for named form or broaden to `\{\{< (customize|variant)[^>]*>\}\}` with extraction; scope the axis lookup to the `params.variants` section.

### M-7 — `static/js/chat.js:739` — `innerHTML = safeMarkdown(answer)` trusts `safeMarkdown` fully

**File:** `static/js/chat.js:153-167`, `739`
`safeMarkdown` is careful (escape first, placeholder fences/lists), but if LLM returns ```` ``` ```` without closing fence the regex `/```([\w+-]*)\n([\s\S]*?)```/g` fails open and subsequent `inlineMarkdown` runs inside the fence. No XSS (escaped), but can produce broken markup / layout.

**Fix:** cap unclosed fences: after the main replace, if `s` still contains ```` ``` ```` wrap remainder as `<pre>`.

### M-8 — `static/js/chat.js` chat completion has no timeout

**File:** `static/js/chat.js:728-810`
Model-list fetch has `AbortSignal.timeout(10000)` (good), but the streaming `fetch(chatUrl…)` for completions has no timeout and `state.controller` is never timed out. A stalled gateway hangs the UI with "Thinking…" forever.

**Fix:** add `AbortSignal.timeout(120_000)` or idle timer resetting on each chunk.

### M-9 — `static/js/chat.js:428` `banner.innerHTML` uses static string — safe, but pattern invites future XSS

**File:** `static/js/chat.js:428`
Static HTML literal is fine, but the file already mixes `textContent` and `innerHTML`. Lint rule should enforce `textContent` + `createElement` for dynamic content.

**Fix:** add eslint rule `no-inner-html` with allowlist comment.

### M-10 — `assets/js/action-registry.js:128-140` markdown fetch cache never invalidates

**File:** `assets/js/action-registry.js:128-140`
`markdown` Map caches `fetchMarkdown(url)` forever. After navigating to a new page the old page's markdown is served incorrectly (key is URL, so cross-page is actually correct), but after content update without reload it is stale until tab close.

**Fix:** add TTL or `invalidateMarkdown()` on `visibilitychange`; document expected staleness.

### M-11 — `.github/workflows/omp.yml:23` `contains(body, '/omp')` is substring match

A comment containing code like `` `npm run /ompile` `` triggers the agent. Low probability but wastes minutes and posts noise.

**Fix:** `contains(github.event.comment.body, '/omp ') || startsWith(..., '/omp')` or regex `/(^|\n)\/omp(\s|$)/`.

---

## 🟡 Low

### L-1 — `layouts/_partials/actions/context.html:54` `printf (T "ui_open_in_prompt")` — translation string with `%s` filled via `querify`

Works, but `T` strings are translator-editable; a translation dropping `%s` silently sends the wrong prompt. Already guarded in `action-registry.js:151-154` (`promptTemplate.indexOf('%s') < 0` → null), so the link just disables. Consider adding a build-time check.

### L-2 — `static/js/chat.js:84-93` `previewKey` leaks 6-char prefix of API key in DOM

Intentional for UX, but shows in page source / screenshots. Could be opt-in or show `••••` only.

### L-3 — `static/js/agent-setup.js:27` fallback repo literal is hardcoded

`REPO` fallback `'rh-aiservices-bu/CAI-Field-Manual-Hello-World'` will drift if the org renames the content repo. Prefer failing visibly (`No github_repo configured`) over silently cloning the wrong repo.

### L-4 — `Docs/` contains stale review docs referencing old repo name

`Docs/backlog.md:9` still mentions `CAI-Field-Manual-prototype`; `Docs/maas-guide.review.md:4` references `CAI-Field-Manual-prototype` as local site. Either archive or update `Docs/`.

### L-5 — `.hugo_build.lock` (0 B) present on disk — should not be committed and is already gitignored

Harmless, but `hugo` creates it with `flock`; on NFS it can linger. Already in `.gitignore` (`/.hugo_build.lock`), no action needed beyond awareness.

### L-6 — No `eslint` / `stylelint` / `shellcheck` in CI

Shell scripts and 1.4 kLOC of JS have no lint step. `check-contracts.sh` has SC2044/SC2066, `publication-gate.sh` needs SC2086 justification documented.

**Fix:** add a `lint` job (`shellcheck`, `eslint --no-warn`) or a `pre-commit` hook.

### L-7 — `layouts/_partials/shell/sidebar-tree.html:31-34` `$sidebarRootID` vs `$navRoot` inconsistency

`$sidebarRootID` is derived from `sidebar_root_enabled` check, but `$navRoot` can be overridden by `.sidebarRoot` param. When overridden, `data-td-sidebar-root-id` may not match the actual root. No visible bug (downstream JS tolerates missing ID), but confusing.

### L-8 — `static/css/chat.css` / `agent-setup.css` use `color-mix()` / `backdrop-filter` without fallback

`agent-setup.css:14-17` `color-mix(... 30%, transparent)` and `backdrop-filter: blur(2px)` are not supported in older Firefox ESR. Graceful degradation (solid overlay) is fine, but add a `@supports` fallback comment for future maintainers.

### L-9 — ReviewJS diffed against wrong upstream version (observed; not a code defect)

The `ReviewJS` sub-agent's transcript (e.g. history at `ReviewJS.jsonl` line ~60-65) diffed the pinned `assets/js/action-registry.js` / `page-actions.js` against the Hugo cache entry for **`oink@v1.5.1`**, while `go.mod:5` pins **`v1.4.0`** (and `AGENTS.md:39` mandates re-diffing against `~/go/pkg/mod/github.com/pgsty/oink@v1.4.0/`). Any "diverged from upstream" findings from that diff are artifacts of the wrong baseline and must be discarded when integrating that slice. This is a review-provenance note, not a code defect.

### Note — `public/` / `resources/_gen/` scope (not a finding)

`public/` is **gitignored** (`/.gitignore:1`) and **untracked** (verified: `git ls-files public/` → empty) and `resources/_gen/` is similarly untracked build output. The reviewer prompts were scoped to `layouts/`, `assets/`, `static/`, `scripts/`, `hugo.yaml`, `go.mod`, `.github/`, `Docs/` — no stale `public/` or `resources/` issues were reported by sub-agents, and none were added here.

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

1. **Harden `check-contracts.sh` contracts** (M-3/M-4/M-5/M-6) — derive variant labels from `hugo.yaml` and assert them; add named-param coverage; fix YAML + shell brittleness.
2. **Add `pipefail` to `publication-gate.sh`** (M-1) + lint step to CI (L-6) — prevents silent green on corrupted gate log.
3. **Add chat completion timeout** (M-8) — user-visible hang.
4. **Archive/update `Docs/`** (L-4) and add `public/` clean-up note if desired.

---

*Revised single-pass review: working tree at `212b89f`; prior draft was at `ea45b4a`. Five reviewer slices fanned at T+0, still running at T+4m+ with no delivered output, so findings are from the integration session only. This draft withdraws M-10/L-9/L-1 as same-class false positives (Go `html/template` CSS-context escaper; `renderer.unsafe` governs markdown source only; `static/` serves from site root) verified by live `go run` test and Hugo semantics, and adds the contracts defects (hardcoded labels + unused `labels` count; positional-only shortcode regex). Sub-agent findings must be merged and attributed when they land.*
