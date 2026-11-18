# Backlog

Working list of pending work for this repo. New items go at the bottom of their priority table.

## Now

| # | Item | Status | Notes |
|---|------|--------|-------|
| | | | |

## Next

| # | Item | Status | Notes |
|---|------|--------|-------|
| 1 | GitHub Pages: Settings → Pages → Source = GitHub Actions (admin, one-time) | pending | required before the site publishes |

## Later

| # | Item | Status | Notes |
|---|------|--------|-------|
| 1 | All images visible in the rendered view have a 1px visible outline | pending | CSS in assets/scss/_styles_project.scss (sanctioned extension point); scope: rendered content images (e.g. .td-content img), not chrome marks (nav logo, sidebar brand, icons); 1px solid using a theme border/ink token so it stays visible across paper/slate/ink/terminal presets and dark mode; verify via Hello-World hugo.work build + browser |

## Done

| # | Item | Completed | Notes |
|---|------|-----------|-------|
| 1 | Commit rename + RH CAI lockup changes; push to renamed repo | 2026-10-30 | commit 5ac0c4d (field-guides → field-manual rename, RH CAI lockup); baseURL/github_repo half moved to Hello-World by 70d5c48 |
| 2 | *Feed it to my AI Agent* page-action/palette row + copy-prompt modal (Claude Code / Codex) | 2026-10-31 | assets/js/agent-setup.js + assets/css/agent-setup.css wired via body-end/head-end hooks; row is registered with the assistant actions in layouts/_partials/actions/context.html and uses url "#agent-prompt", so it appears directly below Open Gemini in both the page action menu and palette; the JS watches the fragment hash, opens the modal, clears the hash so the action can re-fire; clone URL from params.github_repo via __TD_AGENT_SETUP__ blob (chat.js llmsFull pattern); copy via theme OinkClipboard (dialog-aware execCommand fallback); prompt points agent at README.md; gate clean, browser-verified |
