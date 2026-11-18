# Code Review — CAI-Field-Manual-Shell (2026-11-18)

> Scope: full working tree at `ea45b4a` (main), then `212b89f`, then `cf351bbf`, then `03d91b0` (prior integrated draft). Five reviewer slices were fanned out at T+0 (layouts, JS, config/build, scripts/CI, security). At T+4m+ none had delivered (verified at T+4m14s). **SecuritySweep delivered at T+9m41s** and was integrated in `03d91b0`; **ReviewConfigBuild delivered at T+15m50s** and is integrated below; **ReviewLayouts, ReviewJS, ReviewScriptsCI remain running at T+16m** — their findings must be merged and attributed when they land. No behavioral changes were made.

---

## Summary

| Severity | Count | Meaning |
|----------|------:|---------|
| 🔴 High | 1 | Fix before next release |
| 🟠 Medium | 17 | Should-fix, low risk to defer one cycle |
| 🟡 Low | 13 | Polish / hygiene |
| **Total** | **31** | (plus attribution/provenance notes — not counted) |

The repo is in good shape: XSS posture is solid, shell scripts are well-commented, and the variant/customize system is unusually careful for a docs theme. Most findings are edge cases, stale docs, or hardening. One **High** (H-1) has real attack value; the rest are hardening.

### Corrections log (prior drafts)

- **Attribute-escaping finding (withdrawn in 212b89f):** `customize.html:44` `data-td-customize-default="{{ $field.default }}"`, `customize-form.html:59` `value="{{ .default }}"`, `td-variant-selector.html:26` `title="{{ .label }}"` are in `html/template` HTML-attribute context and are **auto-escaped by Go's contextual escaper**. Piping through `| htmlEscape` risks double-escaping; `hugo.yaml` `params.customize` is first-party content. Withdrawn as a High (ID not re-used; the current H-1 is the CI trust-boundary finding).
- **`hugo.yaml` YAML-parsing finding (demoted in 212b89f):** `scripts/check-contracts.sh:44` `if ! grep -qE "^    - id: $axis\$" hugo.yaml` does **not** silently pass on reformat — it **loudly false-fails** (`CONTRACT variant-axis: axis '…' not declared …` per pair). Real defect is brittleness/noise, not missed validation. Demoted to Medium (M-6).
- **`go 1.27.3` finding (withdrawn in 212b89f):** `go.mod:3` / `AGENTS.md:19` declare `go 1.27.3` — released as of 2026-11-18. Prior recommendation to downgrade to 1.22 was wrong.
- **CSS-in-`<style>` finding (withdrawn in cf351):** `layouts/_partials/hooks/head-end.html:52` `html[data-td-variant-{{ $axis }}='{{ $active }}']` inside `<style>` is **CSS context** in `html/template` — the contextual escaper applies `cssValueFilter` (verified live: `'` → `\27`, `"><script>` → `\27\22\3e\3cscript\3e`). Same class as the attribute-escaping finding; not a raw injection.
- **`renderer.unsafe` finding (withdrawn in cf351):** `markup.goldmark.renderer.unsafe` only gates raw HTML **in markdown source**; shortcode templates (`layouts/_shortcodes/*.html`) emit HTML regardless. Setting it `false` does not break variants. Prior premise was inverted.
- **`relLangURL` finding (withdrawn in cf351):** `layouts/_partials/favicons.html` correctly uses `relURL` — Hugo copies `static/favicon.*` to the site root, not into per-language subdirs; `relLangURL` on non-multilingual sites behaves identically and would be unnecessary. Prior recommendation to "use `relLangURL` everywhere" was inverted.

---

## 🔴 High

### H-1 — CI agent workflow: any public commenter can drive a `contents: write` agent that holds a live LLM API key

**Source:** SecuritySweep (T+9m41s) — independently verified via `read .github/workflows/omp.yml`.

**Files:** `.github/workflows/omp.yml:9-12`, `23-24`, `27-29`, `60-61`, `67-71`

**Evidence:** `permissions: contents: write / issues: write / pull-requests: write` (9-12); invocation gate is only `sender.type != 'Bot' && contains(comment.body, '/omp')` (23-24); raw comment body is interpolated verbatim into the agent prompt (`COMMENT_BODY="$(gh api ... --jq .body)"` → `PROMPT` → `omp ... "$PROMPT"` at 67-71). The agent runs with `GH_TOKEN: ${{ github.token }}` (61) and `AGENT_API_KEY` in the step env (60), commits to `omp/issue-<n>` and opens PRs. On a public repo any GitHub user can author the prompt. `<comment>` delimiters are advisory — the agent is instructed to execute the request. The `Bot` filter does prevent reply-loop re-triggering (agent posts as `github-actions[bot]`), and the omp binary SHA256 pin is good — neither mitigates prompt injection or key exfiltration via tool calls.

**Fix (options, in priority order):**
1. Restrict trigger to collaborators/owners (`if: github.event.sender.type == 'User' && (github.event.comment.author_association == 'MEMBER' || … == 'OWNER' || … == 'COLLABORATOR')`), or require label/approval gate with an `environment:` protection rule before the write step.
2. Keep `AGENT_API_KEY` out of the agent's inherited env — write it only to `models.yml`, not `env:` of the `Run omp` step that the agent's tools can read.
3. Principle of least privilege: `contents: write` only on the final push job after human approval; earlier jobs `contents: read` + `pull-requests: write`.
4. Drop `fetch-depth: 0` (line 29) — full history is not needed for the agent run and widens the "read the repo" exfiltration surface.

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

### M-3 — `hugo.work` is documented as gitignored but is not

**Source:** ReviewConfigBuild (T+15m50s) — independently verified via `read .gitignore` and `read README.md/AGENTS.md`.

**Files:** `.gitignore:1-5`; `README.md:94` / `AGENTS.md:34`

Both `README.md:94` and `AGENTS.md:34` state "`hugo.work` is gitignored — never commit it." But `.gitignore:1-5` contains only `/public/`, `/resources/`, `/.hugo_cache/`, `/.hugo_build.lock`, `.DS_Store` — `git check-ignore -v hugo.work hugo.work.sum build-gate.log` matches nothing. A `git add -A` from the documented verification flow would commit a workspace file whose `replace … => ../CAI-Field-Manual-Shell` points outside any clone. `build-gate.log` (leaked if the `publication-gate.sh:15` trap is skipped, e.g. `kill -9`) is equally unprotected.

**Fix:** append to `.gitignore`: `/hugo.work`, `/hugo.work.sum`, `/build-gate.log`.

### M-4 — Logo lockup ink follows the OS color-scheme, not the site's dark-mode toggle

**Source:** ReviewConfigBuild (T+15m50s) — independently verified via `read assets/icons/logo-rh-cai.svg` and `assets/scss/_styles_project.scss`.

**Files:** `assets/icons/logo-rh-cai.svg:4-6`; `assets/scss/_styles_project.scss:5` (misleading comment)

The SVG flips `.rh-cai-ink` to `#fff` only inside `@media (prefers-color-scheme: dark)`. The site's dark mode is a reader-selectable `html[data-bs-theme=dark]` toggle (`dark_mode: true` in `hugo.yaml:19` → Appearance menu). A reader with a light OS who toggles Dark gets `#151515` ink on a dark canvas (`#161513`, per built `public/index.html` theme block) — contrast ≈ 1.05:1, the wordmark and divider vanish. The reverse (dark OS + light site) yields white ink on `#f7f6f3`. An `<img>`-embedded SVG can only see the OS scheme, never the host page's `[data-bs-theme]` attribute, so no selector inside the SVG can fix this; the SCSS comment "The SVG's own media query handles theme ink" asserts something the mechanism cannot deliver.

**Fix (pick one, both in sanctioned files):** (a) keep constant ink and add a light plate `rect` behind the lockup so it reads on both canvases, updating the SCSS comment; or (b) inline the lockup via a shell-owned brand partial so `data-bs-theme` selectors can drive `.rh-cai-ink`. Also note the print bundle inherits the same failure for dark-OS readers.

### M-5 — Shell `static/` assets bypass the theme's minify/fingerprint pipeline

**Source:** ReviewConfigBuild (T+15m50s) — verified in production `public/` output.

**Files:** `static/css/chat.css:1`, `static/css/agent-setup.css:1`; emitted at `layouts/_partials/hooks/head-end.html:112,115` and `body-end.html:10,20`

Theme bundles ship as `scss/main.min.<sha256>.css` with SRI, while `public/js/chat.js` (38 KB), `public/css/chat.css`, `agent-setup.{js,css}` are copied verbatim, unminified and unhashed — verified in production output. No cache busting (a redeploy can leave returning readers on a stale `chat.js` against a fresh site — this pair is version-coupled to the hooks' `__TD_CHAT__`/`__TD_AGENT_SETUP__` blobs), and `agent-setup.css` (2.4 KB, needed only when the modal opens) is fetched on every page.

**Fix:** move the four files under `assets/` and emit them from the hooks with the established pattern (`resources.Get` → `minify` → `fingerprint`, as `head-css.html` does), keeping `relLangURL` semantics via `.RelPermalink`.

### M-6 — `check-contracts.sh` brittle `hugo.yaml` parsing causes false failures (not silent passes)

**File:** `scripts/check-contracts.sh:44`, `49`
```sh
grep -qE "^    - id: $axis\$" hugo.yaml
axis_block=$(sed -n "/- id: $axis\$/,/^    - id:/p" hugo.yaml)
```
Assumes exactly 4-space indent and no comments/trailing keys. A reformat (e.g. `yamlfmt`) would not silently pass — it would **loudly false-fail** with one `CONTRACT variant-axis` error per pair (the `fail=1` path). Separately, `"$axis"` is regex-interpolated without escaping (axis is `[a-z_]+` today, safe but fragile).

**Fix:** parse with `yq` if available, fallback to indent-insensitive `awk` anchored on key name; or emit a warning when `grep` matches 0 axes.

### M-7 — `check-contracts.sh` word-splitting on `for pair in $(…)` / `for tok in $used_tokens`

**File:** `scripts/check-contracts.sh:27`, `41`, `50`
Unquoted expansions split on IFS. Works for current `[a-z_]+` ids but will break if variant options contain spaces/hyphens. SC2044/SC2066.

**Fix:** `while IFS= read -r` loop or `set -f` + quoted handling; add `# shellcheck disable` with justification.

### M-8 — `check-contracts.sh` hardcoded variant labels + `labels` never asserted

**File:** `scripts/check-contracts.sh:68-69`, `91-93`
`grep -cE '\*\*(RHAIE Version|Ops Mode): '` hardcodes the two current axis labels. A renamed axis label, or a new consumer with different `params.variants[].label`, yields `labels=0` and still prints `contracts OK` — because `labels` is only interpolated in the success banner (`echo "contracts OK — $pages pages, $labels variant labels, …"`), never asserted via `fail=1`. Contract 3 ("every variant block is labelled") can thus never fail.

**Fix:** derive expected labels from `hugo.yaml` `params.variants[].label` and assert `src_variants > 0 && out_labels == 0` → `fail=1`; or compare `src_variants` against `out_labels`.

### M-9 — `check-contracts.sh` only validates positional shortcode forms

**File:** `scripts/check-contracts.sh:26`, `41`
Line 26 `\{\{< customize [a-z_]+ >\}\}` and line 41 `\{\{< variant [a-z_]+ ("[^"]*"|[a-z0-9._-]+) >\}\}` only match the positional form (`{{< variant version "3.5" >}}`). But `layouts/_shortcodes/customize.html:16` and `variant.html:23` both branch on `if .IsNamedParams`, accepting named form (`{{< variant axis="version" id="3.5" >}}`). Named-param usages in content bypass the `declared in hugo.yaml` check entirely and the gate still prints "contracts OK". Separately, line 44's `grep -qE "^    - id: $axis\$" hugo.yaml` scans the whole file, so an axis id that collides with a `params.customize` field id (e.g. `user`) could validate against the wrong YAML block.

**Fix:** add a second regex for named form or broaden to `\{\{< (customize|variant)[^>]*>\}\}` with extraction; scope the axis lookup to the `params.variants` section.

### M-10 — `check-contracts.sh` has no freshness guard: validates whatever `public/` happens to contain

**Source:** SecuritySweep — independently verified.

**File:** `scripts/check-contracts.sh:60` (`find public -name index.md …`), usage comment at `:1-6` (assumes a just-built `public/`).

A stale, partial, or hand-edited `public/` silently passes — CI could cache an old `public/` and print "contracts OK" without having rebuilt. `publication-gate.sh` enforces `--cleanDestinationDir`; this gate does not and is not required to run after it.

**Fix:** either run `hugo --cleanDestinationDir` inside the script (like the publication gate does), or require a freshness proof (e.g. check `public/.hugo_build.lock` mtime, or accept `$BUILD_DIR` as an explicit arg and refuse if absent). At minimum, document the required invocation order in the script header.

### M-11 — Missing `params.github_repo` renders a broken clone URL that defeats the single-source claim

**Source:** SecuritySweep — independently verified via `read layouts/_partials/hooks/body-end.html` and `static/js/agent-setup.js`.

**File:** `layouts/_partials/hooks/body-end.html:18` (`repo: "{{ printf "%s" site.Params.github_repo | strings.TrimPrefix "https://github.com/" }}"`) → consumed by `static/js/agent-setup.js:27`

`hugo.yaml` in this module intentionally does not set `github_repo` — it lives in importing sites. When absent, `printf "%s" nil` renders `<no value>`, so the copy-prompt prints `git clone https://github.com/<no value>.git`. The JS fallback (`|| 'rh-aiservices-bu/…'` at agent-setup.js:27) is dead code because `__TD_AGENT_SETUP__` is always defined by the hook, just with garbage. A trailing-slash value also survives `TrimPrefix`.

**Fix:** guard in the template (`{{ with site.Params.github_repo }}…{{ else }}warnf{{ end }}`), strip trailing `/`, and delete the dead JS default so the "single source (`params.github_repo`)" claim holds. The JS fallback can then be removed or turned into an explicit error.

### M-12 — No security headers: no CSP, Referrer-Policy, nosniff

**Source:** SecuritySweep — spot-checked in built output (`public/index.html` has no `Content-Security-Policy`/`referrer` meta).

**Files:** `layouts/docs/baseof.html:7` (head assembled via `head.html` + hooks); built `public/index.html` confirms zero matches for `Content-Security-Policy|http-equiv.*referrer`.

The theme emits SRI + `crossorigin` on bundled assets (good), but no `<meta http-equiv="Content-Security-Policy">` or `<meta name="referrer">`. GitHub Pages cannot set response headers, so meta is the only vehicle. This site specifically runs a BYO-endpoint chat widget that POSTs the reader's API key to an arbitrary host (`static/js/chat.js:711-721`) and fetches `?src=`-controlled same-origin paths (`chat.js:583-613`) — a `default-src 'self'; connect-src` baseline would at least bound script/frame egress (chat's open-egress is intentional, but should be documented as a CSP carve-out).

**Fix:** add `<meta http-equiv="Content-Security-Policy" content="object-src 'none'; base-uri 'self'; frame-ancestors 'none'; …">` in a head hook (script-src will need `unsafe-inline` or hashes given the pre-paint bootstrap — even a partial policy is better than none) plus `<meta name="referrer" content="strict-origin-when-cross-origin">`.

### M-13 — `static/js/chat.js:739` — `innerHTML = safeMarkdown(answer)` trusts `safeMarkdown` fully

**File:** `static/js/chat.js:153-167`, `739`
`safeMarkdown` is careful (escape first, placeholder fences/lists), but if LLM returns ```` ``` ```` without closing fence the regex `/```([\w+-]*)\n([\s\S]*?)```/g` fails open and subsequent `inlineMarkdown` runs inside the fence. No XSS (escaped), but can produce broken markup / layout.

**Fix:** cap unclosed fences: after the main replace, if `s` still contains ```` ``` ```` wrap remainder as `<pre>`.

### M-14 — `static/js/chat.js` chat completion has no timeout

**File:** `static/js/chat.js:728-810`
Model-list fetch has `AbortSignal.timeout(10000)` (good), but the streaming `fetch(chatUrl…)` for completions has no timeout and `state.controller` is never timed out. A stalled gateway hangs the UI with "Thinking…" forever.

**Fix:** add `AbortSignal.timeout(120_000)` or idle timer resetting on each chunk.

### M-15 — `static/js/chat.js:428` `banner.innerHTML` uses static string — safe, but pattern invites future XSS

**File:** `static/js/chat.js:428`
Static HTML literal is fine, but the file already mixes `textContent` and `innerHTML`. Lint rule should enforce `textContent` + `createElement` for dynamic content.

**Fix:** add eslint rule `no-inner-html` with allowlist comment.

### M-16 — `assets/js/action-registry.js:128-140` markdown fetch cache never invalidates

**File:** `assets/js/action-registry.js:128-140`
`markdown` Map caches `fetchMarkdown(url)` forever. After navigating to a new page the old page's markdown is served incorrectly (key is URL, so cross-page is actually correct), but after content update without reload it is stale until tab close.

**Fix:** add TTL or `invalidateMarkdown()` on `visibilitychange`; document expected staleness.

### M-17 — `.github/workflows/omp.yml:24` `contains(body, '/omp')` is substring match

A comment containing code like `` `npm run /ompile` `` triggers the agent. Low probability but wastes minutes and posts noise. (Distinct from H-1's prompt-injection issue — this is the cheap false-trigger even for legitimate users.)

**Fix:** `contains(github.event.comment.body, '/omp ') || startsWith(..., '/omp')` or regex `/(^|\n)\/omp(\s|$)/`.

---

## 🟡 Low

### L-1 — `layouts/_partials/actions/context.html:54` `printf (T "ui_open_in_prompt")` — translation string with `%s` filled via `querify`

Works, but `T` strings are translator-editable; a translation dropping `%s` silently sends the wrong prompt. Already guarded in `action-registry.js:151-154` (`promptTemplate.indexOf('%s') < 0` → null), so the link just disables. Consider adding a build-time check.

### L-2 — `static/js/chat.js:84-93` `previewKey` leaks 6-char prefix of API key in DOM

Intentional for UX, but shows in page source / screenshots. Could be opt-in or show `••••` only.

### L-3 — `static/js/agent-setup.js:27` fallback repo literal is hardcoded

`REPO` fallback `'rh-aiservices-bu/CAI-Field-Manual-Hello-World'` will drift if the org renames the content repo. Now compounded by M-11: prefer failing visibly (`No github_repo configured`) over silently cloning the wrong repo.

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

### L-9 — Pinned-copy bookkeeping is stale: "all three", "one deliberate change"

**Source:** ReviewConfigBuild (T+15m50s) — independently verified via `grep -rn "Re-diff\|one deliberate"` in docs and layout headers.

**Files:** `README.md:15-20`; `AGENTS.md:42-47`; `layouts/_partials/actions/context.html`, `title-menu.html`

`README.md:15` says "Re-diff all three against `~/go/pkg/mod/…`" but the pinned set is now **seven files** (`AGENTS.md:42-47` lists them), and two of them (`context.html`, `title-menu.html`) carry **no provenance comment** at all — both start with the theme's own headers; diffing shows the only changes are the appended `open_gemini`/`feed_agent` rows. `action-registry.js` and `page-actions.js` now each contain two deliberate changes (Gemini + feed-agent), contradicting "naming its one deliberate change". A theme bump using the old count would miss files.

**Fix:** update `README.md` count/list, add provenance headers to the two missing files, and reword "one deliberate change" to "each named change" in `AGENTS.md:45` and `README.md:16`.

### L-10 — `README.md:40` overstates that `check-contracts.sh` runs in content repos' CI

**Source:** ReviewConfigBuild (T+15m50s) — verified against Hello-World `github-pages.yaml`.

`README.md:40` headers both scripts as "run by content repos' CI via a `shell/` checkout", but Hello-World's `.github/workflows/github-pages.yaml` calls only `shell/scripts/publication-gate.sh` (lines 74, 121); the contract check is a **manual/local gate only** (see `AGENTS.md:36`). Dual-consumption promises are therefore unenforced in CI despite the README's implication. This matters because M-5 through M-10 are about those contracts.

**Fix:** reword `README.md:40` to "publication-gate.sh runs in CI; check-contracts.sh is a local gate (add it to CI if you want it enforced)" — or actually add the step to the content repo's workflow.

### L-11 — `README.md:71` typo: "Shel changes"

`README.md:71` says "Shel changes are proven by building…" → "Shell changes".

### L-12 — Experimental presets shipped to every reader without comment

**Files:** `hugo.yaml:18` `preset_menu: [paper, slate, ink, terminal]`

Oink documents `ink`/`terminal` as experimental (`preset-config.html:10,16`, `_experimental-presets.scss:1` → `// Experimental`). Valid config (no build warning), but worth confirming intent for a customer-facing manual. Drop the two names if not — keeps the Appearance menu to two stable choices.

### L-13 — Pointless empty param

**File:** `hugo.yaml:15` `footer_center_info: ''`

The theme keys on `isset` (`shell/footer-line.html:14`), so the empty string activates a code path that renders nothing — omitting the key is equivalent and clearer. Trim.

---

### Attribution & deferred findings

### Note — SecuritySweep: findings adopted, one demoted

- **SecuritySweep M2 (not adopted as written):** "Config strings interpolated raw into `<style>` and `<script type=\"application/json\">`" — axis/option ids and status phrases emitted via `{{ $axis }}` in `<style>` and `{{ $blob | jsonify | safeJS }}` in `application/json`. The report claimed Hugo `jsonify` does not escape `<`/`/` so `</script>` breaks out, and axis ids inject CSS. Re-checked: `<style>` content is **CSS context** in `html/template` (verified live in prior draft via `go run` — `'` → `\27`, `"><script>` → CSS-escaped), not raw; and Hugo's `jsonify` (backed by `encoding/json` with `SetEscapeHTML(true)`) emits `<` as `\u003c`, so `</script>` cannot terminate the JSON element. Site params are **first-party trusted config** (content-repo maintainers), not an XSS boundary. Demoted to defense-in-depth: constraining ids at validation time (`head-end.html:18-36` already warns on bad axes) is good hygiene — keep it as a Low, not a Medium. No change to the report beyond this note.
- **SecuritySweep M3 freshness gap** merged into **M-10** above; its additional note about unquoted `for md in $manual_mds` and `sed` over-matching `params.customize: { id: … }`-style variant options is valid and is covered by **M-7** (word-splitting) and **M-6** (scope axis lookup to `params.variants`).
- **SecuritySweep L1-L8:** L1 (LICENSE/SECURITY.md/Dependabot, stale `publication-gate.sh:9` comment referencing non-existent `github-pages.yaml`) is valid hygiene — left as L-6 note to add supply-chain docs. L2 (GA4 `cookie_flags`) is valid but below the report's current Low bar; L3 (agent-setup clipboard `.catch`), L4 (`isLocalHostname` misses `.home.arpa`/ULA), L5 (customize over-match), L7 (minor `curl --fail`, `rel="noopener"` vs `noreferrer`) are noted and may be promoted when the layout/JS slices land. None are dropped.

### Note — ReviewConfigBuild: findings adopted (3 medium + 5 low)

- M1-M3 adopted as **M-3/M-4/M-5** above (`.gitignore` gap, logo `prefers-color-scheme` vs `data-bs-theme`, `static/` cache-busting). L1-L5 adopted as **L-9/L-10/L-11/L-12/L-13** above (pinned-copy count/provenance staleness, README CI overstatement, typo, experimental presets, empty footer param).
- ReviewConfigBuild's Verified Clean (hugoVersion, go.mod, tokens, favicons, tokens, `.hugo_build.lock` provenance) independently confirms the prior drafts' withdrawals remain correct — no re-raised false positives.

### Note — `public/` / `resources/_gen/` scope (not a finding)

`public/` is **gitignored** (`/.gitignore:1`) and **untracked** (verified: `git ls-files public/` → empty) and `resources/_gen/` is similarly untracked build output. The reviewer prompts were scoped to `layouts/`, `assets/`, `static/`, `scripts/`, `hugo.yaml`, `go.mod`, `.github/`, `Docs/` — no stale `public/` or `resources/` issues were reported by SecuritySweep or ReviewConfigBuild, and none are added here.

### Note — ReviewJS diffed against wrong upstream version (observed; not a code defect)

The `ReviewJS` sub-agent's transcript (e.g. history at `ReviewJS.jsonl` line ~60-65) diffed the pinned `assets/js/action-registry.js` / `page-actions.js` against the Hugo cache entry for **`oink@v1.5.1`**, while `go.mod:5` pins **`v1.4.0`** (and `AGENTS.md:39` mandates re-diffing against `~/go/pkg/mod/github.com/pgsty/oink@v1.4.0/`). Any "diverged from upstream" findings from that diff are artifacts of the wrong baseline and must be discarded when integrating that slice. This is a review-provenance note, not a code defect.

---

## Positive notes (keep)

- `safeUrl()` allowlist (`http:`/`https:` only, rejects `//`, `\`) is correct and consistently applied — SecuritySweep independently verified every `| safeURL` site in `title-menu.html` passes through `content/url.html` validation.
- `action-registry.js` freezing descriptors and rejecting non-builtin `kind` prevents site-config JS injection — strong design.
- `td-variant-selector` inline JS correctly falls back to config `default` for unknown stored ids and sweeps stale keys — rare to see done right.
- `chat.js` `Local Network Access` diagnostic in `formatFetchError` is genuinely helpful; keep it (SecuritySweep flagged its `isLocalHostname` as slightly narrow — true, but the current version handles the common cases).
- `agent-setup.js` dialog focus restore + `Esc` `stopPropagation` avoids double-close with page-actions menu — careful.
- Publication gate + contract checks are well split (gate = build must pass; contracts = content promises).
- **SecuritySweep verified clean:** no secrets in tracked files/history/`public/` (only public GA ID `G-7ZXCS2MF1D`); SRI + `crossorigin` on bundled assets present; `safeMarkdown` escapes first then transforms — correct order; no tracked large binaries; stale `public/`/`resources/` untracked and harmless.
- **ReviewConfigBuild verified clean:** `hugoVersion.min: 0.168.0`, all `params.ui.*` keys validated against theme; `go.mod`/`go.sum` verified; `--td-*`/`--bs-*` tokens exist in theme; favicons correctly sized.

---

## Recommended next steps (priority order)

1. **Harden CI trust boundary** (H-1) — restrict `omp` trigger to collaborators and split `contents: write` to an approval-gated job; move `AGENT_API_KEY` out of the agent's env.
2. **Harden `check-contracts.sh` contracts** (M-3/M-4/M-5 etc. consolidated as M-6/M-7/M-8/M-9/M-10) — derive variant labels from `hugo.yaml` and assert them; add named-param coverage; add freshness guard; scope lookups to `params.variants`; fix YAML + shell brittleness. Also fix **M-11** (`github_repo` guard) and the **ReviewConfigBuild** CI/docs items **L-9/L-10** (pinned-copy provenance, README CI overstatement).
3. **Shell hygiene** (M-3, M-1, M-4, M-5) — `.gitignore` gap for `hugo.work`, logo `prefers-color-scheme` vs `data-bs-theme` mismatch, `static/` asset cache-busting, and `publication-gate.sh` `pipefail`.
4. **Add chat completion timeout** (M-14) + CSP/referrer meta (M-12) — user-visible hang + cheap defense-in-depth.
5. **Archive/update `Docs/`** (L-4) + typo (L-11).

---

*Report at `cf351bbf` scope plus SecuritySweep (T+9m41s) and ReviewConfigBuild (T+15m50s) integrations. ReviewLayouts, ReviewJS, ReviewScriptsCI remain running — their findings must be merged and attributed when they land. Withdrawals: attribute-escaping, CSS-in-style, renderer.unsafe, relLangURL same-class false positives verified by live `go run` test and Hugo semantics; current additions: `.gitignore` gap, logo OS-vs-site theme mismatch, static-asset cache-busting, pinned-copy/README bookkeeping — all independently verified via `read` before adoption.*
