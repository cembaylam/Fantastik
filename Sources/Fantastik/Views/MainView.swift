import SwiftUI

struct MainView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 270, ideal: 300, max: 380)
        } detail: {
            ContentArea()
                .navigationTitle(app.title)
                .navigationSubtitle(app.viewMode == .week ? "Week \(app.selectedDate.weekOfYear)" : "")
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $app.viewMode) {
                    ForEach(ViewMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 280)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { app.step(-1) } label: { Image(systemName: "chevron.left") }.help("Previous")
                Button("Today") { app.goToday() }.help("Go to today")
                Button { app.step(1) } label: { Image(systemName: "chevron.right") }.help("Next")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("New Event…") { app.newEvent() }
                    Menu("New from Template") { TemplatesMenu() }
                    Divider()
                    Button("Find Openings…") { app.showOpenings = true }
                } label: { Image(systemName: "plus") } primaryAction: { app.newEvent() }
                    .help("New event")
            }
        }
        .searchable(text: $app.searchText, placement: .toolbar, prompt: "Search events")
        .sheet(item: $app.editor) { EventEditorView(request: $0) }
        .sheet(isPresented: $app.showOpenings) { OpeningsView() }
        .overlay(alignment: .bottom) {
            if let t = app.toast {
                Text(t).font(.system(size: 13, weight: .medium)).padding(.horizontal, 16).padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: app.toast)
        .frame(minWidth: 980, minHeight: 640)
        .tint(Theme.accent)
        .task { WeatherService.shared.start() }
    }
}

private struct ContentArea: View {
    @Environment(AppState.self) private var app

    var body: some View {
        switch app.store.access {
        case .unknown, .denied:
            OnboardingView()
        default:
            if !app.searchText.isEmpty {
                SearchResultsView()
            } else {
                switch app.viewMode {
                case .day: TimelineCalendarView(days: [app.selectedDate.startOfDay])
                case .week: TimelineCalendarView(days: (0..<7).map { app.selectedDate.startOfWeek.adding(days: $0) })
                case .month: MonthView()
                case .year: YearView()
                case .list: ListCalendarView()
                }
            }
        }
    }
}

struct OnboardingView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let denied = app.store.access == .denied
        VStack(spacing: 18) {
            Image(nsImage: IconRenderer.appIcon(size: 128, date: Date())).resizable().frame(width: 96, height: 96)
            Text("Welcome to Fantastik").font(.system(size: 28, weight: .bold))
            Text(denied ? "Calendar access is turned off. Enable it in System Settings → Privacy & Security → Calendars to see your events."
                        : "Fantastik shows every calendar and reminder list you’ve set up in System Settings — iCloud, Google, Exchange and more.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 420)
            VStack(spacing: 10) {
                if denied {
                    Button("Open System Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                    }.buttonStyle(.borderedProminent).controlSize(.large)
                } else {
                    Button("Allow Calendar Access") { Task { await app.store.requestAccess() } }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                }
                Button("Explore with Sample Data") { app.store.enableDemo() }.buttonStyle(.link)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
