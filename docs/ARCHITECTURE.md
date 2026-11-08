# Architecture

Fantastik is a single SwiftPM executable target (`Sources/Fantastik`) packaged into an `.app` by `scripts/build.sh`. It uses Swift 6.4 toolchain in Swift 5 language mode, SwiftUI, Observation (`@Observable`) and EventKit. The minimum deployment target is macOS 26.

```
Sources/Fantastik
├── FantastikApp.swift        App scenes, menu commands, app delegate, global hot key, floating panel
├── Model/
│   ├── Models.swift          Value types: EventItem, ReminderItem, CalendarInfo, RepeatSpec, EventDraft…
│   ├── CalendarStore.swift   EventKit access, fetching, saving, reminders, change observation
│   ├── DemoData.swift        Sample (fictional) data used by demo mode and screenshots
│   ├── AppState.swift        UI state: selection, view mode, calendar sets, templates, openings finder
│   └── InterestingCalendars.swift  Locally computed moon phases and US holidays
├── Parser/EntryParser.swift  Natural-language parser (regex pipeline, no network)
├── Services/WeatherService.swift  Core Location + Open-Meteo forecast
├── Support/                  Date helpers, theme, icon renderer, offscreen snapshot tool
└── Views/                    Timeline (day/week), month, year, list, sidebar, editor, quick entry, settings…
```

## Key ideas

- **Value-type events.** `EventItem` is a plain struct copied from `EKEvent`, which keeps views simple and lets demo mode share the same code path. The store keeps a private map from item id to the live `EKEvent` for saving.
- **One store, one state object.** `CalendarStore` owns data and bumps a `revision` counter whenever EventKit reports a change; `AppState` owns presentation state and filters by visible calendars / the active calendar set. Views read both through the environment.
- **Parser pipeline.** `EntryParser` removes recognised fragments (URL, emails, calendar, alerts, repeat, duration, times, dates, location) from a working string one at a time; whatever remains is the title.
- **Timeline layout.** `TimelineView.swift` places events in columns per overlapping cluster, and implements drag-to-create, move and resize with 15-minute snapping.
- **Demo mode.** `--demo` (or the welcome screen button) swaps EventKit for generated sample data, so the UI can be explored and screenshotted without touching real calendars.
- **Snapshots.** `--snapshot <dir>` renders the main screens offscreen to PNG in demo mode; used for the README images.
- **Icon.** `IconRenderer` draws the app icon (with today's date) at runtime; `scripts/build.sh` uses it via `--render-icon` to create the `.icns`, unless `Resources/AppIcon.icns` exists.

## Scripts

| Script | Purpose |
| --- | --- |
| `scripts/build.sh` | Release build for arm64, assemble and ad-hoc sign `build/Fantastik.app` |
| `scripts/make-dmg.sh` | Build the app and package `build/Fantastik-<version>.dmg` |

## Privacy

The app talks to EventKit locally. The only network requests are the optional weather forecast (Open-Meteo, using approximate coordinates) and optional MapKit travel-time estimates. No analytics, no accounts, no data leaves the Mac otherwise.
