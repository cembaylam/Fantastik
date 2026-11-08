import SwiftUI
import EventKit

struct CalendarInfo: Identifiable, Hashable {
    let id: String
    var title: String
    var color: Color
    var sourceTitle: String
    var isEditable: Bool
}

struct Attendee: Identifiable, Hashable {
    enum Status { case accepted, declined, tentative, pending }
    let name: String
    let status: Status
    let isOrganizer: Bool
    let isMe: Bool
    var id: String { name + "\(status)" }

    var symbol: String {
        switch status {
        case .accepted: "checkmark.circle.fill"
        case .declined: "xmark.circle.fill"
        case .tentative: "questionmark.circle.fill"
        case .pending: "circle.dotted"
        }
    }
    var tint: Color {
        switch status {
        case .accepted: .green
        case .declined: .red
        case .tentative: .orange
        case .pending: .secondary
        }
    }
}

struct EventItem: Identifiable, Hashable {
    var id: String
    var eventID: String
    var title: String
    var location: String
    var notes: String
    var url: URL?
    var start: Date
    var end: Date
    var isAllDay: Bool
    var calendarID: String
    var calendarTitle: String
    var color: Color
    var isRecurring: Bool
    var repeatSpec: RepeatSpec?
    var hasComplexRule: Bool
    var repeatSummary: String?
    var attendees: [Attendee]
    var alarmOffsets: [TimeInterval]
    var timeZoneID: String?
    var isEditable: Bool
    var isBusy: Bool

    static func == (l: EventItem, r: EventItem) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    var myStatus: Attendee.Status? { attendees.first(where: \.isMe)?.status }

    /// Last instant the event occupies (all-day ends are inclusive, some providers store them exclusive).
    var lastInstant: Date {
        if isAllDay {
            var e = end
            if e > start, e == e.startOfDay { e = e.addingTimeInterval(-1) }
            return max(e, start)
        }
        return max(end, start.addingTimeInterval(60))
    }

    var spansMultipleDays: Bool { !start.isSameDay(lastInstant) }

    func occurs(on day: Date) -> Bool {
        let ds = day.startOfDay
        let de = ds.endOfDay
        return start < de && lastInstant >= ds && (isAllDay ? true : lastInstant > ds)
    }

    var meeting: MeetingLink? { MeetingLink.detect(in: [url?.absoluteString ?? "", location, notes]) }

    var timeSummary: String {
        if isAllDay {
            return spansMultipleDays ? dayRangeText(start, lastInstant) : "All day"
        }
        return spansMultipleDays ? "\(start.formatted(.dateTime.month(.abbreviated).day().hour().minute())) – \(end.formatted(.dateTime.month(.abbreviated).day().hour().minute()))" : timeRangeText(start, end)
    }
}

struct ReminderItem: Identifiable, Hashable {
    var id: String
    var title: String
    var due: Date?
    var hasTime: Bool
    var isCompleted: Bool
    var listTitle: String
    var color: Color
    var priority: Int
    var notes: String

    static func == (l: ReminderItem, r: ReminderItem) -> Bool { l.id == r.id && l.isCompleted == r.isCompleted }
    func hash(into h: inout Hasher) { h.combine(id) }

    var isOverdue: Bool {
        guard let due, !isCompleted else { return false }
        return hasTime ? due < Date() : due.startOfDay < Date().startOfDay
    }
}

// MARK: - Meetings

struct MeetingLink {
    let url: URL
    let service: String

    static let services: [(host: String, name: String)] = [
        ("zoom.us", "Zoom"), ("zoom.com", "Zoom"), ("meet.google.com", "Google Meet"),
        ("teams.microsoft.com", "Microsoft Teams"), ("teams.live.com", "Microsoft Teams"),
        ("webex.com", "Webex"), ("whereby.com", "Whereby"), ("gotomeeting.com", "GoToMeeting"),
        ("facetime.apple.com", "FaceTime"), ("around.co", "Around"), ("app.slack.com/huddle", "Slack Huddle"),
        ("bluejeans.com", "BlueJeans"), ("jit.si", "Jitsi"), ("meet.jit.si", "Jitsi"),
    ]

    static func detect(in texts: [String]) -> MeetingLink? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        for text in texts where !text.isEmpty {
            let ns = text as NSString
            for m in detector.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                guard let url = m.url, let host = url.host?.lowercased() else { continue }
                let full = host + url.path
                if let s = services.first(where: { host == $0.host || host.hasSuffix("." + $0.host) || full.hasPrefix($0.host) }) {
                    return MeetingLink(url: url, service: s.name)
                }
            }
        }
        return nil
    }
}

// MARK: - Repeat

struct RepeatSpec: Equatable, Hashable {
    enum Freq: String, CaseIterable, Hashable {
        case daily, weekly, monthly, yearly
        var ek: EKRecurrenceFrequency {
            switch self { case .daily: .daily; case .weekly: .weekly; case .monthly: .monthly; case .yearly: .yearly }
        }
        var unit: String {
            switch self { case .daily: "day"; case .weekly: "week"; case .monthly: "month"; case .yearly: "year" }
        }
    }

    var freq: Freq
    var interval: Int = 1
    var weekdays: [Int] = []   // 1 = Sunday
    var until: Date? = nil

    init(freq: Freq, interval: Int = 1, weekdays: [Int] = [], until: Date? = nil) {
        self.freq = freq; self.interval = interval; self.weekdays = weekdays; self.until = until
    }

    init?(rule r: EKRecurrenceRule) {
        guard r.daysOfTheMonth == nil, r.monthsOfTheYear == nil, r.weeksOfTheYear == nil,
              r.daysOfTheYear == nil, r.setPositions == nil else { return nil }
        let days = r.daysOfTheWeek ?? []
        guard days.allSatisfy({ $0.weekNumber == 0 }) else { return nil }
        if let end = r.recurrenceEnd, end.occurrenceCount > 0 { return nil }
        switch r.frequency {
        case .daily: freq = .daily
        case .weekly: freq = .weekly
        case .monthly: freq = .monthly
        case .yearly: freq = .yearly
        @unknown default: return nil
        }
        if freq != .weekly && !days.isEmpty { return nil }
        interval = max(1, r.interval)
        weekdays = days.map { $0.dayOfTheWeek.rawValue }.sorted()
        until = r.recurrenceEnd?.endDate
    }

    func ekRule() -> EKRecurrenceRule {
        let days = weekdays.compactMap { EKWeekday(rawValue: $0) }.map { EKRecurrenceDayOfWeek($0) }
        return EKRecurrenceRule(
            recurrenceWith: freq.ek, interval: max(1, interval),
            daysOfTheWeek: days.isEmpty ? nil : days, daysOfTheMonth: nil, monthsOfTheYear: nil,
            weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil,
            end: until.map { EKRecurrenceEnd(end: $0) }
        )
    }

    var summary: String {
        var s: String
        if freq == .weekly, weekdays == [2, 3, 4, 5, 6], interval == 1 {
            s = "Every weekday"
        } else {
            s = interval == 1 ? "Every \(freq.unit)" : "Every \(interval) \(freq.unit)s"
            if !weekdays.isEmpty {
                let sym = appCalendar().shortWeekdaySymbols
                s += " on " + weekdays.map { sym[($0 - 1) % 7] }.joined(separator: ", ")
            }
        }
        if let until { s += " until " + until.formatted(.dateTime.month(.abbreviated).day().year()) }
        return s
    }
}

// MARK: - Draft

struct EventDraft: Equatable {
    var title = ""
    var location = ""
    var notes = ""
    var urlString = ""
    var start: Date
    var end: Date
    var isAllDay = false
    var calendarID: String?
    var alerts: [TimeInterval] = []
    var repeatSpec: RepeatSpec?
    var keepOriginalRule = false
    var timeZoneID: String?
    var isBusy = true

    init(start: Date, end: Date, isAllDay: Bool = false) {
        self.start = start; self.end = end; self.isAllDay = isAllDay
    }

    init(item: EventItem) {
        title = item.title; location = item.location; notes = item.notes
        urlString = item.url?.absoluteString ?? ""
        start = item.start; end = item.isAllDay ? item.lastInstant : item.end
        isAllDay = item.isAllDay
        calendarID = item.calendarID
        alerts = item.alarmOffsets
        repeatSpec = item.repeatSpec
        keepOriginalRule = item.hasComplexRule
        timeZoneID = item.timeZoneID
        isBusy = item.isBusy
    }
}

struct EditorRequest: Identifiable {
    let id = UUID()
    var existing: EventItem?
    var draft: EventDraft
}
