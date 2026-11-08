import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            CalendarsSettings().tabItem { Label("Calendars", systemImage: "calendar") }
            TemplatesSettings().tabItem { Label("Templates", systemImage: "doc.on.doc") }
            ClocksSettings().tabItem { Label("Time Zones", systemImage: "globe") }
            ShortcutsSettings().tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .frame(width: 560, height: 480)
        .tint(Theme.accent)
    }
}

/// Calendar accounts (iCloud, Google, Exchange, CalDAV…) are managed by macOS and appear in Fantastik automatically.
enum AccountsLink {
    static func open() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension")!)
    }
}

private struct GeneralSettings: View {
    @Environment(AppState.self) private var app
    @AppStorage("firstWeekday") private var firstWeekday = 0
    @AppStorage("defaultDuration") private var duration = 60
    @AppStorage("defaultAlert") private var alert = 10
    @AppStorage("showWeekNumbers") private var weekNumbers = false
    @AppStorage("hideDeclined") private var hideDeclined = true
    @AppStorage("showWeather") private var weather = true
    @AppStorage("useFahrenheit") private var fahrenheit = Locale.current.measurementSystem == .us
    @AppStorage("showMenuBarIcon") private var menuBar = true
    @AppStorage("showNextEventInMenuBar") private var nextInMenu = false

    var body: some View {
        @Bindable var app = app
        Form {
            Section("Accounts") {
                LabeledContent("Calendar accounts") {
                    Button("Add or Manage Accounts…") { AccountsLink.open() }
                }
                Text("iCloud, Google, Microsoft Exchange, Yahoo and CalDAV accounts are connected in System Settings and show up here automatically.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Calendar") {
                Picker("First day of week", selection: $firstWeekday) {
                    Text("System default").tag(0)
                    ForEach(1...7, id: \.self) { Text(Calendar.current.weekdaySymbols[$0 - 1]).tag($0) }
                }
                Picker("Default view", selection: $app.viewMode) { ForEach(ViewMode.allCases) { Text($0.label).tag($0) } }
                Toggle("Show week numbers", isOn: $weekNumbers)
                Toggle("Hide declined events", isOn: $hideDeclined)
            }
            Section("New Events") {
                Picker("Default duration", selection: $duration) {
                    ForEach([15, 30, 45, 60, 90, 120], id: \.self) { Text("\($0) minutes").tag($0) }
                }
                Picker("Default alert", selection: $alert) {
                    Text("None").tag(-1)
                    ForEach([0, 5, 10, 15, 30, 60], id: \.self) { Text($0 == 0 ? "At time of event" : "\($0) minutes before").tag($0) }
                }
            }
            Section("Interesting Calendars") {
                Toggle("Moon phases", isOn: $app.showMoon)
                Toggle("US holidays", isOn: $app.showHolidays)
            }
            Section("Weather") {
                Toggle("Show weather forecast", isOn: $weather)
                Toggle("Use Fahrenheit", isOn: $fahrenheit)
            }
            Section("Menu Bar") {
                Toggle("Show menu bar icon", isOn: $menuBar)
                Toggle("Show next event in menu bar", isOn: $nextInMenu)
            }
        }
        .formStyle(.grouped)
    }
}

private struct CalendarsSettings: View {
    @Environment(AppState.self) private var app
    @State private var selection: UUID?

    var body: some View {
        @Bindable var app = app
        HSplitView {
            List(selection: $selection) {
                Section("Calendar Sets") {
                    ForEach(app.sets) { s in Text(s.name).tag(s.id) }
                }
                Button { app.saveCurrentAsSet(named: "New Set") } label: { Label("Add Set", systemImage: "plus") }.buttonStyle(.plain)
            }
            .frame(minWidth: 160, maxWidth: 200)
            Group {
                if let i = app.sets.firstIndex(where: { $0.id == selection }) {
                    Form {
                        TextField("Name", text: $app.sets[i].name)
                        Section("Calendars in this set") {
                            ForEach(app.allCalendars) { c in
                                Toggle(isOn: Binding(
                                    get: { app.sets[i].calendarIDs.contains(c.id) },
                                    set: { on in
                                        if on { app.sets[i].calendarIDs.append(c.id) } else { app.sets[i].calendarIDs.removeAll { $0 == c.id } }
                                    })) { Label { Text(c.title) } icon: { Image(systemName: "circle.fill").foregroundStyle(c.color) } }
                            }
                        }
                        Button("Delete Set", role: .destructive) {
                            if app.activeSetID == app.sets[i].id { app.activeSetID = nil }
                            app.sets.remove(at: i); selection = nil
                        }
                    }.formStyle(.grouped)
                } else {
                    ContentUnavailableView("Calendar Sets", systemImage: "square.stack.3d.up",
                                           description: Text("Sets let you switch between groups of calendars, like Work and Personal."))
                }
            }
        }
    }
}

private struct TemplatesSettings: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        VStack(alignment: .leading) {
            List {
                ForEach($app.templates) { $t in
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Template name", text: $t.name).font(.headline)
                        HStack {
                            TextField("Event title", text: $t.title)
                            TextField("Location", text: $t.location)
                        }
                        HStack {
                            Stepper("\(t.durationMinutes) min", value: $t.durationMinutes, in: 5...600, step: 5)
                            Spacer()
                            Button(role: .destructive) { app.templates.removeAll { $0.id == t.id } } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                        }
                    }.padding(.vertical, 4)
                }
            }
            Button { app.templates.append(EventTemplate(name: "New Template", title: "", durationMinutes: 30)) } label: { Label("Add Template", systemImage: "plus") }
                .padding([.horizontal, .bottom])
        }
    }
}

private struct ClocksSettings: View {
    @Environment(AppState.self) private var app
    @State private var pick = "Europe/Paris"

    var body: some View {
        @Bindable var app = app
        VStack(alignment: .leading) {
            List {
                ForEach(app.worldClocks, id: \.self) { id in
                    HStack {
                        Text(id.replacingOccurrences(of: "_", with: " "))
                        Spacer()
                        Button { app.worldClocks.removeAll { $0 == id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                    }
                }
            }
            HStack {
                Picker("Add", selection: $pick) {
                    ForEach(TimeZone.knownTimeZoneIdentifiers.sorted(), id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")).tag($0) }
                }
                Button("Add") { if !app.worldClocks.contains(pick) { app.worldClocks.append(pick) } }
            }.padding()
        }
    }
}

private struct ShortcutsSettings: View {
    var body: some View {
        Form {
            Section("Global") {
                LabeledContent("Quick entry anywhere", value: "⌃⌥ Space")
            }
            Section("In the app") {
                LabeledContent("New event (focus entry field)", value: "⌘N")
                LabeledContent("New event with details", value: "⇧⌘N")
                LabeledContent("Today", value: "⌘T")
                LabeledContent("Previous / next", value: "⌘[  /  ⌘]")
                LabeledContent("Day, Week, Month, Year, List", value: "⌘1 – ⌘5")
                LabeledContent("Find openings", value: "⌥⌘O")
                LabeledContent("Search", value: "⌘F")
                LabeledContent("Edit selected event", value: "⌘E")
            }
        }.formStyle(.grouped)
    }
}
