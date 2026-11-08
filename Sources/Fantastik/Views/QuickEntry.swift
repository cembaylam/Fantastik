import SwiftUI

struct QuickEntryField: View {
    @Environment(AppState.self) private var app
    @State private var text: String
    @FocusState private var focused: Bool
    var large = false

    init(large: Bool = false, autofocus: Bool = false, initialText: String = "", onCommit: (() -> Void)? = nil) {
        self.large = large; self.autofocus = autofocus; self.onCommit = onCommit
        _text = State(initialValue: initialText)
    }
    var autofocus = false
    var onCommit: (() -> Void)? = nil

    private var parsed: ParsedEntry {
        EntryParser(now: app.now, reference: app.selectedDate, defaultDuration: app.defaultDuration).parse(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkle").font(.system(size: large ? 17 : 13, weight: .semibold)).foregroundStyle(Theme.accent)
                TextField("New event or reminder…", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: large ? 20 : 13.5))
                    .focused($focused)
                    .onSubmit(commit)
                    .onKeyPress(.return, phases: .down) { press in
                        guard press.modifiers.contains(.command), !text.isEmpty else { return .ignored }
                        openInEditor(); return .handled
                    }
                    .onKeyPress(.escape) {
                        if text.isEmpty { return .ignored }
                        text = ""; return .handled
                    }
                if !text.isEmpty {
                    Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, large ? 16 : 10).padding(.vertical, large ? 14 : 7)
            .background(RoundedRectangle(cornerRadius: large ? 14 : 9, style: .continuous).fill(.quaternary.opacity(large ? 0.4 : 0.7)))
            .overlay(RoundedRectangle(cornerRadius: large ? 14 : 9, style: .continuous).stroke(focused ? Theme.accent.opacity(0.7) : Theme.hairline, lineWidth: focused ? 1.5 : 1))

            if !text.isEmpty { QuickEntryPreview(entry: parsed) }
            else if large {
                Text("Try “Lunch with Sam tomorrow at noon at Café Lomi”, “Standup every weekday 9:30am /Work” or “Remind me to call mom Friday 5pm”.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 4)
            }
        }
        .onChange(of: app.quickEntryFocusTick) { focused = true }
        .onAppear { if autofocus { DispatchQueue.main.async { focused = true } } }
    }

    private func commit() {
        if app.create(from: parsed) { text = ""; onCommit?() }
    }

    private func openInEditor() {
        let p = parsed
        guard !p.isReminder else { commit(); return }
        let s = p.start ?? app.now.nextHour
        var d = EventDraft(start: s, end: p.end ?? s.addingTimeInterval(app.defaultDuration), isAllDay: p.isAllDay)
        d.title = p.title; d.location = p.location ?? ""; d.urlString = p.url?.absoluteString ?? ""
        d.calendarID = app.calendarInfo(forHint: p.calendarHint)?.id
        d.repeatSpec = p.repeatSpec; d.alerts = p.alertOffsets
        app.editor = EditorRequest(existing: nil, draft: d)
        text = ""; onCommit?()
    }
}

struct QuickEntryPreview: View {
    @Environment(AppState.self) private var app
    let entry: ParsedEntry

    var body: some View {
        let cal = app.calendarInfo(forHint: entry.calendarHint, reminders: entry.isReminder)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: entry.isReminder ? "checklist" : "calendar").foregroundStyle(cal?.color ?? .secondary)
                Text(entry.title.isEmpty ? "Untitled" : entry.title).font(.system(size: 14, weight: .semibold)).lineLimit(2)
            }
            FlowLayout(spacing: 5) {
                if let s = entry.start {
                    Chip(icon: "calendar", text: dateText(s), tint: .blue)
                    if entry.hasTime, !entry.isReminder, let e = entry.end { Chip(icon: "clock", text: timeRangeText(s, e), tint: .indigo) }
                    else if entry.hasTime { Chip(icon: "clock", text: s.timeText, tint: .indigo) }
                    else if entry.isAllDay { Chip(icon: "sun.max", text: "All day", tint: .orange) }
                }
                if let l = entry.location { Chip(icon: "mappin", text: l, tint: .green) }
                if let r = entry.repeatSpec { Chip(icon: "repeat", text: r.summary, tint: .purple) }
                ForEach(entry.alertOffsets, id: \.self) { Chip(icon: "bell", text: alertText($0), tint: .orange) }
                ForEach(entry.invitees, id: \.self) { Chip(icon: "person.fill", text: $0, tint: .teal) }
                if entry.url != nil { Chip(icon: "link", text: "Link", tint: .gray) }
                if let cal { Chip(icon: "circle.fill", text: cal.title, tint: cal.color) }
            }
            Text("↩ to add  ·  ⌘↩ to edit details").font(.system(size: 10.5)).foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.background.opacity(0.7)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.hairline))
    }

    private func dateText(_ d: Date) -> String {
        if entry.end != nil, entry.isAllDay, let e = entry.end, !e.isSameDay(d) {
            return "\(d.formatted(.dateTime.month(.abbreviated).day())) – \(e.formatted(.dateTime.month(.abbreviated).day()))"
        }
        let rel = d.relativeDayText
        return ["Today", "Tomorrow", "Yesterday"].contains(rel) ? "\(rel), \(d.formatted(.dateTime.month(.abbreviated).day()))" : d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}

private struct Chip: View {
    let icon: String, text: String, tint: Color
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9.5, weight: .semibold))
            Text(text).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
        }
        .padding(.horizontal, 8).padding(.vertical, 3.5)
        .foregroundStyle(tint.mix(with: .primary, by: 0.25))
        .background(Capsule().fill(tint.opacity(0.15)))
    }
}

/// Content of the floating panel opened with the global shortcut.
struct QuickEntryPanelView: View {
    var close: () -> Void
    var initialText = ""
    var body: some View {
        QuickEntryField(large: true, autofocus: true, initialText: initialText, onCommit: close)
            .padding(18)
            .frame(width: 620)
            .glassEffect(.regular, in: .rect(cornerRadius: 26))
            .padding(10)
    }
}
