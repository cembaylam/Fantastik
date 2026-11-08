import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var app
    @Environment(\.openSettings) private var openSettings
    @AppStorage("sidebarCalendarsOpen") private var calendarsOpen = true
    @AppStorage("sidebarTasksOpen") private var tasksOpen = true
    @AppStorage("sidebarClocksOpen") private var clocksOpen = true
    @State private var newSetName = ""
    @State private var askSetName = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                QuickEntryField()
                MiniMonthView(cell: 33)

                DayAgendaList(days: [app.selectedDate], showEmptyDays: true)

                SectionBox(title: "Tasks", isOpen: $tasksOpen) {
                    let shownAbove = Set(app.reminders(on: app.selectedDate).map(\.id))
                    let open = app.store.reminders.filter { !$0.isCompleted && !shownAbove.contains($0.id) }
                        .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }.prefix(8)
                    if open.isEmpty { Text(app.store.remindersGranted ? "All caught up" : "Reminders access not granted")
                        .font(.system(size: 12)).foregroundStyle(.tertiary).padding(.horizontal, 8) }
                    ForEach(Array(open)) { r in
                        ReminderRow(reminder: r)
                    }
                }

                SectionBox(title: "Calendars", isOpen: $calendarsOpen, accessory: { setsMenu }) {
                    calendarList
                }

                if !app.worldClocks.isEmpty {
                    SectionBox(title: "World Clock", isOpen: $clocksOpen) {
                        ForEach(app.worldClocks, id: \.self) { id in ClockRow(identifier: id) }
                    }
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 16).padding(.top, 8)
        }
        .scrollContentBackground(.hidden)
        .alert("New Calendar Set", isPresented: $askSetName) {
            TextField("Name", text: $newSetName)
            Button("Create") { if !newSetName.isEmpty { app.saveCurrentAsSet(named: newSetName) }; newSetName = "" }
            Button("Cancel", role: .cancel) { newSetName = "" }
        } message: { Text("Saves the currently visible calendars as a set.") }
    }

    private var setsMenu: some View {
        Menu {
            Button { app.activeSetID = nil } label: { Label("All Calendars", systemImage: app.activeSetID == nil ? "checkmark" : "") }
            if !app.sets.isEmpty { Divider() }
            ForEach(app.sets) { s in
                Button { app.activeSetID = s.id } label: { Label(s.name, systemImage: app.activeSetID == s.id ? "checkmark" : "") }
            }
            Divider()
            Button("New Set from Visible Calendars…") { askSetName = true }
            Button("Manage Sets…") { openSettings() }
            Divider()
            Button("Add Calendar Account…") { AccountsLink.open() }
        } label: {
            Text(app.activeSet?.name ?? "All").font(.system(size: 11, weight: .medium))
        }
        .menuStyle(.borderlessButton).fixedSize()
    }

    private var calendarList: some View {
        let grouped = Dictionary(grouping: app.allCalendars, by: \.sourceTitle).sorted { $0.key < $1.key }
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(grouped, id: \.key) { source, cals in
                VStack(alignment: .leading, spacing: 1) {
                    Text(source.uppercased()).font(.system(size: 9.5, weight: .semibold)).tracking(0.6).foregroundStyle(.tertiary).padding(.horizontal, 8)
                    ForEach(cals.sorted { $0.title < $1.title }) { c in
                        let on = app.isVisible(c.id)
                        Button { app.setVisible(c.id, !on) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 13)).foregroundStyle(c.color)
                                Text(c.title).font(.system(size: 12.5)).foregroundStyle(on ? .primary : .secondary).lineLimit(1)
                                Spacer()
                            }
                            .padding(.vertical, 3).padding(.horizontal, 8).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct SectionBox<Content: View, Accessory: View>: View {
    let title: String
    @Binding var isOpen: Bool
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    init(title: String, isOpen: Binding<Bool>, @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }, @ViewBuilder content: @escaping () -> Content) {
        self.title = title; self._isOpen = isOpen; self.accessory = accessory; self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button { withAnimation(.snappy(duration: 0.2)) { isOpen.toggle() } } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).rotationEffect(.degrees(isOpen ? 90 : 0))
                        Text(title).font(.system(size: 12, weight: .bold))
                    }.foregroundStyle(.secondary)
                }.buttonStyle(.plain)
                Spacer()
                accessory()
            }
            .padding(.horizontal, 8)
            if isOpen { content() }
        }
    }
}

private struct ClockRow: View {
    @Environment(AppState.self) private var app
    let identifier: String

    var body: some View {
        if let tz = TimeZone(identifier: identifier) {
            let diffHours = Double(tz.secondsFromGMT(for: app.now) - TimeZone.current.secondsFromGMT(for: app.now)) / 3600
            let dayLabel: String = {
                var lc = appCalendar()
                let ld = lc.component(.day, from: app.now)
                lc.timeZone = tz
                let rd = lc.component(.day, from: app.now)
                if rd == ld { return "Today" }
                return diffHours > 0 ? "Tomorrow" : "Yesterday"
            }()
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text(identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? identifier)
                        .font(.system(size: 12.5, weight: .medium))
                    Text("\(dayLabel), \(diffHours >= 0 ? "+" : "")\(diffHours.formatted(.number.precision(.fractionLength(0...1))))h")
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
                Spacer()
                Text(app.now.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: tz)))
                    .font(.system(size: 15, weight: .light)).monospacedDigit()
            }
            .padding(.horizontal, 8).padding(.vertical, 2)
        }
    }
}
