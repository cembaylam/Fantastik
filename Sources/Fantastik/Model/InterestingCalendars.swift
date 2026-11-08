import SwiftUI

/// Locally computed "interesting calendars" (moon phases, holidays) — no network needed.
enum InterestingCalendars {
    static let moonInfo = CalendarInfo(id: "interesting-moon", title: "Moon Phases", color: Color(red: 0.45, green: 0.50, blue: 0.62),
                                       sourceTitle: "Interesting Calendars", isEditable: false)
    static let holidayInfo = CalendarInfo(id: "interesting-holidays", title: "US Holidays", color: Color(red: 0.86, green: 0.30, blue: 0.36),
                                          sourceTitle: "Interesting Calendars", isEditable: false)

    private static func item(_ title: String, _ date: Date, _ info: CalendarInfo, allDay: Bool = true) -> EventItem {
        EventItem(id: "\(info.id)-\(title)-\(Int(date.timeIntervalSince1970))", eventID: info.id + title, title: title, location: "", notes: "",
                  url: nil, start: date, end: allDay ? date.endOfDay.addingTimeInterval(-1) : date, isAllDay: allDay,
                  calendarID: info.id, calendarTitle: info.title, color: info.color, isRecurring: false, repeatSpec: nil,
                  hasComplexRule: false, repeatSummary: nil, attendees: [], alarmOffsets: [], timeZoneID: nil,
                  isEditable: false, isBusy: false)
    }

    // MARK: Moon

    static func moon(from: Date, to: Date) -> [EventItem] {
        let synodic = 29.530588853 * 86400
        let newMoon = Date(timeIntervalSince1970: 947_182_440) // 2000-01-06 18:14 UTC
        let names = [("🌑 New Moon", 0.0), ("🌓 First Quarter", 0.25), ("🌕 Full Moon", 0.5), ("🌗 Last Quarter", 0.75)]
        var out: [EventItem] = []
        let k0 = Int(floor(from.addingTimeInterval(-86400).timeIntervalSince(newMoon) / synodic))
        let k1 = Int(ceil(to.timeIntervalSince(newMoon) / synodic))
        guard k0 <= k1 else { return [] }
        for k in k0...k1 {
            for (name, frac) in names {
                let d = newMoon.addingTimeInterval((Double(k) + frac) * synodic)
                if d >= from.addingTimeInterval(-86400), d < to { out.append(item(name, d.startOfDay, moonInfo)) }
            }
        }
        return out.filter { $0.start < to && $0.lastInstant >= from }
    }

    // MARK: Holidays

    private static func nthWeekday(_ n: Int, _ weekday: Int, month: Int, year: Int) -> Date? {
        let c = appCalendar()
        guard let first = c.date(from: DateComponents(year: year, month: month, day: 1)) else { return nil }
        var d = first
        while d.weekdayNumber != weekday { d = d.adding(days: 1) }
        return d.adding(days: 7 * (n - 1))
    }
    private static func lastWeekday(_ weekday: Int, month: Int, year: Int) -> Date? {
        let c = appCalendar()
        guard let first = c.date(from: DateComponents(year: year, month: month + 1, day: 1)) else { return nil }
        var d = first.adding(days: -1)
        while d.weekdayNumber != weekday { d = d.adding(days: -1) }
        return d
    }

    static func holidays(from: Date, to: Date) -> [EventItem] {
        let c = appCalendar()
        let y0 = c.component(.year, from: from), y1 = c.component(.year, from: to)
        var out: [EventItem] = []
        for y in y0...max(y0, y1) {
            func fixed(_ n: String, _ m: Int, _ d: Int) -> (String, Date?) { (n, c.date(from: DateComponents(year: y, month: m, day: d))) }
            let list: [(String, Date?)] = [
                fixed("New Year's Day", 1, 1), ("Martin Luther King Jr. Day", nthWeekday(3, 2, month: 1, year: y)),
                fixed("Valentine's Day", 2, 14), ("Presidents' Day", nthWeekday(3, 2, month: 2, year: y)),
                fixed("St. Patrick's Day", 3, 17), ("Mother's Day", nthWeekday(2, 1, month: 5, year: y)),
                ("Memorial Day", lastWeekday(2, month: 5, year: y)), fixed("Juneteenth", 6, 19),
                ("Father's Day", nthWeekday(3, 1, month: 6, year: y)), fixed("Independence Day", 7, 4),
                ("Labor Day", nthWeekday(1, 2, month: 9, year: y)), fixed("Halloween", 10, 31),
                ("Thanksgiving", nthWeekday(4, 5, month: 11, year: y)), fixed("Christmas Eve", 12, 24),
                fixed("Christmas Day", 12, 25), fixed("New Year's Eve", 12, 31),
            ]
            for (n, d) in list { if let d, d >= from.startOfDay, d < to { out.append(item(n, d, holidayInfo)) } }
        }
        return out
    }
}
