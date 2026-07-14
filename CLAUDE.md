# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Loan/due-date info from VÖBB (Verbund der Öffentlichen Bibliotheken Berlins) for one or more library cards, as two apps sharing one core:

- **macOS menu bar app** (`Sources/VOEBBMenu`) — pure AppKit, no SwiftUI, built via Swift Package Manager. Runs as an accessory app (`LSUIElement`, no Dock icon).
- **iOS app** (`iOS/VOEBBApp.xcodeproj` + `iOS/VOEBBApp/`) — SwiftUI, iOS 16+, draft stage.
- **`VOEBBKit`** (`Sources/VOEBBKit`, library target) — the shared core both apps use: scraping client, HTML parser, models, account/keychain storage. All cross-app logic belongs here; its public API surface is deliberate (`public` types/members), so keep additions minimal.

## Build & run

macOS:

```
swift build                 # debug build
swift build -c release      # release build
./build_app.sh              # produce runnable VOEBBMenu.app
open VOEBBMenu.app
```

`build_app.sh` builds the release binary, assembles `VOEBBMenu.app/Contents/{MacOS,Resources}`, and writes `Info.plist` (bundle id `de.voebb.menubar`, `LSUIElement=true`, min macOS 13). Icon comes from repo-relative `AppIcon.icns` (override with `ICON_SRC=…`).

iOS (requires the iOS platform installed in Xcode):

```
xcodebuild -project iOS/VOEBBApp.xcodeproj -scheme VOEBBApp -destination 'generic/platform=iOS' build
```

or open `iOS/VOEBBApp.xcodeproj` in Xcode and run on a device. The project references the root package via a local-package reference (`relativePath = ..`); signing is automatic with team `9H7F5NMT97`, bundle id `de.ncls.voebbar`.

`swift test` currently fails with "no tests found" — `Tests/VOEBBMenuTests` exists (Swift Testing framework, one empty stub) but `Package.swift` declares no test target. If you add real tests, wire up a `testTarget` in `Package.swift` first (against `VOEBBKit`).

No linter/formatter is configured.

## Architecture

### Entry points
- macOS: `main.swift` sets `.accessory` activation policy and hands off to `AppDelegate`, which owns a single `StatusBarController` and wires it to `PreferencesWindowController.shared`.
- iOS: `VOEBBApp.swift` (SwiftUI `@main`) owns an `AppModel` (`ObservableObject`) that mirrors the mac app's refresh/renew flows against `VOEBBKit`; views are `ContentView` (loan list grouped by account) and `AccountsView`/`AddAccountView` (account management).

### VOEBBSession — screen-scraping client (`VOEBBService.swift`)
This is the core and most fragile part of the app. VÖBB's site (`aDISWeb`, an ADIS-based legacy system) is a form-based, session-driven web app with no public API — there is no DOM parser, everything is regex-based HTML scraping (`HTMLParser.swift`).

- `login()` scrapes a session ID out of an HTML form action, POSTs a nav request, then POSTs credentials.
- `navigate()` "changes pages" by re-POSTing the current page's hidden `<input>` fields plus a `selected` field encoding a nav code (e.g. `*SZA` = loans list, `*SGG` = fees).
- Parsing relies on VÖBB's markup (row class `rTable_tr`, literal status substrings like `"nicht verlängerbar"`). It has broken before when VÖBB changed its markup — see commits `54e9f39` and `bff5340`. Any change to `HTMLParser.swift` or the nav-code POSTs should be treated as coupled to VÖBB's current HTML, not a stable contract.
- Loan-row columns are parsed **by position** (`td[0]`=checkbox, `td[1]`=due date, `td[2]`=library, `td[3]`=title, `td[4]`=status), NOT by td class: cells with red hints (Vormerkung, "nicht verlängerbar") use class `zellef` instead of `rTable_td_text`, so class-based filtering silently drops exactly the rows that carry problems.

### Renewal flow
Both VÖBB renewal buttons ("Alle verlängern" and "Markierte Medien verlängern") abort the **entire batch** if any selected loan is blocked (e.g. by a hold/"Vormerkung"). `renewAllLoans()` therefore runs a two-step flow: first probe renewability via "Markierte Medien verlängerbar?" (`$Button$2`, read-only), then submit only the confirmed-renewable checkboxes via "Markierte Medien verlängern" (`$Button$1`). Button-field ↔ action mapping was reverse-engineered from live HTML; buttons are position-numbered (`$Button$0` = Alle verlängern). The result is a `RenewalOutcome` (renewed + blocked incl. per-item reason).

### Storage
- `AccountStorage` (UserDefaults key `voebb_accounts_v1`) — account metadata (name + card number), the refresh interval (`voebb_refresh_interval_hours`, constrained to `AccountStorage.availableRefreshIntervalsHours`), and the "due soon" threshold in days for the per-account "Fällige verlängern" action (`voebb_renewal_due_days`, constrained to `availableRenewalDueDays`).
- `KeychainHelper` — passwords, keyed by card number, Keychain service `de.voebb.menubar`. Passwords never touch UserDefaults.
- The bundle id `de.voebb.menubar` is shared between `KeychainHelper`'s service name and `Info.plist` — if one changes, existing saved passwords become unreachable via Keychain lookup.

### UI controllers
All windows are built by hand with explicit `NSRect` frames (no `.xib`/storyboard, minimal Auto Layout) — adjusting one element's position usually means recomputing the y-coordinates of everything below/above it in the same window.

- `StatusBarController` — the `NSStatusItem` and its dropdown menu (per-account submenus, refresh/renew actions, auto-refresh timer).
- `PreferencesWindowController` (singleton) — account add/remove, plus two symmetric settings rows of custom pill-style `NSButton`s (built by hand via `makePillRow`/`stylePills`, not `NSSegmentedControl`): refresh interval and renewal "due soon" threshold.
- `OverviewWindowController` (singleton) — sortable table of all loans across all accounts.

### Data flow
`StatusBarController.refresh()` reads accounts from `AccountStorage`, creates one `VOEBBSession` per account (fresh `URLSessionConfiguration.ephemeral`, no cookie persistence across sessions), fetches `AccountData` for each, then updates the status bar menu and pushes results into `OverviewWindowController`.
