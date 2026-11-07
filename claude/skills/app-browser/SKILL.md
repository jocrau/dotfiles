---
name: app-browser
description: Look at and drive the repo's own running web app in a real browser with the agent-browser CLI - open its pages, read the accessibility tree, click, fill forms, check console errors, take screenshots. Use to verify a UI change works, reproduce a UI bug, or check what a screen shows. Not for general web lookups or reading docs (use WebFetch/WebSearch for those).
---

# Browser for this repo's web app

`agent-browser` (on PATH) drives one shared, visible Chrome window per git
repo. A wrapper picks the session (the repo's folder name) and a persistent
profile for it, so logins stick. Pass no `--session`, `--profile` or
`--headed` flags. The person sees the same window you drive.

Load the version-matched usage guide before your first command:

```bash
agent-browser skills get core
```

## Find the app

- How to start the dev server and which URL to open: the repo's AGENTS.md,
  CLAUDE.md or README first, then `package.json` scripts. Prefer what the docs
  say over `localhost:<port>` (some apps need a specific hostname for OAuth).
- Check whether it's already running before starting another
  (`lsof -nP -iTCP:<port> -sTCP:LISTEN`).
- Ask before any setup step that changes committed files (OAuth client ids,
  env files).

## Logins

If a page asks to sign in, stop and ask the person to log in in the open
Chrome window. Never type credentials yourself. The profile keeps the login
for later sessions in this repo.

## The loop

1. `agent-browser open <url>`
2. `agent-browser snapshot -i` for interactive elements with `@eN` refs
3. Act with refs: `click @e3`, `fill @e5 "text"`, `press Enter`
4. Snapshot again after anything that changes the page; refs go stale.
5. `agent-browser console` and `agent-browser errors` when something looks wrong.
6. Screenshot only when the person needs to see it:
   `agent-browser screenshot /tmp/<repo>-<what>.png`

Leave the browser open when done: the person shares the window.
