# Natural-language entry

Type a sentence into the entry field (sidebar, menu bar window or the ⌃⌥Space panel). A live preview shows the title, date, time, location, repeat, alerts and the calendar it will land in. Press **↩** to add, **⌘↩** to open the full editor first.

## Examples

| You type | Result |
| --- | --- |
| `Lunch with Sam tomorrow at noon at Café Lomi` | "Lunch with Sam", tomorrow 12:00–13:00, location Café Lomi |
| `Dentist friday 3-4pm` | "Dentist", next Friday 15:00–16:00 |
| `Planning Dec 5 at 2pm for 90 minutes /Work` | 14:00–15:30 on 5 Dec in the Work calendar |
| `Standup every weekday at 9:30am` | repeats Mon–Fri |
| `Gym every Monday and Wednesday at 6pm` | repeats on Mon and Wed |
| `Mom's birthday on 14 Nov` | all-day event |
| `Tea in 2 hours` | starts two hours from now |
| `Review deck 12/25 10am alert 30 minutes before` | alert 30 minutes before |
| `Remind me to call the bank tomorrow at 4pm` | creates a **reminder** instead of an event |

## Supported parts

- **Dates**: today, tomorrow, tonight, weekday names (`friday`, `next tuesday`, `this sunday`), `Dec 5`, `5 December 2026`, `12/25`, `2026-12-25`, `in 3 days/weeks/months`, `next week`, `next month`, `on the 15th`.
- **Times**: `3pm`, `3:30pm`, `at 15:30`, `noon`, `midnight`, ranges like `3-4pm` or `9:30 to 10:30`, relative `in 45 minutes`.
- **Duration**: `for 1h`, `for 90 minutes`, `for an hour`, `for half an hour`, `for 3 days`. The default duration is set in Settings.
- **Location**: `at <place>` at the end of the sentence.
- **Calendar**: `/Work` or `/"Team Calendar"` (matched by name prefix).
- **Repeat**: `daily`, `weekly`, `monthly`, `yearly`, `every other week`, `every 3 days`, `every weekday`, `every monday and thursday`.
- **Alerts**: `alert 15 minutes before`, `10 min before`, `1 hour before`, `2 days before`.
- **Invitees / links**: email addresses and URLs are recognised and removed from the title.
- **Reminders**: start with `remind me to …`, `reminder`, `todo` or `task`.

A date with no time creates an all-day event; a time with no date uses the day currently selected (or tomorrow if that time has already passed today).

The parser lives in `Sources/Fantastik/Parser/EntryParser.swift` and is covered by `Tests/FantastikTests/ParserTests.swift`.
