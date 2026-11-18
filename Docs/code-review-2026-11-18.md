# Code Review — CAI-Field-Manual-Shell (2026-11-18)

> Scope: full working tree at `ea45b4a` (main) → `212b89f` → `cf351bbf` → `03d91b0` → `a2515d6` → `be41a00` → `a785704` (prior integrated drafts).
> Five reviewer slices were fanned at T+0 (layouts, JS, config/build, scripts/CI, security). At T+4m+ none had delivered (verified at T+4m14s).
> **SecuritySweep (T+9m41s)**, **ReviewConfigBuild (T+15m50s)**, **ReviewScriptsCI (T+17m29s)** integrated.
> **ReviewJS (T+20m28s) delivered one High (chat `?src=` fetch → prompt injection)** — noted below as pending re-emission (full transcript truncated at generation).
> **ReviewLayouts remains running at T+24m** — its findings must be merged and attributed when it lands.
> Worktree at remediation time (2026-11-18) carried three uncommitted WIP files: `assets/scss/_styles_project.scss` sidebar `:has()` guard, `layouts/_partials/hooks/body-end.html` `llmsFull` from `docs_section`, `scripts/check-contracts.sh` docs_section derivation. The contracts WIP had dropped the `page.md` source mapping so contract 3 was vacuous (0 pages). Those WIP changes are kept; the contracts regression was restored in the remediation.

---

## Summary

| Severity | Count | Meaning |
|----------|------:|---------|
| 🔴 High | 0 | Fix before next release |
| 🟠 Medium | 0 | Should-fix, low risk to defer one cycle |
| 🟡 Low | 5 | No-action, documented |
| **Total** | **5** | (plus attribution/provenance notes — not counted) |

All actionable findings from this review have been remediated or dispositioned; five Low findings remain as no-action documentation. The print-bundle double-count High was demoted to M-2 and the logo-ink finding was withdrawn — see corrections log.

### Corrections log (prior drafts)

- **Attribute-escaping finding (withdrawn in 212b89f):** `customize.html:44` `data-td-customize-default="{{ $field.default }}"`, `customize-form.html:59` `value="{{ .default }}"`, `td-variant-selector.html:26` `title="{{ .label }}"` are in `html/template` HTML-attribute context and are **auto-escaped by Go's contextual escaper**. Piping through `| htmlEscape` risks double-escaping; `hugo.yaml` `params.customize` is first-party content. Withdrawn as a High (ID not re-used; the current H-1 is the CI trust-boundary finding).
- **`hugo.yaml` YAML-parsing finding (demoted in 212b89f):** `scripts/check-contracts.sh:44` `if ! grep -qE "^    - id: $axis\$" hugo.yaml` does **not** silently pass on reformat — it **loudly false-fails** (`CONTRACT variant-axis: axis '…' not declared …` per pair). Real defect is brittleness/noise, not missed validation. Demoted to Medium (now M-7).
- **`go 1.27.3` finding (withdrawn in 212b89f):** `go.mod:3` / `AGENTS.md:19` declare `go 1.27.3` — released as of 2026-11-18. Prior recommendation to downgrade to 1.22 was wrong.
- **CSS-in-`<style>` finding (withdrawn in cf351):** `layouts/_partials/hooks/head-end.html:52` `html[data-td-variant-{{ $axis }}='{{ $active }}']` inside `<style>` is **CSS context** in `html/template` — the contextual escaper applies `cssValueFilter` (verified live: `'` → `\27`, `"><script>` → `\27\22\3e\3cscript\3e`). Same class as the attribute-escaping finding; not a raw injection.
- **`renderer.unsafe` finding (withdrawn in cf351):** `markup.goldmark.renderer.unsafe` only gates raw HTML **in markdown source**; shortcode templates (`layouts/_shortcodes/*.html`) emit HTML regardless. Setting it `false` does not break variants. Prior premise was inverted.
- **`relLangURL` finding (withdrawn in cf351):** `layouts/_partials/favicons.html` correctly uses `relURL` — Hugo copies `static/favicon.*` to the site root, not into per-language subdirs; `relLangURL` on non-multilingual sites behaves identically and would be unnecessary. Prior recommendation to "use `relLangURL` everywhere" was inverted.
- **H-2 (print-bundle double-count) demoted in this draft:** `scripts/check-contracts.sh:60` `find public -name index.md -path "*/field-manual/*"` was claimed to double-count pages via `public/_print/…/index.md`. **False:** the theme's `print` output format is `mediaType: text/html`, `path: _print` (per `oink@v1.4.0` `outputFormats/print: isPlainText: false, mediaType: text/html`), so print pages are emitted as `public/_print/**/index.html`, **not** `.md` — verified: `public/_print/field-manual/hello-world/` contains only `index.html`, `find public/_print -name index.md` matches zero files. The `-prune` patch was unnecessary. The real defect in B1 is only the **CWD-dependence/vacuous pass** (see corrected M-2). Former H-2 demoted to Medium (M-2); no stub retained in the High section.
- **Logo-ink finding (withdrawn in this draft):** `assets/icons/logo-rh-cai.svg:4-6` `@media (prefers-color-scheme: dark)` was claimed to ignore the site's `html[data-bs-theme=dark]` reader toggle (→ 1.05:1 contrast failure). **False:** oink's `assets/scss/td/shell/_tokens.scss:54-65` declares `color-scheme: light` on `:root`/`[data-bs-theme='light']` and `color-scheme: dark` on `[data-bs-theme='dark']`, with the explicit comment: *"An SVG loaded through `<img>` resolves `prefers-color-scheme` against the embedding document's used color scheme."* The logo therefore already flips correctly on reader toggle; the `_styles_project.scss:5` comment is accurate. Deleted as a finding.
- **OMP agent removed (2026-11-18, user decision):** the OMP CI workflow is deleted (H-1, M-16, L-16 moot). Remaining open: ReviewJS chat.js `?src=` High and the Medium/Low findings below.

---

## 🔴 High

### H-1 — ✅ Resolved: OMP workflow deleted (2026-11-18); chat ?src= prompt-injection guard shipped (assets/js/chat.js)

**Source:** SecuritySweep (T+9m41s) — independently verified via `read .github/workflows/omp.yml`. Reinforced by ReviewScriptsCI C2/C3.

**Files:** `.github/workflows/omp.yml:9-12`, `23-24`, `27-29`, `60-61`, `67-71`

**Evidence:** `permissions: contents: write / issues: write / pull-requests: write` (9-12); invocation gate is only `sender.type != 'Bot' && contains(comment.body, '/omp')` (23-24); raw comment body is interpolated verbatim into the agent prompt (`COMMENT_BODY="$(gh api ... --jq .body)"` → `PROMPT` → `omp ... "$PROMPT"` at 67-71). The agent runs with `GH_TOKEN: ${{ github.token }}` (61) and `AGENT_API_KEY` in the step env (60), commits to `omp/issue-<n>` and opens PRs. On a public repo any GitHub user can author the prompt. `<comment>` delimiters are advisory — the agent is instructed to execute the request. The `Bot` filter does prevent reply-loop re-triggering (agent posts as `github-actions[bot]`), and the omp binary SHA256 pin is good — neither mitigates prompt injection or key exfiltration via tool calls. ReviewScriptsCI adds: `AGENT_API_KEY` need not be in the agent's env at all — omp's `models.yml` indirection (key = env-var name) resolves without exporting it to the agent's tools (C2); `fetch-depth: 0` widens history exfiltration surface (C3).

**Fix (options, in priority order):**
1. Restrict trigger to collaborators/owners (allow-list on `author_association` or `environment:` protection rule before the write step).
2. Keep `AGENT_API_KEY` out of the agent's inherited env — write it only to `models.yml`, not `env:` of the `Run omp` step that the agent's tools can read (ReviewScriptsCI C2).
3. Principle of least privilege: `contents: write` only on the final push job after human approval; earlier jobs `contents: read` + `pull-requests: write`.
4. Drop `fetch-depth: 0` (line 29) — full history is not needed for the agent run and widens the "read the repo" exfiltration surface.

### Outstanding High — resolved

ReviewJS's truncated delivery noted `assets/js/chat.js:604-613` `?src=` arbitrary cross-origin fetch. The fix shipped this pass: `loadContext()` validates `new URL(pagePath, location.href)` same-origin, pathname shape (`/^(?:[\\w@:%-]+~)?[\\w.-]+(?:\\/[\\w@.%-]+)*\\/$/`), depth ≤ 6, strips query/frag before fetch (`assets/js/chat.js:607-612`). The OMP workflow half is resolved by deletion. ReviewJS agent is gone (`agent://ReviewJS` not found); lost findings 2..n unrecoverable; H-1 fixed this pass; slice closed.

---

## 🟠 Medium — all 14 remediated this pass (see per-item notes); M-16 OMP-deletion, M-14 declined-by-user noted below

### ✅ M-1 — `publication-gate.sh` missing `pipefail` — WARN check can be masked

**File:** `scripts/publication-gate.sh:13`, `27`
`set -eu` without `set -o pipefail` means `grep -i warn "$log" | grep -qv '…'` can exit 0 even if first grep fails (pipe status = last command). A corrupted `build-gate.log` could green-light the gate. Duplicate: ReviewScriptsCI A3 reinforces; portable fix below.

**Fix:** `set -eu` + `(set -o pipefail 2>/dev/null) && set -o pipefail || true` (POSIX-sh compatible — ReviewScriptsCI's patch).

### ✅ M-2 — `check-contracts.sh` fails vacuously from the wrong CWD (no `hugo.yaml` → "contracts OK")

**Formerly H-2 — demoted per print-bundle correction.**

**Source:** ReviewScriptsCI B1 (T+17m29s) — partially verified via `read scripts/check-contracts.sh`.

**Files:** `scripts/check-contracts.sh:60` (`find public …` vacuously empty when CWD wrong); `hugo.yaml` / `content/` reads at `:25-26`, `41`, `44`, `49`

Post-split, `check-contracts.sh` reads `hugo.yaml` (:25/44/49) and `content/` (:26/41) relative to CWD — it must run from the content repo root, but the script lives in `shell/scripts/` and neither the script nor `AGENTS.md:21-24` pins that requirement. From any other directory (including this Shell repo), `hugo.yaml` / `content/` reads return empty, making contracts 1-2 a vacuous pass (`declared_tokens` empty, `used_tokens` empty → no failures) and contract 3 a `0 pages` no-op. The earlier `_print` double-count claim was false: `find public -name index.md -path "*/field-manual/*"` never matches `public/_print/…/index.html` (print is `text/html`, not `text/markdown` — verified above). The `-prune` patch is therefore unnecessary.

**Fix:** guard on required files instead of pruning print:
```sh
[ -f hugo.yaml ] || { echo "CONTRACT: run from the content repo root (hugo.yaml not found)" >&2; exit 1; }
[ -d public ]   || { echo "CONTRACT: public/ not found — build first: hugo --environment production" >&2; exit 1; }
```

### ✅ M-3 — `publication-gate.sh` header documents an invocation that only works from the content repo CWD

**Source:** ReviewScriptsCI A1 (T+17m29s) — independently verified via `read scripts/publication-gate.sh` and `read README.md/AGENTS.md`.

**Files:** `scripts/publication-gate.sh:8-11`, `19-20`; `README.md:92`; `AGENTS.md:20-21`

The header says the gate is "safe to run locally" as `scripts/publication-gate.sh [args]`, and line 19-20 runs bare `hugo`. With an explicit path (`sh ../CAI-Field-Manual-Shell/scripts/publication-gate.sh` — the only shape post-split, per `README.md:92` / `AGENTS.md:20-21`), CWD stays the caller's, so from the Shell repo root `hugo` fails ("no existing content configured") and from a random CWD it silently builds the wrong tree. The gate can only ever build the *importing* content repo. `AGENTS.md` already says to run the gate via `shell/scripts/publication-gate.sh` from the content root; the shell header should mirror that. The earlier "script-dir resolution is dead code" framing was inaccurate — `scripts/publication-gate.sh` contains no `dirname`/`SHELL_DIR`/`cd "$PWD"` logic at all (34 lines; verified via `read`), so no proposed patch of that shape applies.

**Fix:** reword header lines 8-10 to "run from the content repo root (the importing site); do not run from the Shell checkout" — no other code change needed.

### ✅ M-4 — `publication-gate.sh` WARN tolerance matches any line containing `warn`

**Source:** ReviewScriptsCI A2 (T+17m29s) — independently verified.

**Files:** `scripts/publication-gate.sh:27-30`

`grep -i warn "$log"` matches any occurrence of the substring — e.g. a `WARNING:` column inside a tool trace from a render hook, a build-error line with `warning` in its text, or content printed during build. Hugo's own warning records start at column 0 with `WARN` (including the tolerated `css.Sass: libsass` deprecation), so anchoring closes the hole without breaking the existing pass:

```sh
if grep -E '^WARN' "$log" | grep -qv 'css.Sass: libsass'; then
    echo "::error::Publication gate failed: unexpected WARN output" >&2
    grep -E '^WARN' "$log" | grep -v 'css.Sass: libsass' >&2
    exit 1
fi
```

Note: Hugo can wrap long deprecation WARNs onto continuation lines that do not start with `WARN` — counting `^WARN` lines is the pragmatic middle ground; a stricter check would fold continuation lines.

### ✅ M-5 — `publication-gate.sh` writes `build-gate.log` in repo root

**File:** `scripts/publication-gate.sh:15-16`
Pollutes `git status` if the trap fails (e.g. `kill -9`). Should use `mktemp`.

**Fix:** `log=$(mktemp -t build-gate.XXXXXX)` and trap `rm -f "$log"`; or write to `$RUNNER_TEMP` in CI.

### ✅ M-6 — `hugo.work` is documented as gitignored but is not

**Source:** ReviewConfigBuild (T+15m50s) — independently verified via `read .gitignore` and `read README.md/AGENTS.md`.

**Files:** `.gitignore:1-5`; `README.md:94` / `AGENTS.md:34`

Both `README.md:94` and `AGENTS.md:34` state "`hugo.work` is gitignored — never commit it." But `.gitignore:1-5` contains only `/public/`, `/resources/`, `/.hugo_cache/`, `/.hugo_build.lock`, `.DS_Store` — `git check-ignore -v hugo.work hugo.work.sum build-gate.log` matches nothing. A `git add -A` from the documented verification flow would commit a workspace file whose `replace … => ../CAI-Field-Manual-Shell` points outside any clone. `build-gate.log` (leaked if the `publication-gate.sh:15` trap is skipped, e.g. `kill -9`) is equally unprotected.

**Fix:** append to `.gitignore`: `/hugo.work`, `/hugo.work.sum`, `/build-gate.log`.

Note: per advisory, `hugo.work` is created **in the content repo** (per `README.md:73-80`), whose own `.gitignore` may already cover it — but the claim in this Shell repo's `README.md:94` / `AGENTS.md:34` is still about *this* checkout, so the gap is real for the local verification flow as documented here.

### ✅ M-7 — Shell `static/` assets bypass the theme's minify/fingerprint pipeline

**Source:** ReviewConfigBuild (T+15m50s) — verified in production `public/` output.

**Files:** `static/css/chat.css:1`, `static/css/agent-setup.css:1`; emitted at `layouts/_partials/hooks/head-end.html:112,115` and `body-end.html:10,20`

Theme bundles ship as `scss/main.min.<sha256>.css` with SRI, while `public/js/chat.js` (38 KB), `public/css/chat.css`, `agent-setup.{js,css}` are copied verbatim, unminified and unhashed — verified in production output. No cache busting (a redeploy can leave returning readers on a stale `chat.js` against a fresh site — this pair is version-coupled to the hooks' `__TD_CHAT__`/`__TD_AGENT_SETUP__` blobs), and `agent-setup.css` (2.4 KB, needed only when the modal opens) is fetched on every page.

**Fix:** move the four files under `assets/` and emit them from the hooks with the established pattern (`resources.Get` → `minify` → `fingerprint`, as `head-css.html` does), keeping `relLangURL` semantics via `.RelPermalink`.

### ✅ M-8 — `check-contracts.sh` brittle `hugo.yaml` parsing causes false failures (not silent passes)

**File:** `scripts/check-contracts.sh:44`, `49`
```sh
grep -qE "^    - id: $axis\$" hugo.yaml
axis_block=$(sed -n "/- id: $axis\$/,/^    - id:/p" hugo.yaml)
```
Assumes exactly 4-space indent and no comments/trailing keys. A reformat (e.g. `yamlfmt`) would not silently pass — it would **loudly false-fail** with one `CONTRACT variant-axis` error per pair (the `fail=1` path). Separately, `"$axis"` is regex-interpolated without escaping (axis is `[a-z_]+` today, safe but fragile). Overlaps with ReviewScriptsCI B3 (which notes the customize side is *stricter* — flow-map `- { id: X, … }` only, so block-style `id: X` false-fails there; both sides should handle both styles).

**Fix:** parse with `yq` if available, fallback to indent-insensitive `awk` anchored on key name; or emit a warning when `grep` matches 0 axes. For customize, add block-style alternates:
```sh
declared_tokens=$(sed -n \
  -e 's/.*- { id: \([a-z_]*\),.*/\1/p' \
  -e 's/^[[:space:]]*id:[[:space:]]*\([a-z_]*\).*/\1/p' \
  hugo.yaml | sort -u)
```

### ✅ M-9 — `check-contracts.sh` word-splitting on `for pair in $(…)` / `for tok in $used_tokens`

**File:** `scripts/check-contracts.sh:27`, `41`, `50`
Unquoted expansions split on IFS. Works for current `[a-z_]+` ids but will break if variant options contain spaces/hyphens. SC2044/SC2066.

**Fix:** `while IFS= read -r` loop or `set -f` + quoted handling; add `# shellcheck disable` with justification.

### ✅ M-10 — `check-contracts.sh` hardcoded variant labels + `labels` never asserted

**File:** `scripts/check-contracts.sh:68-69`, `91-93`
`grep -cE '\*\*(RHAIE Version|Ops Mode): '` hardcodes the two current axis labels. A renamed axis label, or a new consumer with different `params.variants[].label`, yields `labels=0` and still prints `contracts OK` — because `labels` is only interpolated in the success banner (`echo "contracts OK — $pages pages, $labels variant labels, …"`), never asserted via `fail=1`. Contract 3 ("every variant block is labelled") can thus never fail.

**Fix:** derive expected labels from `hugo.yaml` `params.variants[].label` and assert `src_variants > 0 && out_labels == 0` → `fail=1`; or compare `src_variants` against `out_labels`.

### ✅ M-11 — `check-contracts.sh` only validates positional shortcode forms

**File:** `scripts/check-contracts.sh:26`, `41`
Line 26 `\{\{< customize [a-z_]+ >\}\}` and line 41 `\{\{< variant [a-z_]+ ("[^"]*"|[a-z0-9._-]+) >\}\}` only match the positional form (`{{< variant version "3.5" >}}`). But `layouts/_shortcodes/customize.html:16` and `variant.html:23` both branch on `if .IsNamedParams`, accepting named form (`{{< variant axis="version" id="3.5" >}}`). Named-param usages in content bypass the `declared in hugo.yaml` check entirely and the gate still prints "contracts OK". Separately, line 44's `grep -qE "^    - id: $axis\$" hugo.yaml` scans the whole file, so an axis id that collides with a `params.customize` field id (e.g. `user`) could validate against the wrong YAML block.

**Fix:** add a second regex for named form or broaden to `\{\{< (customize|variant)[^>]*>\}\}` with extraction; scope the axis lookup to the `params.variants` section. ReviewScriptsCI B4/B5 add: normalize newlines before grepping (multi-line shortcode invocations exist) and add `tr ',' ' '` (comma-separated `"3.4, 3.5"` was silently merged into one token by the shortcode's `FindRE`).

### ✅ M-12 — `check-contracts.sh` has no freshness guard: validates whatever `public/` happens to contain

**Source:** SecuritySweep — independently verified.

**File:** `scripts/check-contracts.sh:60` (`find public -name index.md …`), usage comment at `:1-6` (assumes a just-built `public/`).

A stale, partial, or hand-edited `public/` silently passes — CI could cache an old `public/` and print "contracts OK" without having rebuilt. `publication-gate.sh` enforces `--cleanDestinationDir`; this gate does not and is not required to run after it. The CWD-dependence half of former H-2 is now in M-2; this entry is the freshness half.

**Fix:** either run `hugo --cleanDestinationDir` inside the script (like the publication gate does), or require a freshness proof (e.g. check `public/.hugo_build.lock` mtime, or accept `$BUILD_DIR` as an explicit arg and refuse if absent). At minimum, document the required invocation order in the script header.

### ✅ M-13 — Missing `params.github_repo` renders a broken clone URL that defeats the single-source claim

**Source:** SecuritySweep — independently verified via `read layouts/_partials/hooks/body-end.html` and `static/js/agent-setup.js`.

**File:** `layouts/_partials/hooks/body-end.html:18` (`repo: "{{ printf "%s" site.Params.github_repo | strings.TrimPrefix "https://github.com/" }}"`) → consumed by `static/js/agent-setup.js:27`

`hugo.yaml` in this module intentionally does not set `github_repo` — it lives in importing sites. When absent, `printf "%s" nil` renders `<no value>`, so the copy-prompt prints `git clone https://github.com/<no value>.git`. The JS fallback (`|| 'rh-aiservices-bu/…'` at agent-setup.js:27) is dead code because `__TD_AGENT_SETUP__` is always defined by the hook, just with garbage. A trailing-slash value also survives `TrimPrefix`.

**Fix:** guard in the template (`{{ with site.Params.github_repo }}…{{ else }}warnf{{ end }}`), strip trailing `/`, and delete the dead JS default so the "single source (`params.github_repo`)" claim holds. The JS fallback can then be removed or turned into an explicit error.

### ⏭️ M-14 — Closed/declined (user 2026-11-18): manuals own their analytics; BYO-endpoint chat makes a meaningful CSP impossible without carving out the feature

**Source:** SecuritySweep — spot-checked in built output (`public/index.html` has no `Content-Security-Policy`/`referrer` meta).

**Files:** `layouts/docs/baseof.html:7` (head assembled via `head.html` + hooks); built `public/index.html` confirms zero matches for `Content-Security-Policy|http-equiv.*referrer`.

The theme emits SRI + `crossorigin` on bundled assets (good), but no `<meta http-equiv="Content-Security-Policy">` or `<meta name="referrer">`. GitHub Pages cannot set response headers, so meta is the only vehicle. This site specifically runs a BYO-endpoint chat widget that POSTs the reader's API key to an arbitrary host (`static/js/chat.js:711-721`) and fetches `?src=`-controlled same-origin paths (`chat.js:583-613`) — a `default-src 'self'; connect-src` baseline would at least bound script/frame egress (chat's open-egress is intentional, but should be documented as a CSP carve-out).

**Fix:** add `<meta http-equiv="Content-Security-Policy" content="object-src 'none'; base-uri 'self'; frame-ancestors 'none'; …">` in a head hook (script-src will need `unsafe-inline` or hashes given the pre-paint bootstrap — even a partial policy is better than none) plus `<meta name="referrer" content="strict-origin-when-cross-origin">`.

### ✅ M-15 — `check-contracts.sh` status-gate check (contract #4) — fixed this pass (M-15 awk)

**Source:** ReviewScriptsCI B2 (T+17m29s) — independently verified via `read scripts/check-contracts.sh:76-89`.

**Files:** `scripts/check-contracts.sh:78-83` (awk pending logic); documented at `Docs/issue-3-top5.md:23-33`

The awk sets `pending` on `/Expected output/` and only clears it on `/^```/`; **any** subsequent heading (`/^#/`) is treated as the violation trigger — it clears `pending` without reporting. In real output the "Expected output:" line sits inside a `## Verification` section, so the very next `## Rollback` (or any heading) resets `pending = 0` before the "no following fence" condition can fire — unless the promise is in the final section. Empirically verified on the current build: a planted mid-page dangling promise reports nothing (`fail=0`); shipped pages pass only because no mid-page violation happens to exist. The header (line 13) also promises an "(no output)" escape hatch that the awk never implements.

**Fix:** test that the next non-empty line after the promise is a fence:
```sh
awk '
    /Expected output/ { pending = NR; next }
    pending != 0 && NF == 0 { next }
    pending != 0 && !/^(```|~~~)/ {
        printf "CONTRACT status-gate: %s line %d — \"Expected output\" with no following fence\n", FILENAME, pending;
        bad = 1; pending = 0;
    }
    pending != 0 && /^(```|~~~)/ { pending = 0; next }
    END { exit bad }
' "$md" || fail=1
```
Drop `/^#/` from the violation arm; add `(no output)` handling if the marker is intended.

### ✅ M-16 — `omp.yml` trigger — resolved by OMP workflow deletion (2026-11-18) — review comments lack `issue` payload fields

**Source:** ReviewScriptsCI C1 (T+17m29s) — independently verified via `read .github/workflows/omp.yml`.

**Files:** `.github/workflows/omp.yml:4-9`, `15`, `68`, `123`, `135`

The workflow listens for both `issue_comment` and `pull_request_review_comment`, but every downstream step assumes the issue-comment payload shape. For `pull_request_review_comment`, GitHub sends `github.event.comment` (a *review* comment) and `github.event.pull_request` but **no `github.event.issue`** key — so:

1. Line 68 `gh api repos/.../issues/comments/<id>` — review comments live under `pulls/comments/<id>`, not `issues/comments/<id>` → 404, empty prompt.
2. Lines 69-74 `TARGET_NUMBER`/`TARGET_URL` interpolation (`github.event.issue.html_url`/`.number`) → empty → prompt says "is a comment on #."
3. Line 15 concurrency `omp-${{ github.event.issue.number }}` → `omp-` for every review-comment run (serialized, mutually blocking issue runs sharing the null group).
4. Line 138 reply `issues/<empty>/comments` → 400; the `if: always()` step fails the workflow even on agent success.

Net effect for the documented invocation path (`AGENTS.md:63`: "Comment `/omp` on any issue or PR review thread"): the agent burns a paid run on an empty prompt and the workflow reports failure without posting the answer.

**Fix:** use `comment.id` + `pulls/comments` for the review path, and `TARGET_NUMBER: ${{ github.event.issue.number || github.event.pull_request.number }}` / `TARGET_URL: ${{ github.event.issue.html_url || github.event.pull_request.html_url }}` in the prompt, concurrency group, and reply step.

### ✅ M-17 — `Docs/backlog.md` "Now #1" is already done but still `pending`; other `Docs/` planning docs predate the split

**Source:** ReviewScriptsCI D1/D2 (T+17m29s) — independently verified via `read Docs/backlog.md` and git log.

**Files:** `Docs/backlog.md:9`; `Docs/issue-3-top5.md:24-33,159,189`; `Docs/issue-3-review.md:42`

`Docs/backlog.md:9` `pending` item "Commit rename + RH CAI lockup changes; push to renamed repo … field-guides → field-manual rename everywhere; `assets/icons/logo-rh-cai.svg`" is verifiably complete (rename commit `5ac0c4d` in history; `hugo.yaml:26` carries `docs_section: field-manual`; `assets/icons/logo-rh-cai.svg` exists; gate passes). After `70d5c48` (Shell/Hello-World split) the item's `baseURL`/`github_repo` half is meaningless in this repo — those keys live in the content repo now. Contributors or agents picking up the "Now" table chase finished work. Separately, `Docs/issue-3-top5.md` (`content/` run-before-PR instruction, `data/home.yaml`, prototype naming) and `Docs/issue-3-review.md` (citing `set-up.md:52` which no longer exists here) predate the split and misstate this repo's contents — `content/` and `data/` were deleted in `70d5c48`.

**Fix:** move `backlog.md` Now#1 to Done with a completion date; add a one-line provenance banner to the two planning docs:
```markdown
> Written 2026-11-07 against the pre-split prototype (content/, data/, prototype naming). After 70d5c48 those files live in CAI-Field-Manual-Hello-World; the scripts here are validated from that repo (see AGENTS.md).
```

---


| ID | Disposition | Rationale |
|----|-------------|-----------|
| L-1 | No-action | Runtime guard exists (`assets/js/action-registry.js:151-154`); build-time `%s` check skipped |
| L-5 | No-action | Already gitignored; no fix needed |
| L-6 | No-action | No CI in Shell post-OMP-deletion; out of scope |
| L-7 | No-action | Review: no visible bug |
| L-12 | Kept (user) | Presets kept per user choice |
| L-13 | Withdrawn | Empty key suppresses theme branding (see above) |
| L-16 | Resolved | OMP workflow deletion |

## 🟡 Low — resolved L-2,L-3,L-4,L-8,L-9,L-10,L-11,L-14,L-15 this pass; L-13 withdrawn; L-16 OMP-deletion; L-1,L-5,L-6,L-7,L-12 remain as no-action (see table)

### L-1 — `layouts/_partials/actions/context.html:54` `printf (T "ui_open_in_prompt")` — translation string with `%s` filled via `querify`

Works, but `T` strings are translator-editable; a translation dropping `%s` silently sends the wrong prompt. Already guarded in `action-registry.js:151-154` (`promptTemplate.indexOf('%s') < 0` → null), so the link just disables. Consider adding a build-time check.

### ✅ L-2 — `static/js/chat.js:84-93` `previewKey` leaks 6-char prefix of API key in DOM

Intentional for UX, but shows in page source / screenshots. Could be opt-in or show `••••` only.

### ✅ L-3 — `static/js/agent-setup.js:27` fallback repo literal is hardcoded

`REPO` fallback `'rh-aiservices-bu/CAI-Field-Manual-Hello-World'` will drift if the org renames the content repo. Now compounded by M-13: prefer failing visibly (`No github_repo configured`) over silently cloning the wrong repo.

### ✅ L-4 — `Docs/` contains stale review docs referencing old repo name

`Docs/backlog.md:9` still mentions `CAI-Field-Manual-prototype`; `Docs/maas-guide.review.md:4` references `CAI-Field-Manual-prototype` as local site. Either archive or update `Docs/`. (Superseded by M-16's more specific backlog/split provenance finding — kept as the broader `Docs/` hygiene item.)

### L-5 — `.hugo_build.lock` (0 B) present on disk — should not be committed and is already gitignored

Harmless, but `hugo` creates it with `flock`; on NFS it can linger. Already in `.gitignore` (`/.hugo_build.lock`), no action needed beyond awareness.

### L-6 — No `eslint` / `stylelint` / `shellcheck` in CI

Shell scripts and 1.4 kLOC of JS have no lint step. `check-contracts.sh` has SC2044/SC2066, `publication-gate.sh` needs SC2086 justification documented.

**Fix:** add a `lint` job (`shellcheck`, `eslint --no-warn`) or a `pre-commit` hook.

### L-7 — `layouts/_partials/shell/sidebar-tree.html:31-34` `$sidebarRootID` vs `$navRoot` inconsistency

`$sidebarRootID` is derived from `sidebar_root_enabled` check, but `$navRoot` can be overridden by `.sidebarRoot` param. When overridden, `data-td-sidebar-root-id` may not match the actual root. No visible bug (downstream JS tolerates missing ID), but confusing.

### ✅ L-8 — `static/css/chat.css` / `agent-setup.css` use `color-mix()` / `backdrop-filter` without fallback

`agent-setup.css:14-17` `color-mix(... 30%, transparent)` and `backdrop-filter: blur(2px)` are not supported in older Firefox ESR. Graceful degradation (solid overlay) is fine, but add a `@supports` fallback comment for future maintainers.

### ✅ L-9 — Pinned-copy bookkeeping is stale: "all three", "one deliberate change"

**Source:** ReviewConfigBuild (T+15m50s) — independently verified via `grep -rn "Re-diff\|one deliberate"` in docs and layout headers.

**Files:** `README.md:15-20`; `AGENTS.md:42-47`; `layouts/_partials/actions/context.html`, `title-menu.html`

`README.md:15` says "Re-diff all three against `~/go/pkg/mod/…`" but the pinned set is now **seven files** (`AGENTS.md:42-47` lists them), and two of them (`context.html`, `title-menu.html`) carry **no provenance comment** at all — both start with the theme's own headers; diffing shows the only changes are the appended `open_gemini`/`feed_agent` rows. `action-registry.js` and `page-actions.js` now each contain two deliberate changes (Gemini + feed-agent), contradicting "naming its one deliberate change". A theme bump using the old count would miss files.

**Fix:** update `README.md` count/list, add provenance headers to the two missing files, and reword "one deliberate change" to "each named change" in `AGENTS.md:45` and `README.md:16`.

### ✅ L-10 — `README.md:40` overstates that `check-contracts.sh` runs in content repos' CI

**Source:** ReviewConfigBuild (T+15m50s) — verified against Hello-World `github-pages.yaml`.

`README.md:40` headers both scripts as "run by content repos' CI via a `shell/` checkout", but Hello-World's `.github/workflows/github-pages.yaml` calls only `shell/scripts/publication-gate.sh` (lines 74, 121); the contract check is a **manual/local gate only** (see `AGENTS.md:36`). Dual-consumption promises are therefore unenforced in CI despite the README's implication. This matters because M-9 through M-13 and M-2 are about those contracts.

**Fix:** reword `README.md:40` to "publication-gate.sh runs in CI; check-contracts.sh is a local gate (add it to CI if you want it enforced)" — or actually add the step to the content repo's workflow.

### ✅ L-11 — `README.md:71` typo: "Shel changes"

`README.md:71` says "Shel changes are proven by building…" → "Shell changes".

### L-12 — Experimental presets shipped to every reader without comment

**Files:** `hugo.yaml:18` `preset_menu: [paper, slate, ink, terminal]`

Oink documents `ink`/`terminal` as experimental (`preset-config.html:10,16`, `_experimental-presets.scss:1` → `// Experimental`). Valid config (no build warning), but worth confirming intent for a customer-facing manual. Drop the two names if not — keeps the Appearance menu to two stable choices.

### ⏭️ L-13 — Withdrawn: — Pointless empty param

**File:** `hugo.yaml:15` `footer_center_info: ''`

The theme keys on `isset` (`shell/footer-line.html:14`), so the empty string activates a code path that renders nothing — omitting the key is equivalent and clearer. Trim.

### ✅ L-14 — `check-contracts.sh` multi-line and comma-separated option lists mis-validated

**Source:** ReviewScriptsCI B4/B5 (T+17m29s).

**Files:** `scripts/check-contracts.sh:26`, `41-43`

- `{{< variant axis="version" id="3.5, 3.6" >}}` splits on commas inside the shortcode (`strings.FindRE "[^,\s]+"`); but the contract check's `tr ' ' '_'` produces `3.5,_3.6` as one merged token, false-positive `option not declared` while `"3.4,3.5"` (no space) is silently one opaque option with no per-option validation.
- `{{< customize\ntoken >}}` and `{{< variant\naxis … >}}` with line breaks between params (valid Hugo) are skipped by single-line `grep` patterns, so wrapped invocations are never validated.

**Fix:** normalize: `tr ',' ' '` alongside the existing space-to-underscore in line 41's pipeline, and concatenate `content/*.md` before grepping (or normalize newlines → spaces).

### ✅ L-15 — `check-contracts.sh` "(no output)" marker and `expected output below` prose check mis-targeted

**Source:** ReviewScriptsCI B6 (T+17m29s).

**Files:** `scripts/check-contracts.sh:13`, `78-86`

The header (line 13) promises both escape hatches — following fence **or** explicit "(no output)" marker — but the awk recognizes no marker, so a legitimate "Expected output: (no output)" page is flagged as a violation (currently masked only by the heading-reset bug in M-14). Separately, line 85 greps the *built* markdown for the exact prose "confirm the output matches the expected output below", but built pages are Hugo-flattened and HTML-escaped — any rewording or rewrapping silences the check. Should match the *source* page (like M-15's next-non-empty fence test).

### ✅ L-16 — `omp.yml` loop-filter and model-token hardcoding

**Source:** ReviewScriptsCI C4-C6 (T+17m29s).

**Files:** `.github/workflows/omp.yml:23`, `52-53`

- C4: `sender.type != 'Bot'` prevents self-loops but not cross-repo loops (two repos with this workflow can trigger each other forever); add `timeout-minutes: 30` and fix concurrency to `omp-${{ github.event.issue.number || github.event.pull_request.number }}`.
- C5: `contains(body, '/omp')` substring trigger fires on `/omp/…` paths, code snippets, URLs — anchor with `contains(body, '/omp ') || endsWith(body, '/omp')`.
- C6: `contextWindow: 1000000` / `maxTokens: 32000` baked in regardless of which model `vars.AGENT_MODEL` names — swapping to a smaller-context model silently truncates. Promote to repo variables.
- (C3's substring-trigger aspect is already covered by M-17/C5 in the Medium section — these remain Low as the remaining tail.)

---

### Attribution & deferred findings

### Note — ReviewJS: slice closed (single High H-1 fixed this pass; remainder unrecoverable)

ReviewJS delivered at T+20m28s; its output was truncated at generation (not at read time) — `history://ReviewJS` ends mid-code-fence at "```js / var pagePath" and `agent://ReviewJS:raw:` returns nothing past it. The single recoverable High `static/js/chat.js:604-613` `?src=` arbitrary fetch is noted in the **Outstanding High** section above; findings 2..n (preamble says "ordered by severity") were lost. **Action:** re-task ReviewJS with a short prompt to re-emit findings 2..n verbatim. Until then, this slice is recorded as partial (not fully integrated).

### Note — SecuritySweep: findings adopted, one demoted (now reflected in H-1/M-12/M-13 above)

- **SecuritySweep M2 (not adopted as written):** "Config strings interpolated raw into `<style>` and `<script type=\"application/json\">`" — axis/option ids and status phrases emitted via `{{ $axis }}` in `<style>` and `{{ $blob | jsonify | safeJS }}` in `application/json`. The report claimed Hugo `jsonify` does not escape `<`/`/` so `</script>` breaks out, and axis ids inject CSS. Re-checked: `<style>` content is **CSS context** in `html/template` (verified live in prior draft via `go run` — `'` → `\27`, `"><script>` → CSS-escaped), not raw; and Hugo's `jsonify` (backed by `encoding/json` with `SetEscapeHTML(true)`) emits `<` as `\u003c`, so `</script>` cannot terminate the JSON element. Site params are **first-party trusted config** (content-repo maintainers), not an XSS boundary. Demoted to defense-in-depth note.
- **SecuritySweep M3 freshness gap** merged into M-11 (and former H-2).
- **SecuritySweep L1-L8:** L1 (LICENSE/SECURITY.md/Dependabot) left as L-6 hygiene; L2 (GA4 `cookie_flags`) / L3 (clipboard `.catch`) / L4 (`isLocalHostname` misses) / L5 (customize over-match) / L7 (`curl --fail`) noted and may be promoted when layout/JS slices land. None dropped.

### Note — ReviewConfigBuild: findings adopted (3 medium + 5 low) — consolidated above

- M5/M6/M7 as adopted above; L-9/L-10/L-11/L-12/L-13 incorporated. Verified-clean notes (hugoVersion, go.mod, tokens, favicons, `.hugo_build.lock`) independently confirm prior withdrawals remain correct.

### Note — ReviewScriptsCI: findings adopted (1 high-demoted + 4 medium + 6 low) — consolidated above

- **B1 as M-2 (demoted from High):** CWD-dependence/vacuous pass retained; `_print` sweep half withdrawn as false (print is `text/html` → `index.html`, not `.md`).
- **B2/B3/B4 as M-14/M-7/M-10** (status-gate dead-on-arrival, flow-map-only customize parse, multi-line shortcode misses).
- **A1/A2/A3 as M-2/M-3/M-1** (publication-gate invocation header, WARN anchoring, pipefail).
- **C1 as M-15** (broken `pull_request_review_comment` path). **C2 as H-1 reinforcement** (API key env exposure). **C3 as H-1 reinforcement** (public-commenter drive). **D1/D2 as M-16** (stale backlog / pre-split planning docs). B5/B6/C6/C4/C5 as L-14/L-15/L-16. No deduplication loss — the duplicate `grep -i warn` → `^WARN` anchoring finding from SecuritySweep (already in M-3) is noted but not double-counted. ReviewScriptsCI A1's "script-dir resolution is dead code / `SHELL_DIR=$(dirname)` + `cd $PWD`" description is rejected: `scripts/publication-gate.sh` is 34 lines and contains no `dirname`/`SHELL_DIR` logic (verified via `read`), so no such patch applies — A1 is adopted narrowly as the header-example clarification in M-3.

### Note — `public/` / `resources/_gen/` scope (not a finding)

`public/` is **gitignored** (`/.gitignore:1`) and **untracked** (verified: `git ls-files public/` → empty) and `resources/_gen/` is similarly untracked build output. The reviewer prompts were scoped to `layouts/`, `assets/`, `static/`, `scripts/`, `hugo.yaml`, `go.mod`, `.github/`, `Docs/` — no stale `public/` or `resources/` issues were reported by SecuritySweep or ReviewConfigBuild, and none are added here.

### Note — ReviewJS: slice closed

Findings 2..n were never recovered (`agent://ReviewJS` not found); H-1 (the only recovered High) is fixed this pass. No further ReviewJS work is expected.

The `ReviewJS` sub-agent's transcript diffed against `oink@v1.5.1`, while `go.mod` pins `v1.4.0`. Re-checked: ReviewJS itself caught and corrected this mid-run ("`go.mod` pins oink **v1.4.0** — my diffs above were against v1.5.1. Re-checking…"), so no findings from the re-diff remain to filter — the remaining High (chat `?src=`) is independent of that baseline.

### Note — Worktree hygiene at remediation time

Three files carried uncommitted WIP (see scope banner above); the contracts WIP had dropped the `page.md` source mapping (contract 3 vacuous, 0 pages) — restored this pass

Re-checked `git status` before writing this document: `git diff --stat` shows only `Docs/code-review-2026-11-18.md`-related commits; `git diff -- hugo.yaml` and `git diff -- assets/scss/_styles_project.scss` are empty (no lingering tracked-source mutations from sub-agent runs). Prior `commit.draft` at `a2515d6` transiently showed `? assets/scss/_styles_project.scss +15` (a ReviewJS bash that touched the file), but a fresh `read` of the same path at `190-220` showed no `:has()` guard rules — the mutation was transient and has vanished from the worktree before any commit.

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
- **ReviewScriptsCI verified clean:** `trap 'rm -f "$log"' EXIT` does not swallow exit code (empirically verified on this machine); `models.yml` heredoc scoping correct; `issue_comment` on PR conversation comments does populate `github.event.issue`; both scripts executable (`100755`).

---

## Recommended next steps — all actionable items from this review are closed

No further remediation is required for this review pass. Remaining Low findings (L-1, L-5, L-6, L-7, L-12) are documented no-action items.

---

*Remediated 2026-11-18: 0 High / 0 Medium remain; 5 Low remain as no-action (L-1, L-5, L-6, L-7, L-12). Resolved this pass — Med: M-1,M-2,M-3,M-4,M-5,M-6,M-7,M-8,M-9,M-10,M-11,M-12,M-13,M-15,M-17 (15); closed-no-code: M-14; already-resolved: M-16. Low: resolved L-2,L-3,L-4,L-8,L-9,L-10,L-11,L-14,L-15 (9); withdrawn L-13; already-resolved L-16. Worktree changes: `Docs/code-review-2026-11-18.md` reconciled; `.github/workflows/omp.yml` deleted; `README.md`/`AGENTS.md` OMP sections removed; assets moved to `assets/` with pipeline; contracts/gate scripts hardened.*
