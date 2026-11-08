import SwiftUI

extension CalendarStore {
    static let demoCalendars: [CalendarInfo] = [
        CalendarInfo(id: "demo-work", title: "Work", color: Color(red: 0.20, green: 0.52, blue: 0.96), sourceTitle: "iCloud", isEditable: true),
        CalendarInfo(id: "demo-personal", title: "Personal", color: Color(red: 0.96, green: 0.33, blue: 0.28), sourceTitle: "iCloud", isEditable: true),
        CalendarInfo(id: "demo-family", title: "Family", color: Color(red: 0.30, green: 0.78, blue: 0.40), sourceTitle: "iCloud", isEditable: true),
        CalendarInfo(id: "demo-health", title: "Health", color: Color(red: 0.62, green: 0.38, blue: 0.90), sourceTitle: "iCloud", isEditable: true),
        CalendarInfo(id: "demo-birthdays", title: "Birthdays", color: Color(red: 0.55, green: 0.56, blue: 0.60), sourceTitle: "Other", isEditable: false),
    ]

    private struct Template {
        let title: String
        let weekdays: [Int]
        let hour: Int, minute: Int, duration: Int
        let cal: Int
        var location = ""
        var url: String? = nil
        var attendees: [Attendee] = []
    }

    private static let templates: [Template] = [
        Template(title: "Team Standup", weekdays: [2, 3, 4, 5, 6], hour: 9, minute: 30, duration: 30, cal: 0,
                 location: "Zoom", url: "https://zoom.us/j/9876543210",
                 attendees: [Attendee(name: "Alex Chen", status: .accepted, isOrganizer: true, isMe: false),
                             Attendee(name: "Priya Patel", status: .accepted, isOrganizer: false, isMe: false),
                             Attendee(name: "Jordan Lee", status: .tentative, isOrganizer: false, isMe: false),
                             Attendee(name: "You", status: .accepted, isOrganizer: false, isMe: true)]),
        Template(title: "Design Review", weekdays: [3, 5], hour: 11, minute: 0, duration: 60, cal: 0, location: "Room 4B"),
        Template(title: "Lunch with Sam", weekdays: [4], hour: 12, minute: 30, duration: 60, cal: 1, location: "Café Lomi"),
        Template(title: "Gym", weekdays: [2, 4, 6], hour: 18, minute: 0, duration: 60, cal: 3, location: "Equinox"),
        Template(title: "1:1 with Alex", weekdays: [5], hour: 15, minute: 0, duration: 30, cal: 0, url: "https://meet.google.com/abc-defg-hij"),
        Template(title: "Roadmap Planning", weekdays: [2], hour: 14, minute: 0, duration: 90, cal: 0, location: "Conference Room A"),
        Template(title: "Farmer's Market", weekdays: [7], hour: 9, minute: 0, duration: 120, cal: 2, location: "Union Square"),
        Template(title: "Dinner with Mom & Dad", weekdays: [7], hour: 19, minute: 0, duration: 120, cal: 2, location: "Trattoria Roma"),
        Template(title: "Yoga", weekdays: [3], hour: 7, minute: 30, duration: 45, cal: 3),
        Template(title: "Focus Time", weekdays: [4], hour: 9, minute: 0, duration: 120, cal: 0),
    ]

    func demoGenerate(from: Date, to: Date) -> [EventItem] {
        var out: [EventItem] = []
        var day = from.startOfDay
        while day < to {
            let wd = day.weekdayNumber
            for t in Self.templates where t.weekdays.contains(wd) {
                let start = day.settingTime(hour: t.hour, minute: t.minute)
                let cal = Self.demoCalendars[t.cal]
                out.append(EventItem(
                    id: "demo-\(t.title)-\(Int(start.timeIntervalSince1970))", eventID: "demo-\(t.title)",
                    title: t.title, location: t.location, notes: "", url: t.url.flatMap(URL.init(string:)),
                    start: start, end: start.addingTimeInterval(Double(t.duration) * 60), isAllDay: false,
                    calendarID: cal.id, calendarTitle: cal.title, color: cal.color,
                    isRecurring: true, repeatSpec: nil, hasComplexRule: false, repeatSummary: "Repeats weekly",
                    attendees: t.attendees, alarmOffsets: [600], timeZoneID: nil, isEditable: true, isBusy: true))
            }
            if day.dayNumber == 14 { out.append(allDay("Mom's Birthday 🎂", day, cal: 4)) }
            if day.dayNumber == 1 { out.append(allDay("Rent Due", day, cal: 1)) }
            day = day.adding(days: 1)
        }
        return out
    }

    private func allDay(_ title: String, _ day: Date, cal: Int) -> EventItem {
        let c = Self.demoCalendars[cal]
        return EventItem(id: "demo-\(title)-\(Int(day.timeIntervalSince1970))", eventID: "demo-\(title)", title: title,
                         location: "", notes: "", url: nil, start: day, end: day.endOfDay.addingTimeInterval(-1), isAllDay: true,
                         calendarID: c.id, calendarTitle: c.title, color: c.color, isRecurring: true, repeatSpec: nil,
                         hasComplexRule: false, repeatSummary: "Repeats yearly", attendees: [], alarmOffsets: [],
                         timeZoneID: nil, isEditable: c.isEditable, isBusy: false)
    }

    static func demoReminders() -> [ReminderItem] {
        let c = demoCalendars[1].color
        let today = Date().startOfDay
        func r(_ t: String, _ due: Date?, time: Bool = false, color: Color? = nil) -> ReminderItem {
            ReminderItem(id: UUID().uuidString, title: t, due: due, hasTime: time, isCompleted: false,
                         listTitle: "Reminders", color: color ?? c, priority: 0, notes: "")
        }
        return [
            r("Buy groceries", today.settingTime(hour: 17, minute: 0), time: true),
            r("Send invoice to Acme", today, color: demoCalendars[0].color),
            r("Call plumber", today.adding(days: -1)),
            r("Book dentist", today.adding(days: 2)),
            r("Renew passport", today.adding(days: 10)),
        ]
    }
}
