import SwiftUI

struct MenuBarLabel: View {
    @Environment(AppState.self) private var app
    @Environment(\.openWindow) private var openWindow
    @AppStorage("showNextEventInMenuBar") private var showNext = false

    var body: some View {
        HStack(spacing: 5) {
            Image(nsImage: IconRenderer.menuBarImage(day: app.now.dayNumber))
            if showNext, let e = app.nextEvent {
                let mins = Int(e.start.timeIntervalSince(app.now) / 60)
                Text(mins <= 0 ? "\(trim(e.title)) now" : mins < 60 ? "\(trim(e.title)) in \(mins)m" : "\(trim(e.title)) \(e.start.timeText)")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openMainWindow)) { _ in
            openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func trim(_ s: String) -> String { s.count > 22 ? String(s.prefix(21)) + "…" : s }
}

extension Notification.Name {
    static let openMainWindow = Notification.Name("FantastikOpenMainWindow")
}

struct MenuBarView: View {
    @Environment(AppState.self) private var app
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 12) {
            switch app.store.access {
            case .unknown, .denied:
                VStack(spacing: 10) {
                    Text("Calendar access needed").font(.headline)
                    Button("Open Fantastik") { openMain() }.buttonStyle(.borderedProminent)
                }.padding(.vertical, 30)
            default:
                QuickEntryField()
                MiniMonthView(cell: 31)
                ScrollView {
                    DayAgendaList(days: (0..<3).map { app.selectedDate.startOfDay.adding(days: $0) }, showEmptyDays: false)
                }
                .frame(minHeight: 120, maxHeight: 280)
            }
            Divider()
            HStack {
                Button("Open Fantastik") { openMain() }.buttonStyle(.plain).font(.system(size: 12.5, weight: .medium))
                Spacer()
                Button("Today") { app.goToday() }.buttonStyle(.plain).font(.system(size: 12.5)).foregroundStyle(.secondary)
                SettingsLink { Image(systemName: "gearshape") }.buttonStyle(.plain).foregroundStyle(.secondary)
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 350)
        .tint(Theme.accent)
    }

    private func openMain() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
