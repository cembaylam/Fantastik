import SwiftUI

struct AgendaRow: View {
    @Environment(AppState.self) private var app
    let item: EventItem
    var day: Date? = nil
    var showDate = false

    var body: some View {
        let past = item.lastInstant < app.now
        let live = item.start <= app.now && item.lastInstant > app.now && !item.isAllDay
        HStack(alignment: .top, spacing: 9) {
            VStack(alignment: .trailing, spacing: 1) {
                if item.isAllDay {
                    Text(showDate ? item.start.formatted(.dateTime.month(.abbreviated).day()) : "all-day")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    if showDate { Text(item.start.formatted(.dateTime.weekday(.abbreviated).day())).font(.system(size: 10)).foregroundStyle(.secondary) }
                    Text(item.start.formatted(.dateTime.hour().minute())).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                    Text(item.lastInstant.formatted(.dateTime.hour().minute())).font(.system(size: 10.5)).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .frame(width: 58, alignment: .trailing)

            Capsule().fill(item.color).frame(width: 3.5)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(item.title.isEmpty ? "(No title)" : item.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                    if item.isRecurring { Image(systemName: "repeat").font(.system(size: 9)).foregroundStyle(.tertiary) }
                }
                if !item.location.isEmpty {
                    Text(item.location).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                }
                if live {
                    Text("Now").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.accent)
                }
            }
            Spacer(minLength: 0)
            if let m = item.meeting {
                Button { NSWorkspace.shared.open(m.url) } label: {
                    Image(systemName: "video.fill").font(.system(size: 10)).foregroundStyle(.white)
                        .frame(width: 24, height: 20).background(Capsule().fill(Color.accentColor))
                }
                .buttonStyle(.plain).help("Join \(m.service)")
            }
        }
        .padding(.vertical, 6).padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(live ? item.color.opacity(0.1) : .clear))
        .opacity(past ? 0.55 : 1)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { app.edit(item) }
        .onTapGesture { app.selected = item }
        .eventPopover(item, edge: .trailing)
        .contextMenu { EventContextMenu(item: item) }
    }
}

struct ReminderRow: View {
    @Environment(AppState.self) private var app
    let reminder: ReminderItem

    var body: some View {
        HStack(spacing: 9) {
            Text(reminder.due.map { reminder.hasTime ? $0.formatted(.dateTime.hour().minute()) : "" } ?? "")
                .font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 58, alignment: .trailing)
            Button { app.toggle(reminder) } label: {
                Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15)).foregroundStyle(reminder.color)
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 1) {
                Text(reminder.title).font(.system(size: 13)).strikethrough(reminder.isCompleted)
                    .foregroundStyle(reminder.isCompleted ? .secondary : .primary).lineLimit(2)
                if reminder.isOverdue, let due = reminder.due {
                    Text("Overdue · " + due.formatted(.dateTime.month(.abbreviated).day())).font(.system(size: 10.5)).foregroundStyle(Theme.accent)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4).padding(.horizontal, 8)
        .contextMenu { Button("Delete", role: .destructive) { app.store.deleteReminder(reminder) } }
    }
}

struct DayHeaderLabel: View {
    let day: Date
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(day.relativeDayText.components(separatedBy: " ").first.map { ["Today", "Tomorrow", "Yesterday"].contains($0) ? $0 : day.formatted(.dateTime.weekday(.wide)) } ?? "")
                .font(.system(size: 15, weight: .bold)).foregroundStyle(day.isToday ? Theme.accent : .primary)
            Text(day.formatted(.dateTime.month(.wide).day())).font(.system(size: 12.5)).foregroundStyle(.secondary)
            Spacer()
            WeatherBadge(day: day, showLow: true)
        }
    }
}

/// Events + reminders for a set of days, used by the sidebar, list view and menu bar window.
struct DayAgendaList: View {
    @Environment(AppState.self) private var app
    let days: [Date]
    var showEmptyDays = false
    var pinned = false

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 4, pinnedViews: pinned ? [.sectionHeaders] : []) {
            ForEach(days, id: \.self) { d in
                let events = app.events(on: d)
                let rem = app.reminders(on: d)
                if showEmptyDays || !events.isEmpty || !rem.isEmpty || d.isToday {
                    Section {
                        if events.isEmpty && rem.isEmpty {
                            Text("Nothing planned").font(.system(size: 12)).foregroundStyle(.tertiary).padding(.horizontal, 8).padding(.bottom, 6)
                        }
                        ForEach(events) { AgendaRow(item: $0, day: d) }
                        ForEach(rem) { ReminderRow(reminder: $0) }
                    } header: {
                        DayHeaderLabel(day: d).padding(.horizontal, 8).padding(.top, 10).padding(.bottom, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(pinned ? AnyShapeStyle(.bar) : AnyShapeStyle(.clear))
                    }
                }
            }
        }
    }
}

struct ListCalendarView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let start = app.selectedDate.startOfDay
        let days = (0..<120).map { start.adding(days: $0) }
        ScrollView {
            DayAgendaList(days: days, pinned: true)
                .padding(.horizontal, 24).padding(.vertical, 8)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
        }
        .background(.background)
    }
}

struct SearchResultsView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let results = app.store.search(app.searchText).filter { app.isVisible($0.calendarID) }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if results.isEmpty {
                    ContentUnavailableView.search(text: app.searchText).padding(.top, 80)
                }
                ForEach(results) { e in
                    VStack(alignment: .leading, spacing: 0) {
                        AgendaRow(item: e, showDate: true)
                        Text(e.start.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                            .font(.system(size: 10.5)).foregroundStyle(.tertiary).padding(.leading, 76).padding(.bottom, 4)
                    }
                    .onTapGesture { app.jump(to: e.start, mode: .day); app.searchText = "" }
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
            .frame(maxWidth: 720).frame(maxWidth: .infinity)
        }
        .background(.background)
    }
}
