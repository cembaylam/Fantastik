import SwiftUI

struct MonthView: View {
    @Environment(AppState.self) private var app
    @AppStorage("showWeekNumbers") private var showWeekNumbers = false

    private var weekdaySymbols: [String] {
        let c = appCalendar()
        let s = c.shortStandaloneWeekdaySymbols
        let off = c.firstWeekday - 1
        return Array(s[off...] + s[..<off])
    }

    var body: some View {
        let month = app.selectedDate
        let first = month.startOfMonth
        let start = first.startOfWeek
        let span = appCalendar().dateComponents([.day], from: start, to: first).day ?? 0
        let count = appCalendar().range(of: .day, in: .month, for: first)?.count ?? 30
        let rows = (span + count + 6) / 7
        let days = (0..<rows * 7).map { start.adding(days: $0) }
        let events = app.events(from: start, to: days.last!.endOfDay)

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if showWeekNumbers { Color.clear.frame(width: 28) }
                ForEach(weekdaySymbols, id: \.self) { s in
                    Text(s.uppercased()).font(.system(size: 10.5, weight: .semibold)).tracking(0.5)
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 7)
            Divider()
            GeometryReader { geo in
                let cellH = geo.size.height / CGFloat(rows)
                VStack(spacing: 0) {
                    ForEach(0..<rows, id: \.self) { r in
                        HStack(spacing: 0) {
                            if showWeekNumbers {
                                Text("\(days[r * 7].weekOfYear)").font(.system(size: 10)).foregroundStyle(.tertiary).frame(width: 28)
                            }
                            ForEach(0..<7, id: \.self) { c in
                                let d = days[r * 7 + c]
                                MonthDayCell(day: d, inMonth: d.isSameMonth(month), height: cellH,
                                             events: events.filter { $0.occurs(on: d) })
                            }
                        }
                        .frame(height: cellH)
                    }
                }
            }
        }
        .background(.background)
    }
}

private struct MonthDayCell: View {
    @Environment(AppState.self) private var app
    let day: Date
    let inMonth: Bool
    let height: CGFloat
    let events: [EventItem]
    @State private var hover = false

    var body: some View {
        let today = day.isToday
        let selected = day.isSameDay(app.selectedDate)
        let maxChips = max(0, Int((height - 30) / 19))
        let shown = events.count > maxChips ? max(0, maxChips - 1) : events.count
        let banners = events.filter(\.isBanner) + []
        let ordered = banners + events.filter { !$0.isBanner }
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Spacer()
                Text(day.dayNumber == 1 ? day.formatted(.dateTime.month(.abbreviated).day()) : "\(day.dayNumber)")
                    .font(.system(size: 12, weight: today ? .bold : .medium)).monospacedDigit()
                    .foregroundStyle(today ? AnyShapeStyle(.white) : inMonth ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                    .padding(.horizontal, today ? 6 : 2).padding(.vertical, 1)
                    .background { if today { Capsule().fill(Theme.accent) } }
            }
            ForEach(ordered.prefix(shown)) { e in MonthChip(item: e, dim: !inMonth) }
            if ordered.count > shown {
                Text("\(ordered.count - shown) more…").font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.leading, 4)
                    .onTapGesture { app.jump(to: day, mode: .day) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 3).padding(.top, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(selected ? Theme.accent.opacity(0.07) : hover ? Color.primary.opacity(0.03) : Color.clear)
        .overlay(alignment: .topLeading) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
        .overlay(alignment: .leading) { Rectangle().fill(Theme.hairline).frame(width: 1) }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(count: 2) { app.newEvent(at: day.settingTime(hour: 9, minute: 0), allDay: false) }
        .onTapGesture { app.selectedDate = day }
        .contextMenu {
            Button("New Event…") { app.newEvent(at: day.settingTime(hour: 9, minute: 0)) }
            Button("Show Day") { app.jump(to: day, mode: .day) }
        }
    }
}

private struct MonthChip: View {
    @Environment(AppState.self) private var app
    let item: EventItem
    let dim: Bool

    var body: some View {
        Group {
            if item.isBanner {
                Text(item.title).font(.system(size: 10.5, weight: .semibold)).lineLimit(1)
                    .padding(.horizontal, 5).padding(.vertical, 1.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.white)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(item.color.gradient))
            } else {
                HStack(spacing: 4) {
                    Circle().fill(item.color).frame(width: 6, height: 6)
                    Text(item.title).font(.system(size: 10.5, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(item.start.formatted(.dateTime.hour().minute())).font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.horizontal, 4).padding(.vertical, 1.5)
            }
        }
        .opacity(dim ? 0.5 : 1)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { app.edit(item) }
        .onTapGesture { app.selected = item }
        .eventPopover(item)
        .contextMenu { EventContextMenu(item: item) }
    }
}

struct YearView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let year = app.selectedDate.startOfYear
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 28, alignment: .top), count: 4), spacing: 26) {
                ForEach(0..<12, id: \.self) { m in
                    let month = year.adding(months: m)
                    let current = month.isSameMonth(Date())
                    VStack(alignment: .leading, spacing: 6) {
                        Text(month.formatted(.dateTime.month(.wide)))
                            .font(.system(size: 15, weight: .bold)).foregroundStyle(current ? Theme.accent : .primary)
                            .onTapGesture { app.jump(to: month, mode: .month) }
                        MonthGrid(month: month, cell: 24, fontSize: 11, showsOutside: false, showsDots: true, highlightSelection: false) { d in
                            app.jump(to: d, mode: .day)
                        }
                    }
                }
            }
            .padding(28)
        }
        .background(.background)
    }
}
