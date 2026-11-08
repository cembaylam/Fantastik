import SwiftUI

/// A month grid used in the sidebar, menu bar window and year view.
struct MonthGrid: View {
    @Environment(AppState.self) private var app
    let month: Date
    var cell: CGFloat = 30
    var fontSize: CGFloat = 12
    var showsOutside = true
    var showsDots = true
    var showsWeekNumbers = false
    var highlightSelection = true
    var onSelect: (Date) -> Void

    private var gridDays: [Date] {
        let first = month.startOfMonth
        let start = first.startOfWeek
        let span = appCalendar().dateComponents([.day], from: start, to: first).day ?? 0
        let count = appCalendar().range(of: .day, in: .month, for: first)?.count ?? 30
        let rows = showsOutside ? 6 : (span + count + 6) / 7
        return (0..<rows * 7).map { start.adding(days: $0) }
    }

    private var weekdaySymbols: [String] {
        let c = appCalendar()
        let s = c.veryShortStandaloneWeekdaySymbols
        let off = c.firstWeekday - 1
        return Array(s[off...] + s[..<off])
    }

    var body: some View {
        let days = gridDays
        let dots = showsDots ? dotColors(days) : [:]
        let cols = Array(repeating: GridItem(.flexible(minimum: cell * 0.7), spacing: 0), count: 7)
        VStack(spacing: 2) {
            LazyVGrid(columns: cols, spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, s in
                    Text(s).font(.system(size: fontSize - 2, weight: .semibold)).foregroundStyle(.tertiary)
                        .frame(height: 16)
                }
            }
            LazyVGrid(columns: cols, spacing: 1) {
                ForEach(days, id: \.self) { d in
                    let inMonth = d.isSameMonth(month)
                    if inMonth || showsOutside {
                        DayCellMini(day: d, inMonth: inMonth, size: cell, fontSize: fontSize,
                                    colors: dots[d.startOfDay] ?? [], selected: highlightSelection && d.isSameDay(app.selectedDate))
                            .onTapGesture { onSelect(d) }
                    } else {
                        Color.clear.frame(height: cell)
                    }
                }
            }
        }
    }

    private func dotColors(_ days: [Date]) -> [Date: [Color]] {
        guard let first = days.first, let last = days.last else { return [:] }
        let events = app.events(from: first, to: last.endOfDay)
        var out: [Date: [Color]] = [:]
        for e in events {
            var d = max(e.start.startOfDay, first)
            var n = 0
            while d <= e.lastInstant && d < last.endOfDay && n < 31 {
                if e.occurs(on: d), out[d, default: []].count < 3, !out[d, default: []].contains(e.color) { out[d, default: []].append(e.color) }
                d = d.adding(days: 1); n += 1
            }
        }
        return out
    }
}

private struct DayCellMini: View {
    let day: Date, inMonth: Bool, size: CGFloat, fontSize: CGFloat, colors: [Color], selected: Bool
    @State private var hover = false

    var body: some View {
        let today = day.isToday
        VStack(spacing: 1) {
            Text("\(day.dayNumber)")
                .font(.system(size: fontSize, weight: today || selected ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(today ? AnyShapeStyle(.white) : inMonth ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                .frame(width: size * 0.78, height: size * 0.78)
                .background {
                    if today { Circle().fill(Theme.accent) }
                    else if selected { Circle().fill(Color.primary.opacity(0.14)) }
                    else if hover { Circle().fill(Color.primary.opacity(0.07)) }
                }
            HStack(spacing: 2) {
                ForEach(Array(colors.prefix(3).enumerated()), id: \.offset) { _, c in Circle().fill(c).frame(width: 3.5, height: 3.5) }
            }
            .frame(height: 4)
            .opacity(inMonth ? 1 : 0.4)
        }
        .frame(height: size + 4)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}

/// Mini month with a title and prev/next controls; follows the app's selected date.
struct MiniMonthView: View {
    @Environment(AppState.self) private var app
    @State private var shown = Date()
    var cell: CGFloat = 32
    var onSelect: ((Date) -> Void)? = nil

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 2) {
                HStack(spacing: 5) {
                    Text(shown.formatted(.dateTime.month(.wide))).font(.system(size: 17, weight: .bold))
                    Text(shown.formatted(.dateTime.year())).font(.system(size: 17, weight: .regular)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { shown = shown.adding(months: -1) } label: { Image(systemName: "chevron.left") }
                Button { shown = Date(); app.goToday() } label: { Image(systemName: "circle.fill").font(.system(size: 6)) }
                    .help("Go to today")
                Button { shown = shown.adding(months: 1) } label: { Image(systemName: "chevron.right") }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.system(size: 12, weight: .semibold))

            MonthGrid(month: shown, cell: cell, showsWeekNumbers: false) { d in
                app.selectedDate = d
                onSelect?(d)
            }
        }
        .onAppear { shown = app.selectedDate }
        .onChange(of: app.selectedDate) { _, new in if !new.isSameMonth(shown) { shown = new } }
    }
}
