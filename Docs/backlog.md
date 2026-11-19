# Backlog

Working list of pending work for this repo. New items go at the bottom of their priority table.

## Now

| # | Item | Status | Notes |
|---|------|--------|-------|

## Next

| 5 | Fix status-gate EOF bypass in check-contracts.sh | pending | Medium — scripts/check-contracts.sh:193 — EOF promise exits 0 because END never checks pending (found by Slice C sub-agent review 2026-11-19) |
| 6 | Harden variant axis/option parsing against YAML reformats | pending | Medium — scripts/check-contracts.sh:96,101 — brittle 4-space/whole-file grep+sed false-fails on comments or reformat (found by Slice C sub-agent review 2026-11-19) |

| 7 | Fix label extraction for flow-map variant axes (latent) | pending | Low — scripts/check-contracts.sh:143 — flow-map axis label not extracted (passes verbatim into labels_re), would under-count if that style were used; Hello-World hugo.yaml:79-93 is block-style today so no live fail — fold with item 6 if desired (found by Slice C sub-agent review 2026-11-19) |
| 8 | Restore RTL stylesheet SRI and correct README doc | pending | Low — layouts/_partials/head-css.html:61 — `with .Data.Integrity` reads page (nil) not $rtl so RTL link loses integrity+crossorigin; also README.md:30 claims "fixes RTL Integrity scoping" (found by Slice B/E/D sub-agent review 2026-11-19) |
| 9 | Fix README re-diff list (Re-diff all eight) | pending | Low — README.md:26 — says 8 but enumerates 7 bullets, omitting layouts/docs/baseof.html (found by Slice B/D sub-agent review 2026-11-19) |
| 10 | Handle clipboard copy failure in agent-setup dialog | pending | Low — assets/js/agent-setup.js:137 — missing .catch on copy promise leaves silent failure and unhandled rejection (found by Slice A sub-agent review 2026-11-19) |
| 11 | Anchor option-id check against exact id | pending | Low — scripts/check-contracts.sh:104 — substring case *id: '$opt'* matches prefix of longer id, e.g. 3.5 vs 3.5.1 (found by Slice C sub-agent review 2026-11-19) |
| 12 | Fix page discovery case-sensitivity and word-splitting | pending | Low — scripts/check-contracts.sh:120,132,145 — space-joined manual_mds splits on spaces; urlized public/ names mismatched on Linux CI (found by Slice C sub-agent review 2026-11-19) |
| 13 | Remove dead docs_section and LLMS comments | pending | Low — scripts/check-contracts.sh:48-54 — docs_section computed but never filters; LLMS bundle check promised in comments never exists (found by Slice C sub-agent review 2026-11-19) |

## Done

| # | Item | Completed | Notes |
|---|------|-----------|-------|
| 1 | Commit rename + RH CAI lockup changes; push to renamed repo | 2026-10-30 | commit 5ac0c4d (field-guides → field-manual rename, RH CAI lockup); baseURL/github_repo half moved to Hello-World by 70d5c48 |
| 2 | *Feed it to my AI Agent* page-action/palette row + copy-prompt modal (Claude Code / Codex) | 2026-10-31 | assets/js/agent-setup.js + assets/css/agent-setup.css wired via body-end/head-end hooks; row is registered with the assistant actions in layouts/_partials/actions/context.html and uses url "#agent-prompt", so it appears directly below Open Gemini in both the page action menu and palette; the JS watches the fragment hash, opens the modal, clears the hash so the action can re-fire; clone URL from params.github_repo via __TD_AGENT_SETUP__ blob (chat.js llmsFull pattern); copy via theme OinkClipboard (dialog-aware execCommand fallback); prompt points agent at README.md; gate clean, browser-verified |
| 3 | All images visible in the rendered view have a 1px visible outline | 2026-11-18 | assets/scss/_styles_project.scss sanctioned extension (272754f): `:where(.td-content) img { border: 1px solid var(--td-brand-line-strong); }` (line-strong 0.22/0.55 visible across paper/slate/ink/terminal × light/dark) + gallery suppression; verified via Hello-World hugo.work production build + showcase gallery; gate clean |
| 4 | GitHub Pages: Settings → Pages → Source = GitHub Actions (admin, one-time) | 2026-11-18 | Stale — already live at https://rh-aiservices-bu.github.io/CAI-Field-Manual-Hello-World/ (HTTP 200, verified 2026-11-18); required before the site publishes — now done |

### Review log — 2026-11-19 (5 sub-agent slices)

- Slice A (JS runtime): verified-clean — ?src guard holds (origin+regex+depth+u.pathname), __TD_*__ blobs jsonify-safe, BYO-key preview masked, hook guards prevent duplicate injection, action-registry %s guard consistent, pinned JS re-diffs clean (only open_gemini/feed_agent drift), CSS has no executable constructs; 1 Low found (item 10).
- Slice B (Layouts & provenance): verified-clean — baseof/sidebar-tree/pager-state/context/title-menu re-diffs match provenance headers exactly, favicons ↔ static/ exact, GA partial correctly gated, SCSS overlay pair internally consistent, shortcodes ↔ check-contracts belt-and-braces holds; 2 findings merged into items 8 and 9.
- Slice C (Scripts): verified-clean — publication-gate pipefail/mktemp/trap/^WARN hold, CWD guards hold, vacuous-pass guard holds, contract-1 token matcher correct, sh -n passes; shellcheck not installed on this machine; 6 findings logged as items 5,6,7,11,12,13 (2 Medium — item 5 new M-15 remainder, item 6 failed M-8 remediation; 4 Low — items 7,11,12,13); ^WARN continuation folding acknowledged as pragmatic middle ground per 2026-11-18:110 — no live fused-WARN bypass demonstrated (not logged).
- Slice D (Config & docs): verified-clean — go.mod v1.4.0 pin + go.sum hash match module cache, all hugo.yaml params have live consumers, provenance set vs tree matches AGENTS.md claims, .gitignore covers all documented flows, Docs banners present, .mailmap valid; 2 findings merged into items 8 and 9 (same root as Slice B).
- Slice E (Security): verified-clean — no secrets/tokens, SVG/favicon assets clean, GA4 anonymize_ip, blob JSON safe, chat egress key in Authorization header only, storage flows safe, H-1 workflow deletion confirmed, M-13 remediation holds; 1 finding merged into item 8 (same RTL SRI root as Slice B).
- Cross-slice dedup: RTL SRI defect appeared in B, D, E — merged into single item 8 (Low, latent LTR-only impact); README count appeared in B and D — merged into item 9; no High findings; no re-filed CLOSED dispositions (M-14 CSP, H-1 OMP, L-1/L-5/L-6/L-7/L-12/L-13 all honored).
