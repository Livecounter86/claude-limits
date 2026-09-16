# AGENTS.md

Context for whoever (human or agent) touches this repo next. README.md is
user-facing (install/usage) — this file is operational/agent-facing: gotchas,
structure pointers, and why non-obvious decisions were made. Keep it short;
don't duplicate README.

## Environment gotchas

- **`git` and `swift build` can both fail with**
  `You have not agreed to the Xcode license agreements.` — fix is
  `sudo xcodebuild -license accept`, run by the *user* in a real Terminal
  (needs a TTY for the password; can't be done from a non-interactive shell).
  If a build or git command fails with that message, that's the cause —
  don't try workarounds, just ask the user to run it.
- Ad-hoc code signing (`codesign --force --sign -`) means the signature
  changes on every rebuild — macOS may re-prompt for keychain access after
  `make install`. Expected, not a bug.
- `make install` kills the running instance, rebuilds release, copies to
  `/Applications`, and relaunches — safe to run any time after a code change.

## Structure (see README for the full table)

- `Sources/ClaudeLimitsCore/UsageAPI.swift` — the two HTTP calls
  (`/api/oauth/usage`, `/api/oauth/profile`), token comes from
  `Keychain.swift` (reads Claude Code's own credentials, never stores one).
- `Sources/ClaudeLimitsApp/MenuBarController.swift` — status item, menu,
  and the refresh scheduling. This is the file most behavior changes touch.
- AppKit layer (`MenuBarController.swift`, `main.swift`) has **no test
  coverage** — everything else does (see README "Structure"). Verify AppKit
  changes with `make install` + manually checking the menu.

## Known history / decisions

- **Refresh throttling (2026-09, commit 3303dc6):** the menu used to refresh
  on a 60s timer *and* on every menu open, with no cooldown between the two.
  Opening the menu right after a timer tick could fire two requests inside a
  minute and trip the API's rate limit (429 on `/oauth/usage`). Fixed by
  bumping the timer to 90s and adding a 90s `minimumRefreshInterval` that
  throttles both the timer and menu-open triggers. The explicit "Refresh now"
  menu action (`refreshNow`) intentionally bypasses the cooldown — it's a
  direct user request.
- **README vs. code drift:** README currently says refresh happens "once
  every 5 minutes" — the code says 90s. Check `MenuBarController.swift`
  (`refreshInterval` / `minimumRefreshInterval`) for the real numbers before
  trusting README's wording on timing, and fix README when you touch this
  area again.
- The API has no RPM/request-count endpoint — only percentages for the
  5-hour and weekly windows, per `UsageResponse`. Don't build a feature that
  assumes raw request counts are available.

## When making changes here

- No CI in this repo — `make test` (needs full Xcode, not just CLT) is the
  only check. Run it for `ClaudeLimitsCore` changes; AppKit changes need a
  manual `make install` + click-through.
- Prefer fixing README drift in the same commit as the code change that
  caused it, rather than letting it accumulate again.
