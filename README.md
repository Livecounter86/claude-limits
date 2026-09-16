# Claude Limits

Repository: https://github.com/Livecounter86/claude-limits

_Ukrainian version: [README-UA.md](README-UA.md)_

A macOS app that shows in the menu bar how much of your Claude usage limits
you have used.

```
menu bar:  ⟨ 41% · 16% ⟩      session · week
```

Click to expand the details: percentages, progress bars, reset time for each
window, and remaining extra credits.

---

## Where the data comes from

The app reads the OAuth token that Claude Code already stores in your login
keychain (the `Claude Code-credentials` entry) and makes two requests on your
behalf:

| Request | What it returns |
|---|---|
| `GET https://api.anthropic.com/api/oauth/usage` | 5-hour and weekly windows, per-model limits, extra credits |
| `GET https://api.anthropic.com/api/oauth/profile` | name, email, plan (optional — if it fails, the numbers still show) |

**No token is ever stored or copied anywhere.** The keychain is read live on
every refresh, so Claude Code remains the sole owner of the token — and the
one that keeps it fresh. Because of this:

- nothing goes stale and nothing needs to be re-entered;
- there's no conflict with refresh-token rotation;
- **switching accounts needs no UI** — run `claude auth login` under a
  different account and the app will start showing it automatically.

---

## Installing on this Mac

```sh
cd ~/claude-limits
make install      # build, put in /Applications, and launch
```

On first launch macOS will ask once for permission to read
`Claude Code-credentials` — click **"Always Allow"**.

Launch at login is a checkbox in the app's own menu.

---

## Installing on a new Mac

You need a Mac on Apple Silicon (`arm64`) with macOS 13+ and Claude Code
already signed in.

### Option 1 — build in place (recommended)

Copy **the whole source directory**:

```
~/claude-limits
```

No need to copy `.build` or `ClaudeLimits.app` — those are build artifacts:

```sh
rsync -av --exclude .build --exclude ClaudeLimits.app \
      ~/claude-limits/ new-mac:~/claude-limits/
```

On the new Mac:

```sh
cd ~/claude-limits
make install
```

Only the Command Line Tools are required (`xcode-select --install`). Full
Xcode is only needed for `make test`.

This path is clean: the app is built locally, so quarantine and Gatekeeper
issues never come up.

### Option 2 — copy the built `.app`

Copy a single bundle directory:

```
~/claude-limits/ClaudeLimits.app
```

It's self-contained (468 KB, system frameworks only) — drop it into
`/Applications`.

⚠️ **But:** the app is ad-hoc signed and not notarized, so Gatekeeper rejects
it. If you transfer it via AirDrop, a browser, or email, macOS will attach a
quarantine attribute and refuse to launch it. Clear it like this:

```sh
xattr -dr com.apple.quarantine /Applications/ClaudeLimits.app
open /Applications/ClaudeLimits.app
```

Transferring via USB, `scp`, or `rsync` usually doesn't trigger quarantine, in
which case this step isn't needed.

---

## Commands

```sh
make app         # build ClaudeLimits.app
make run         # build and run from here, without installing
make install     # install to /Applications and launch
make uninstall   # remove from /Applications
make test        # 45 tests (requires Xcode)
make clean
```

## Same thing in the terminal

```sh
/Applications/ClaudeLimits.app/Contents/MacOS/ClaudeLimits --print
```

```
Alex · team
example@example.com

5-hour session — 41%
▓▓▓▓▓▓░░░░░░░░  → 20:19 · in 4h 5m

Week · all models — 16%
▓▓░░░░░░░░░░░░  → 09/05 20:59 · in 1d 4h

Extra credits — $0.00 / $140.00
```

Handy for a `statusline` or scripts.

## Data refresh

Once every 90 seconds, and again the moment the menu is opened — though a
menu open within 90 seconds of the last fetch is skipped, to stay under the
API's rate limit. "Refresh now" in the menu always fetches immediately. Only
the signed-in account is polled.

## When something's wrong

| Situation | What you'll see |
|---|---|
| Not signed in to Claude Code | `Не залогінено в Claude Code` + `Run in terminal: claude auth login` |
| Token rejected (401/403) | `Токен недійсний` + the same hint |
| No access to keychain | a hint to allow access in System Settings › Privacy |
| No network | the last numbers, dimmed, labeled `Дані від HH:MM` |

Two principles:

- Stale numbers are **always** marked as stale, never passed off as fresh.
- The "what to do" hint shows up **even while** the previous numbers are still
  there — that's exactly what a mid-session sign-out looks like.

Signing out doesn't break the keychain entry: Claude Code leaves it in place
and just empties the token (the same entry also holds MCP server tokens). So
an empty token is treated as "signed out," not as corrupted data — those are
different situations, and they're fixed differently.

---

## Structure

| File | Role |
|---|---|
| `Sources/ClaudeLimitsCore/Models.swift` | API response types, list of windows to show |
| `Sources/ClaudeLimitsCore/Keychain.swift` | reads Claude Code's credentials |
| `Sources/ClaudeLimitsCore/UsageAPI.swift` | the two HTTP requests |
| `Sources/ClaudeLimitsCore/Formatting.swift` | bars, time, money, plan names |
| `Sources/ClaudeLimitsCore/TextReport.swift` | rendering for `--print` |
| `Sources/ClaudeLimitsApp/MenuBarController.swift` | status item and menu |
| `Resources/Info.plist` | `LSUIElement` — no Dock icon |

Everything except the AppKit layer is covered by tests — including parsing
timestamps with six fractional digits, which the stock
`ISO8601DateFormatter` doesn't accept.

## Limitations

- Apple Silicon only. For Intel, rebuild with
  `swift build -c release --arch arm64 --arch x86_64`.
- Ad-hoc signature: the signature changes on every rebuild, so macOS may ask
  for keychain permission again. Only fixed by a real Developer ID.
- The API returns **percentages**, not message or token counts — showing "how
  many requests are left" is technically impossible.
- One account at a time: exactly as many as Claude Code itself holds.
