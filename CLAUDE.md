# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Loan/due-date info from VÖBB (Verbund der Öffentlichen Bibliotheken Berlins) for one or more library cards, as two apps sharing one core:

- **macOS menu bar app** (`Sources/VOEBBMenu`) — pure AppKit, no SwiftUI, built via Swift Package Manager. Runs as an accessory app (`LSUIElement`, no Dock icon).
- **iOS + macOS app** (`iOS/VOEBBApp.xcodeproj` + `iOS/VOEBBApp/`) — one SwiftUI target with two destinations (iOS 16+, macOS 13+). Live in the App Store as "VÖPP". On macOS it is a normal windowed app plus a `MenuBarExtra` (`MenuBarView.swift`), sandboxed with the network-client entitlement (`VOEBBApp.entitlements`, applied via `CODE_SIGN_ENTITLEMENTS[sdk=macosx*]`). Platform differences are isolated in `PlatformShims.swift` (no-op modifiers on the other platform, `leadingAction`/`trailingAction` toolbar placements, `SheetHeader` for macOS sheets, which do not render toolbars) and a few `#if os(...)` blocks: the barcode scanner is iOS-only; macOS sheets carry their own Schließen/Abbrechen/Sichern buttons; the accounts sheet is a grouped `Form` on macOS because macOS `List` rows do not grow for multi-line footers. The macOS app icon set is derived from the root `AppIcon.icns` (`iconutil --convert iconset`).
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

macOS (same project, same bundle id, universal purchase):

```
xcodebuild -project iOS/VOEBBApp.xcodeproj -scheme VOEBBApp -destination 'platform=macOS' build
```

or open `iOS/VOEBBApp.xcodeproj` in Xcode and run on a device or "My Mac". The project references the root package via a local-package reference (`relativePath = ..`); signing is automatic with team `9H7F5NMT97`, bundle id `de.ncls.voebbar`.

`swift test` runs the `VOEBBKitTests` target (XCTest, `@testable import VOEBBKit`). Parser tests use anonymized real pages in `Tests/VOEBBKitTests/Fixtures/` (overview + loans list); regenerate them from a fresh HAR with `Tests/VOEBBKitTests/anonymize_fixtures.py` — never commit a raw HAR. The fixtures are frozen: they catch our regressions, not VÖBB markup changes.

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
- aDIS `identity` tokens are **single-use**: every response carries a fresh token, and the next POST must be built from the hidden inputs of the page most recently loaded (reusing an older page's inputs lands on a session-error page). Page transitions are restricted: a list navigation posted **from another list page** is silently ignored (after `*SZA`, a `*SZS` returns the loans page again, and vice versa), and the probe result page ignores `*SGG`. The browser's way around this is the "Zur Übersicht" submit button, which returns a genuine overview from any list page; from there the next list navigation works. `fetchAccountData` therefore runs everything in **one session** (live-verified): overview → `*SZA` → renewability probe (`$Button$2`) → `returnToOverview` → `*SZS` → `*SE`. The "Zur Übersicht" button is looked up by its `value` label (`HTMLParser.findSubmitButton`) because its `$Button$N` number differs per page (loans: 3/7, pickups: 1/3), and the response is checked with `HTMLParser.isOverviewPage` before continuing. If the probe or the back-navigation fails, the old fresh-session paths (`fetchRenewabilityRows`, `fetchPickups`) run as fallbacks — checkbox values are positional and stable across sessions. Every session ends with a best-effort `*SE` logout.
- Pickups ("Bereitstellungen", nav code `*SZS`) are fetched only when the overview's service list announces them. The pickups list reuses the loans `<title>`; `HTMLParser.isPickupsPage` keys on the `Mein Konto - Bereitstellungen` heading, and rows are 4 cells (`chk`, `Bis`, `Ausgabeort`, `Titel`).
- Fees, pickup code ("Abholcode"), and card validity are all parsed from the **overview page's** `<dt>/<dd>` list via `HTMLParser.parseAccountInfo` — no `*SGG` navigation at all. `applyFees` treats a missing fees row as 0 only when the overview is recognizable by its other `<dt>` terms; otherwise it sets `feesUnknown` instead of reporting 0 (the iOS app then keeps the last known amount).

### Renewal flow
Both VÖBB renewal buttons ("Alle verlängern" and "Markierte Medien verlängern") abort the **entire batch** if any selected loan is blocked (e.g. by a hold/"Vormerkung"). `renewAllLoans()` therefore runs a two-step flow: first probe renewability via "Markierte Medien verlängerbar?" (`$Button$2`, read-only), then submit only the confirmed-renewable checkboxes via "Markierte Medien verlängern" (`$Button$1`). Button-field ↔ action mapping was reverse-engineered from live HTML; buttons are position-numbered (`$Button$0` = Alle verlängern). Success is **never** inferred from the probe: `RenewalVerifier` compares each submitted item's due date before/after on the result page (matched by title + library, duplicate copies counted per group) — only a later date counts as `renewed`, unchanged dates go to `unconfirmed`, an unreadable result page sets `unverifiable`. There are no explicit success markers in aDIS's response to rely on.
- `requestCount` is a hidden field on every aDIS page and must be echoed back as-is (the sequence depends on session history); never hardcode it. HTTP 4xx/5xx throws `networkError` so an error page can't parse as an empty list.

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
