import SwiftUI
import EventKit

private enum RepeatPreset: String, CaseIterable, Identifiable {
    case never = "Never", daily = "Every Day", weekdays = "Every Weekday", weekly = "Every Week"
    case biweekly = "Every 2 Weeks", monthly = "Every Month", yearly = "Every Year", custom = "Custom…"
    var id: String { rawValue }

    init(_ s: RepeatSpec?) {
        guard let s else { self = .never; return }
        if s.until != nil && s.interval == 1 && s.weekdays.isEmpty { self = RepeatPreset.base(s.freq); return }
        switch (s.freq, s.interval, s.weekdays) {
        case (.daily, 1, []): self = .daily
        case (.weekly, 1, [2, 3, 4, 5, 6]): self = .weekdays
        case (.weekly, 1, []): self = .weekly
        case (.weekly, 2, []): self = .biweekly
        case (.monthly, 1, []): self = .monthly
        case (.yearly, 1, []): self = .yearly
        default: self = .custom
        }
    }
    static func base(_ f: RepeatSpec.Freq) -> RepeatPreset {
        switch f { case .daily: .daily; case .weekly: .weekly; case .monthly: .monthly; case .yearly: .yearly }
    }
    func spec(until: Date?, current: RepeatSpec?) -> RepeatSpec? {
        switch self {
        case .never: nil
        case .daily: RepeatSpec(freq: .daily, until: until)
        case .weekdays: RepeatSpec(freq: .weekly, weekdays: [2, 3, 4, 5, 6], until: until)
        case .weekly: RepeatSpec(freq: .weekly, until: until)
        case .biweekly: RepeatSpec(freq: .weekly, interval: 2, until: until)
        case .monthly: RepeatSpec(freq: .monthly, until: until)
        case .yearly: RepeatSpec(freq: .yearly, until: until)
        case .custom: current ?? RepeatSpec(freq: .weekly, until: until)
        }
    }
}

struct EventEditorView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let request: EditorRequest
    @State private var draft: EventDraft
    @State private var preset: RepeatPreset
    @State private var endsRepeat: Bool
    @State private var showSpanDialog = false
    @State private var errorText: String?
    @FocusState private var titleFocused: Bool

    private static let alertOptions: [TimeInterval] = [0, 300, 600, 900, 1800, 3600, 7200, 86400, 172800, 604800]

    init(request: EditorRequest) {
        self.request = request
        _draft = State(initialValue: request.draft)
        _preset = State(initialValue: RepeatPreset(request.draft.repeatSpec))
        _endsRepeat = State(initialValue: request.draft.repeatSpec?.until != nil)
    }

    private var isNew: Bool { request.existing == nil }
    private var tz: TimeZone { draft.timeZoneID.flatMap(TimeZone.init(identifier:)) ?? .current }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isNew ? "New Event" : "Edit Event").font(.system(size: 15, weight: .semibold))
                Spacer()
                Menu {
                    Button("Save as Template…") {
                        let mins = max(15, Int(draft.end.timeIntervalSince(draft.start) / 60))
                        app.templates.append(EventTemplate(name: draft.title.isEmpty ? "Template" : draft.title, title: draft.title,
                                                           durationMinutes: mins, location: draft.location, calendarID: draft.calendarID, alerts: draft.alerts))
                        app.showToast("Template saved")
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize()
            }
            .padding(.horizontal, 20).padding(.vertical, 14)

            Form {
                Section {
                    TextField("Title", text: $draft.title).font(.system(size: 15, weight: .medium)).focused($titleFocused)
                    TextField("Location", text: $draft.location)
                    Picker("Calendar", selection: $draft.calendarID) {
                        ForEach(app.store.calendars.filter(\.isEditable)) { c in
                            Label { Text(c.title) } icon: { Image(systemName: "circle.fill").foregroundStyle(c.color) }.tag(Optional(c.id))
                        }
                    }
                }
                Section {
                    Toggle("All-day", isOn: $draft.isAllDay)
                    DatePicker("Starts", selection: $draft.start, displayedComponents: draft.isAllDay ? [.date] : [.date, .hourAndMinute])
                        .environment(\.timeZone, tz)
                    DatePicker("Ends", selection: $draft.end, in: draft.start..., displayedComponents: draft.isAllDay ? [.date] : [.date, .hourAndMinute])
                        .environment(\.timeZone, tz)
                    if !draft.isAllDay {
                        Picker("Time Zone", selection: $draft.timeZoneID) {
                            Text("Floating (\(TimeZone.current.identifier.replacingOccurrences(of: "_", with: " ")))").tag(String?.none)
                            ForEach(TimeZone.knownTimeZoneIdentifiers.sorted(), id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")).tag(Optional($0)) }
                        }
                    }
                }
                Section {
                    Picker("Repeat", selection: $preset) {
                        ForEach(RepeatPreset.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if preset == .custom { customRepeat }
                    if preset != .never {
                        Toggle("End Repeat", isOn: $endsRepeat)
                        if endsRepeat {
                            DatePicker("Until", selection: Binding(
                                get: { draft.repeatSpec?.until ?? draft.start.adding(months: 3) },
                                set: { draft.repeatSpec?.until = $0 }), displayedComponents: .date)
                        }
                    }
                    if draft.keepOriginalRule && preset == .never {
                        Text("This event uses an advanced repeat rule that will be kept.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Alerts") {
                    ForEach(Array(draft.alerts.enumerated()), id: \.offset) { i, a in
                        HStack {
                            Picker("Alert", selection: Binding(get: { draft.alerts[i] }, set: { draft.alerts[i] = $0 })) {
                                ForEach(Array(Set(Self.alertOptions + [a])).sorted(), id: \.self) { Text(alertText($0)).tag($0) }
                            }.labelsHidden()
                            Button { draft.alerts.remove(at: i) } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.secondary) }
                                .buttonStyle(.plain)
                        }
                    }
                    Button { draft.alerts.append(draft.alerts.last.map { $0 + 300 } ?? 600) } label: { Label("Add Alert", systemImage: "plus.circle") }
                        .buttonStyle(.plain).foregroundStyle(Color.accentColor)
                }
                Section {
                    Picker("Show As", selection: $draft.isBusy) { Text("Busy").tag(true); Text("Free").tag(false) }
                    TextField("URL", text: $draft.urlString)
                    TextField("Notes", text: $draft.notes, axis: .vertical).lineLimit(3...8)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()
            HStack {
                if let errorText { Text(errorText).font(.footnote).foregroundStyle(.red) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save") { save() }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .frame(width: 480, height: 640)
        .onAppear { titleFocused = true }
        .onChange(of: draft.start) { old, new in
            draft.end = draft.end.addingTimeInterval(new.timeIntervalSince(old))
        }
        .onChange(of: draft.isAllDay) { _, on in
            if on { draft.end = draft.start } else if draft.end <= draft.start { draft.end = draft.start.addingTimeInterval(app.defaultDuration) }
        }
        .onChange(of: preset) { _, p in
            draft.keepOriginalRule = false
            draft.repeatSpec = p.spec(until: endsRepeat ? (draft.repeatSpec?.until ?? draft.start.adding(months: 3)) : nil, current: draft.repeatSpec)
        }
        .onChange(of: endsRepeat) { _, on in draft.repeatSpec?.until = on ? (draft.repeatSpec?.until ?? draft.start.adding(months: 3)) : nil }
        .confirmationDialog("This is a repeating event.", isPresented: $showSpanDialog, titleVisibility: .visible) {
            Button("Save for This Event Only") { commit(.thisEvent) }
            Button("Save for Future Events") { commit(.futureEvents) }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder private var customRepeat: some View {
        let spec = draft.repeatSpec ?? RepeatSpec(freq: .weekly)
        Stepper("Every \(spec.interval) \(spec.freq.unit)\(spec.interval == 1 ? "" : "s")", value: Binding(
            get: { draft.repeatSpec?.interval ?? 1 }, set: { draft.repeatSpec?.interval = $0 }), in: 1...99)
        Picker("Unit", selection: Binding(get: { draft.repeatSpec?.freq ?? .weekly }, set: { draft.repeatSpec?.freq = $0 })) {
            ForEach(RepeatSpec.Freq.allCases, id: \.self) { Text($0.unit.capitalized + "s").tag($0) }
        }
        if spec.freq == .weekly {
            HStack(spacing: 4) {
                let syms = appCalendar().veryShortStandaloneWeekdaySymbols
                ForEach(1...7, id: \.self) { d in
                    let on = spec.weekdays.contains(d)
                    Button(syms[d - 1]) {
                        if on { draft.repeatSpec?.weekdays.removeAll { $0 == d } } else { draft.repeatSpec?.weekdays.append(d) }
                    }
                    .buttonStyle(.plain).font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(on ? Color.accentColor : Color.primary.opacity(0.08)))
                    .foregroundStyle(on ? .white : .primary)
                }
            }
        }
    }

    private func save() {
        if let e = request.existing, e.isRecurring { showSpanDialog = true } else { commit(.thisEvent) }
    }

    private func commit(_ span: EKSpan) {
        do {
            if draft.title.trimmingCharacters(in: .whitespaces).isEmpty { draft.title = "New Event" }
            try app.store.save(draft, existing: request.existing, span: span)
            app.selectedDate = draft.start
            dismiss()
        } catch { errorText = error.localizedDescription }
    }
}
