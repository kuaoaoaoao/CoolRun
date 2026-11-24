# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

CoolRun is a macOS menu bar utility that consolidates multiple everyday productivity tools into a single lightweight popover panel. It runs as a menu bar-only app (no Dock icon by default).

**Current modules (9):**
- **Today** — Prioritized overview aggregating urgency from all modules
- **System Monitor** — CPU, memory, storage, battery, network, temperature, uptime, process ranking
- **Gold Price** — Real-time Chinese gold price (CZB accumulation gold), technical indicators, trading signals, portfolio P&L
- **Calendar** — Calendar with lunar calendar, Chinese holidays, birthdays, countdowns
- **English Learning** — Graded vocabulary with TTS, progress tracking
- **AI Assistant** — LLM-powered conversational assistant for system/gold/AI queries (NEW)
- **Notes** — Local grouped notes with search and pinning
- **Clipboard** — Local clipboard history with search and quick-paste
- **Diagnostics** — Sleep/power analysis, network diagnostics, storage inspection

## Build & Run

Open `CoolRun.xcodeproj` in Xcode, select the `CoolRun` scheme with target `My Mac`, and click Run. The project includes a `CoolRunTests` unit-test target.

To build from command line:
```bash
xcodebuild -project CoolRun.xcodeproj -scheme CoolRun -configuration Debug build
```

To run unit tests:
```bash
xcodebuild -project CoolRun.xcodeproj -scheme CoolRun -destination 'platform=macOS' test
```

## Architecture

The app uses SwiftUI with an `NSApplicationDelegateAdaptor` pattern to bridge AppKit's `NSStatusItem` menu bar integration with SwiftUI views.

**Data flow:**
- `SystemSampler` (Darwin/IOKit) → `SystemMonitorViewModel` (@Observable) → SwiftUI views
- `GoldPriceService` (async HTTP) → `GoldPriceStore` → `GoldAnalysisViewModel` → SwiftUI views
- `LLMService` (LLMProvider protocol) → `AIAssistantView` → SwiftUI views

**Key components:**

- `App/CoolRunApp.swift` — Entry point. Registers `MacAppDelegate` on macOS.
- `App/MacAppDelegate.swift` — Core orchestrator. Manages `NSStatusItem`, popover panels (size per module), coin icon animation, gold price polling.
- `App/ContentView.swift` — Module navigation rail + content area. Defines `ViewMode` enum (9 modules) and each module's panel size.
- `Core/AppTheme.swift` — Shared theme colors + `appCardSurface()` modifier.
- `Modules/Monitor/` — `MonitorPanel` / `MonitorSections` / `ProcessAndDeviceSections` / `MonitorComponents`.
- `Modules/Monitor/SystemSampler.swift` — Raw system data collection using Mach kernel APIs.
- `Modules/Monitor/SystemMonitorViewModel.swift` — @Observable + @MainActor wrapper.
- `Modules/Gold/` — `GoldAnalysisView` / `GoldAnalysisViewModel` / `GoldAnalysisCards` plus engines and stores.
- `Modules/Assistant/LLMService.swift` — LLM provider protocol + OpenAI/Anthropic/Ollama implementations.
- `Modules/Assistant/LLMKeychain.swift` — `LLMProviderKind` enum + Keychain read/write for API keys.
- `Modules/Assistant/LLMProviderSettingsView.swift` — Reusable provider config form + `LLMConfigSheet`.
- `Modules/Assistant/AIAssistantView.swift` — Chat UI for AI assistant module.
- `Settings/SettingsView.swift` — Settings window shell (sidebar + header + category switch).
- `App/AppSettings.swift` — Comprehensive settings with UserDefaults persistence.

## Key Technical Details

- Deployment target: macOS 15.0. Swift Language Version: 5.0 (uses Swift 5.9+ `@Observable` macro).
- App Sandbox enabled with `com.apple.security.network.client` entitlement.
- No external package dependencies (PostHog is optional, env-configured).
- All user data stored locally (UserDefaults, Application Support JSON files). iCloud KVS sync is optional.
- Privacy-first: PostHog analytics has multiple layers of sanitization, default off.
- 4 languages supported: Chinese, English, Japanese, Korean.

## File Organization

Sources live under `CoolRun/` in a directory tree. The target uses a
`PBXFileSystemSynchronizedRootGroup`, so **adding or moving files needs no
`project.pbxproj` edit** — Xcode picks up subdirectories automatically.

```
CoolRun/
├── App/                 entry point, lifecycle, navigation, global state
├── Core/                shared infrastructure (theme, analytics, sync, reminders)
├── Settings/            settings window + one file per page
├── Modules/
│   ├── Today/           Today overview
│   ├── Monitor/         system sampling + monitor panel
│   ├── Gold/            gold price, analysis, forecasting, trade ledger
│   ├── Calendar/        calendar, birthdays, countdowns
│   ├── English/         learning, textbooks, vocabulary
│   ├── Assistant/       LLM chat + provider configuration
│   ├── Notes/           notes store + view
│   ├── Clipboard/       clipboard history + quick paste
│   ├── Diagnostics/     diagnostics reports and probes
│   └── Shelf/           menu bar shelf
└── *.json, Info.plist, Assets.xcassets, CoolRun.entitlements   ← stay at root
```

Resources deliberately stay at the folder root: `EnglishVocabulary*.json` is
loaded with `Bundle.main.url(forResource:withExtension:)` (no subdirectory),
so moving them would change their bundle paths.

**Splitting convention:** one file per concern, named `<Feature><Concern>.swift`.
When a type becomes cross-file, drop `private` and rely on module-internal
visibility — that is why `SettingsView`'s stored properties and the monitor
section views are `internal`.

**Where the big files went:**

- `GoldAnalysisView.swift` (3,432 lines) → `GoldAnalysisView` / `GoldAnalysisViewModel` / `GoldAnalysisCards`
- `SettingsView.swift` (2,109 lines) → shell + `SettingsCategory` + 7 page files + `SettingsComponents`
- `ContentView.swift` (1,907 lines) → shell + `AppTheme` + `MonitorPanel` / `MonitorSections` / `ProcessAndDeviceSections` / `MonitorComponents`

## Self-check

```bash
./scripts/verify.sh          # 编译 + 静态检查
./scripts/verify.sh --test   # 额外跑单元测试
```

When Xcode is present the script does a real `xcodebuild build` and reports the
error/warning counts, then runs the two static checks. When only
CommandLineTools is installed it degrades to `swiftc -parse` — that mode cannot
type-check SwiftUI macros, so treat it as a syntax gate only.

`xcode-select` may still point at CommandLineTools even when Xcode is
installed. The script handles this by exporting
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; do the same
manually if you call `xcodebuild` yourself.

The two static checks (duplicate / `private`-leak detection, and a heuristic
scan for `switch` statements missing an enum case) are redundant with the
compiler when a real build runs, but their messages are more focused. The
`switch` check exists because adding a `ViewMode` case and forgetting one of the
two render switches is a real mistake that has happened.

## Concurrency

The target builds with `-default-isolation MainActor` and `-swift-version 5`.
Under that flag **every** declaration is main-actor isolated unless marked
otherwise, which produces "main actor-isolated ... can not be referenced from a
nonisolated context" warnings (errors in Swift 6) for pure helpers.

Rules when you touch such a site:

- Pure constants and pure helper functions → mark `nonisolated`
  (`nonisolated static let`, `nonisolated static func`).
- Default argument values are evaluated in a nonisolated context. Do not put
  MainActor-isolated initializers there; take an optional parameter and resolve
  it inside the `init` instead.
- A MainActor-isolated sync function called from a nonisolated closure becomes
  an implicit `async` call, which surfaces as "expression is 'async' but is not
  marked with 'await'" on the *caller's* line. Prefer `nonisolated` over adding
  `await`.

The project currently builds with **zero warnings**; keep it that way.

## Conventions

- UI strings use 4-language localization via `LocalizedString` helper.
  Full rules (how to get `lang` in a view, what must *not* be localized,
  the `// i18n-allow` marker, glossary) are in `docs/i18n-conventions.md`.
  Run `./scripts/verify_i18n.sh` after touching user-facing copy — it fails on
  any Chinese literal that is not inside an `en:`/`zh:` call.
- `@Observable` macro for new view models; `ObservableObject` for legacy stores.
- `Sendable` conformance for value types crossing actor boundaries.
- `@MainActor` for view models updating UI state.
- Tests must not hardcode absolute dates that the code compares against `Date()`.
  Build fixtures relative to `Date()` — a fixed `pubDate` silently expires once
  the freshness window passes.

### Adding a module to the navigation rail

`AppSettings` persists the visible module set under `visible_tabs`. Because that
key already exists on every upgraded install, **changing `ViewMode.defaultVisible`
alone does nothing for existing users** — the new module stays invisible.

When adding a case to `ViewMode`:

1. Add it to `ViewMode.defaultVisible`.
2. Bump `ViewMode.visibleTabsSchemaVersion`.
3. Register it in `ViewMode.modulesAdded(after:)` for the new version.

`AppSettings.init` unions the newly added modules into the stored set once, then
writes back `visible_tabs` and `visible_tabs_schema`. Forgetting steps 2–3 is the
exact bug that hid the AI module.

Note the app is **not** sandboxed: real preferences live in
`~/Library/Preferences/kuao.CoolRun.plist`. A `~/Library/Containers/kuao.CoolRun`
directory exists but its plist is stale — do not read settings from there.
