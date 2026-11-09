import SwiftUI

extension EventItem {
    /// Shown in the all-day banner row rather than on the hour grid.
    var isBanner: Bool { isAllDay || lastInstant.timeIntervalSince(start) >= 86400 }
}

private struct Placed: Identifiable {
    let item: EventItem
    var col = 0
    var cols = 1
    let startMin: Double
    let endMin: Double
    var id: String { item.id }
}

private func layoutDay(_ items: [EventItem], day: Date) -> [Placed] {
    let ds = day.startOfDay, de = ds.endOfDay
    var placed: [Placed] = items.map {
        let s = max($0.start, ds).timeIntervalSince(ds) / 60
        let e = min($0.lastInstant, de).timeIntervalSince(ds) / 60
        return Placed(item: $0, startMin: s, endMin: max(e, s + 22))
    }
    placed.sort { $0.startMin != $1.startMin ? $0.startMin < $1.startMin : $0.endMin > $1.endMin }

    var result: [Placed] = []
    var cluster: [Placed] = []
    var colEnds: [Double] = []
    var clusterEnd = -1.0
    func flush() {
        let n = colEnds.count
        result += cluster.map { var p = $0; p.cols = n; return p }
        cluster = []; colEnds = []; clusterEnd = -1
    }
    for var p in placed {
        if p.startMin >= clusterEnd, !cluster.isEmpty { flush() }
        if let i = colEnds.firstIndex(where: { $0 <= p.startMin }) { p.col = i; colEnds[i] = p.endMin }
        else { p.col = colEnds.count; colEnds.append(p.endMin) }
        clusterEnd = max(clusterEnd, p.endMin)
        cluster.append(p)
    }
    flush()
    return result
}

struct TimelineCalendarView: View {
    @Environment(AppState.self) private var app
    let days: [Date]
    @AppStorage("hourHeight") private var hourHeight: Double = 56
    @State private var zoomBase: Double?
    private let gutter: CGFloat = 60

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            allDayRow
            Divider()
            grid
        }
        .background(.background)
    }

    // MARK: Header

    private var headerRow: some View {
        HStack(spacing: 0) {
            VStack {
                if appCalendarShowsWeekNumbers {
                    Text("W\(days.first?.weekOfYear ?? 0)").font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
                }
            }
            .frame(width: gutter)
            ForEach(days, id: \.self) { d in
                let today = d.isToday
                Button { app.jump(to: d, mode: days.count > 1 ? .day : nil) } label: {
                    VStack(spacing: 2) {
                        Text(d.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                            .font(.system(size: 10.5, weight: .semibold)).tracking(0.5)
                            .foregroundStyle(today ? Theme.accent : .secondary)
                        Text("\(d.dayNumber)")
                            .font(.system(size: 20, weight: today ? .semibold : .regular)).monospacedDigit()
                            .foregroundStyle(today ? .white : .primary)
                            .frame(width: 34, height: 34)
                            .background { if today { Circle().fill(Theme.accent) } }
                        WeatherBadge(day: d).frame(height: 14)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }

    private var appCalendarShowsWeekNumbers: Bool { UserDefaults.standard.bool(forKey: "showWeekNumbers") }

    // MARK: All-day

    private var allDayRow: some View {
        let perDay = days.map { d -> (events: [EventItem], reminders: [ReminderItem]) in
            (app.events(on: d).filter(\.isBanner), app.reminders(on: d).filter { !$0.hasTime || $0.isOverdue })
        }
        let rows = perDay.map { $0.events.count + $0.reminders.count }.max() ?? 0
        return Group {
            if rows > 0 {
                HStack(alignment: .top, spacing: 0) {
                    Text("all-day").font(.system(size: 10)).foregroundStyle(.tertiary)
                        .frame(width: gutter, alignment: .trailing).padding(.trailing, 8).padding(.top, 3)
                    ForEach(Array(days.enumerated()), id: \.offset) { i, _ in
                        VStack(spacing: 2) {
                            ForEach(perDay[i].events) { BannerChip(item: $0) }
                            ForEach(perDay[i].reminders) { ReminderChip(reminder: $0) }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 2)
                    }
                }
                .padding(.bottom, 5)
            }
        }
    }

    // MARK: Grid

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        ForEach(0..<24, id: \.self) { h in
                            HourRow(hour: h, gutter: gutter).frame(height: hourHeight, alignment: .top).id(h)
                        }
                    }
                    HStack(spacing: 0) {
                        Color.clear.frame(width: gutter)
                        ForEach(days, id: \.self) { d in
                            DayColumn(day: d, hourHeight: hourHeight, multiDay: days.count > 1)
                                .frame(maxWidth: .infinity)
                                .overlay(alignment: .leading) { Rectangle().fill(Theme.hairline).frame(width: 1) }
                        }
                    }
                    if days.contains(where: \.isToday) {
                        Text(app.now.timeText)
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1.5)
                            .background(Capsule().fill(Theme.accent))
                            .frame(width: gutter, alignment: .trailing).padding(.trailing, 4)
                            .offset(y: app.now.minutesIntoDay / 60 * hourHeight - 8)
                            .allowsHitTesting(false)
                    }
                }
                .frame(height: hourHeight * 24)
            }
            .gesture(MagnifyGesture()
                .onChanged { v in
                    if zoomBase == nil { zoomBase = hourHeight }
                    hourHeight = min(140, max(32, (zoomBase ?? 56) * v.magnification))
                }
                .onEnded { _ in zoomBase = nil })
            .onAppear {
                let target = days.contains(where: \.isToday) ? max(0, Calendar.current.component(.hour, from: app.now) - 2) : 7
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { proxy.scrollTo(target, anchor: .top) }
            }
        }
    }
}

private struct HourRow: View {
    let hour: Int
    let gutter: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            if hour > 0 {
                Text(Date().settingTime(hour: hour, minute: 0).formatted(.dateTime.hour()))
                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
                    .frame(width: gutter - 8, alignment: .trailing)
                    .offset(y: -7)
                Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, gutter - 2)
            }
        }
    }
}

// MARK: - Day column

private struct DayColumn: View {
    @Environment(AppState.self) private var app
    let day: Date
    let hourHeight: Double
    let multiDay: Bool
    @State private var createRange: (Double, Double)?

    private func snap(_ y: CGFloat) -> Double {
        let minutes = Double(y) / hourHeight * 60
        return min(1440, max(0, (minutes / 15).rounded() * 15))
    }

    var body: some View {
        let items = app.events(on: day).filter { !$0.isBanner }
        let placed = layoutDay(items, day: day)
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                if day.isToday { Rectangle().fill(Theme.accent.opacity(0.035)) }
                Color.clear.contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 5)
                        .onChanged { v in
                            let a = snap(v.startLocation.y), b = snap(v.location.y)
                            createRange = (min(a, b), max(max(a, b), min(a, b) + 15))
                        }
                        .onEnded { _ in
                            if let r = createRange {
                                let s = day.startOfDay.adding(minutes: r.0)
                                app.newEvent(at: s, end: day.startOfDay.adding(minutes: r.1))
                            }
                            createRange = nil
                        })
                    .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { v in
                        let m = max(0, snap(v.location.y) - 0)
                        app.newEvent(at: day.startOfDay.adding(minutes: m))
                    })

                ForEach(placed) { p in
                    let cw = w / CGFloat(p.cols)
                    let h = max(CGFloat(p.endMin - p.startMin) / 60 * hourHeight, 20)
                    TimedEventBlock(item: p.item, day: day, size: CGSize(width: cw - 3, height: h - 1), dayWidth: w,
                                    hourHeight: hourHeight, multiDay: multiDay)
                        .offset(x: CGFloat(p.col) * cw + 1, y: CGFloat(p.startMin) / 60 * hourHeight + 0.5)
                }

                if let r = createRange {
                    RoundedRectangle(cornerRadius: 6).fill(Theme.accent.opacity(0.22))
                        .overlay(alignment: .topLeading) {
                            Text(timeRangeText(day.startOfDay.adding(minutes: r.0), day.startOfDay.adding(minutes: r.1)))
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent).padding(5)
                        }
                        .frame(width: w - 4, height: CGFloat(r.1 - r.0) / 60 * hourHeight)
                        .offset(x: 2, y: CGFloat(r.0) / 60 * hourHeight)
                        .allowsHitTesting(false)
                }

                if day.isToday {
                    HStack(spacing: 0) {
                        Circle().fill(Theme.accent).frame(width: 8, height: 8).offset(x: -4)
                        Rectangle().fill(Theme.accent).frame(height: 1.5)
                    }
                    .offset(y: app.now.minutesIntoDay / 60 * hourHeight - 4)
                    .allowsHitTesting(false)
                }
            }
        }
    }
}

// MARK: - Event blocks

private struct TimedEventBlock: View {
    @Environment(AppState.self) private var app
    let item: EventItem
    let day: Date
    let size: CGSize
    let dayWidth: CGFloat
    let hourHeight: Double
    let multiDay: Bool
    @State private var drag: CGSize = .zero
    @State private var resize: CGFloat = 0
    @State private var hover = false

    private var quarter: CGFloat { CGFloat(hourHeight) / 4 }
    private var snappedDY: CGFloat { (drag.height / quarter).rounded() * quarter }
    private var dayShift: Int { multiDay ? Int((drag.width / dayWidth).rounded()) : 0 }
    private var snappedResize: CGFloat { (resize / quarter).rounded() * quarter }
    private var dragging: Bool { drag != .zero || resize != 0 }

    var body: some View {
        let selected = app.selected?.id == item.id
        let h = max(18, size.height + snappedResize)
        let past = item.lastInstant < app.now
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(item.color.opacity(selected ? 0.34 : hover ? 0.24 : 0.17))
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(item.color)
                .frame(width: 3.5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .mask(RoundedRectangle(cornerRadius: 6, style: .continuous))
            content(height: h)
                .padding(.leading, 9).padding(.trailing, 5).padding(.top, 3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .foregroundStyle(item.color.eventText())
        .frame(width: size.width, height: h)
        .opacity(past && !dragging ? 0.62 : 1)
        .overlay(alignment: .bottom) {
            if item.isEditable {
                Color.clear.frame(height: 7).contentShape(Rectangle())
                    .onHover { if $0 { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
                    .gesture(DragGesture(minimumDistance: 2)
                        .onChanged { resize = $0.translation.height }
                        .onEnded { _ in
                            let delta = Double(snappedResize / CGFloat(hourHeight) * 60)
                            resize = 0
                            if delta != 0 { app.move(item, start: item.start, end: max(item.start.adding(minutes: 15), item.end.adding(minutes: delta))) }
                        })
            }
        }
        .offset(x: CGFloat(dayShift) * dayWidth, y: snappedDY)
        .zIndex(dragging ? 10 : (selected ? 5 : 0))
        .shadow(color: .black.opacity(dragging ? 0.2 : 0), radius: 8, y: 3)
        .onHover { hover = $0 }
        .onTapGesture(count: 2) { app.edit(item) }
        .onTapGesture { app.selected = item }
        .gesture(DragGesture(minimumDistance: 6)
            .onChanged { if item.isEditable { drag = $0.translation } }
            .onEnded { _ in
                let delta = Double(snappedDY / CGFloat(hourHeight) * 60)
                let shift = dayShift
                drag = .zero
                guard item.isEditable, delta != 0 || shift != 0 else { return }
                let newStart = item.start.adding(days: shift).addingTimeInterval(delta * 60)
                app.move(item, start: newStart, end: newStart.addingTimeInterval(item.end.timeIntervalSince(item.start)))
            })
        .eventPopover(item)
        .contextMenu { EventContextMenu(item: item) }
    }

    @ViewBuilder private func content(height: CGFloat) -> some View {
        if height < 34 {
            HStack(spacing: 4) {
                Text(item.title.isEmpty ? "(No title)" : item.title).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                Text(item.start.formatted(.dateTime.hour().minute())).font(.system(size: 10.5)).opacity(0.75).lineLimit(1)
                Spacer(minLength: 0)
                if item.meeting != nil { Image(systemName: "video.fill").font(.system(size: 9)) }
            }
        } else {
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .top, spacing: 3) {
                    Text(item.title.isEmpty ? "(No title)" : item.title).font(.system(size: 11.5, weight: .semibold)).lineLimit(height > 60 ? 2 : 1)
                    Spacer(minLength: 0)
                    if item.meeting != nil { Image(systemName: "video.fill").font(.system(size: 9.5)).padding(.top, 2) }
                    if item.isRecurring { Image(systemName: "repeat").font(.system(size: 9)).padding(.top, 2) }
                }
                let liveStart = item.start.adding(minutes: Double(snappedDY / CGFloat(hourHeight) * 60))
                let liveEnd = (dragging && resize != 0) ? item.end.adding(minutes: Double(snappedResize / CGFloat(hourHeight) * 60)) : liveStart.addingTimeInterval(item.end.timeIntervalSince(item.start))
                Text(timeRangeText(dragging ? liveStart : item.start, dragging ? liveEnd : item.end)).font(.system(size: 10.5)).opacity(0.78).lineLimit(1)
                if height > 62, !item.location.isEmpty {
                    Label(item.location, systemImage: "mappin").font(.system(size: 10.5)).opacity(0.78).lineLimit(1)
                }
            }
        }
    }
}

struct BannerChip: View {
    @Environment(AppState.self) private var app
    let item: EventItem

    var body: some View {
        HStack(spacing: 4) {
            Text(item.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6).padding(.vertical, 2.5)
        .foregroundStyle(.white)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(item.color.gradient))
        .onTapGesture(count: 2) { app.edit(item) }
        .onTapGesture { app.selected = item }
        .eventPopover(item)
        .contextMenu { EventContextMenu(item: item) }
    }
}

struct ReminderChip: View {
    @Environment(AppState.self) private var app
    let reminder: ReminderItem

    var body: some View {
        HStack(spacing: 5) {
            Button { app.toggle(reminder) } label: {
                Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle").foregroundStyle(reminder.color)
            }.buttonStyle(.plain)
            Text(reminder.title).font(.system(size: 11)).lineLimit(1)
                .strikethrough(reminder.isCompleted)
                .foregroundStyle(reminder.isOverdue ? Theme.accent : .primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}

struct EventContextMenu: View {
    @Environment(AppState.self) private var app
    let item: EventItem

    var body: some View {
        if let m = item.meeting { Button("Join \(m.service)") { NSWorkspace.shared.open(m.url) } }
        if item.isEditable { Button("Edit…") { app.edit(item) } }
        Button("Duplicate") { app.duplicate(item) }
        Button("Copy Title") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.title, forType: .string) }
        if item.isEditable {
            Divider()
            Button("Delete", role: .destructive) { app.delete(item) }
        }
    }
}
