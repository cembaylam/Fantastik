import SwiftUI
import AppKit

/// The calendar used everywhere in the app; honours the "first weekday" preference.
func appCalendar() -> Calendar {
    var c = Calendar.current
    let fw = UserDefaults.standard.integer(forKey: "firstWeekday")
    if fw >= 1 && fw <= 7 { c.firstWeekday = fw }
    return c
}

extension Date {
    var startOfDay: Date { appCalendar().startOfDay(for: self) }
    func adding(days: Int) -> Date { appCalendar().date(byAdding: .day, value: days, to: self) ?? self }
    func adding(months: Int) -> Date { appCalendar().date(byAdding: .month, value: months, to: self) ?? self }
    func adding(years: Int) -> Date { appCalendar().date(byAdding: .year, value: years, to: self) ?? self }
    func adding(minutes: Double) -> Date { addingTimeInterval(minutes * 60) }
    var startOfWeek: Date { appCalendar().dateInterval(of: .weekOfYear, for: self)?.start ?? startOfDay }
    var startOfMonth: Date { appCalendar().dateInterval(of: .month, for: self)?.start ?? startOfDay }
    var startOfYear: Date { appCalendar().dateInterval(of: .year, for: self)?.start ?? startOfDay }
    var endOfDay: Date { adding(days: 1).startOfDay }
    func isSameDay(_ o: Date) -> Bool { appCalendar().isDate(self, inSameDayAs: o) }
    func isSameMonth(_ o: Date) -> Bool { appCalendar().isDate(self, equalTo: o, toGranularity: .month) }
    var isToday: Bool { appCalendar().isDateInToday(self) }
    var minutesIntoDay: Double { timeIntervalSince(startOfDay) / 60 }
    var dayNumber: Int { appCalendar().component(.day, from: self) }
    var weekdayNumber: Int { appCalendar().component(.weekday, from: self) }
    var weekOfYear: Int { appCalendar().component(.weekOfYear, from: self) }

    func settingTime(hour: Int, minute: Int) -> Date {
        appCalendar().date(bySettingHour: hour, minute: minute, second: 0, of: self) ?? self
    }

    /// Next full hour after the receiver.
    var nextHour: Date {
        let c = appCalendar()
        let base = c.dateInterval(of: .hour, for: self)?.start ?? self
        return base.addingTimeInterval(3600)
    }

    var timeText: String { formatted(date: .omitted, time: .shortened) }

    var relativeDayText: String {
        let c = appCalendar()
        if c.isDateInToday(self) { return "Today" }
        if c.isDateInTomorrow(self) { return "Tomorrow" }
        if c.isDateInYesterday(self) { return "Yesterday" }
        return formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

func timeRangeText(_ start: Date, _ end: Date) -> String {
    (start..<max(end, start)).formatted(.interval.hour().minute())
}

func dayRangeText(_ start: Date, _ end: Date) -> String {
    if start.isSameDay(end) { return start.formatted(.dateTime.weekday(.wide).month(.wide).day().year()) }
    return (start..<end).formatted(.interval.month(.abbreviated).day().year())
}

enum Theme {
    static let accent = Color(red: 0.95, green: 0.27, blue: 0.22)
    static let hairline = Color.primary.opacity(0.09)
    static let subtleFill = Color.primary.opacity(0.05)
}

extension Color {
    /// Event text colour: calendar colour pulled toward the label colour so it stays legible on tinted fills.
    func eventText() -> Color { self.mix(with: .primary, by: 0.38) }
}

extension View {
    @ViewBuilder func `if`<T: View>(_ condition: Bool, transform: (Self) -> T) -> some View {
        if condition { transform(self) } else { self }
    }
}

/// Simple wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, width: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxW, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}
