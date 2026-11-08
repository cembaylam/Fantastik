import SwiftUI

/// Premium "Openings"-style helper: finds free slots and copies them as shareable text.
struct OpeningsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var duration = 30
    @State private var days = 7
    @State private var workStart = 9
    @State private var workEnd = 17
    @State private var weekends = false
    @State private var picked: Set<Date> = []

    var body: some View {
        let slots = app.openings(duration: Double(duration) * 60, days: days, from: Date(), workStart: workStart, workEnd: workEnd, includeWeekends: weekends)
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Find Openings").font(.system(size: 16, weight: .semibold))
                    Text("Pick times to share with someone you’re scheduling with.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(20)

            Form {
                Picker("Meeting length", selection: $duration) {
                    ForEach([15, 30, 45, 60, 90, 120], id: \.self) { Text("\($0) minutes").tag($0) }
                }
                Picker("Look ahead", selection: $days) {
                    ForEach([3, 7, 14, 21], id: \.self) { Text("\($0) days").tag($0) }
                }
                HStack {
                    Picker("Working hours", selection: $workStart) { ForEach(0..<24, id: \.self) { Text(label($0)).tag($0) } }
                    Text("to")
                    Picker("", selection: $workEnd) { ForEach(1..<25, id: \.self) { Text(label($0 % 24)).tag($0) } }.labelsHidden()
                }
                Toggle("Include weekends", isOn: $weekends)
            }
            .formStyle(.grouped).scrollContentBackground(.hidden).frame(height: 190)

            List {
                if slots.isEmpty { Text("No openings in this range.").foregroundStyle(.secondary) }
                ForEach(groupedDays(slots), id: \.0) { day, list in
                    Section(day.formatted(.dateTime.weekday(.wide).month(.wide).day())) {
                        ForEach(list) { s in
                            let on = picked.contains(s.start)
                            Button {
                                if on { picked.remove(s.start) } else { picked.insert(s.start) }
                            } label: {
                                HStack {
                                    Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? Color.accentColor : .secondary)
                                    Text(timeRangeText(s.start, s.end))
                                    Spacer()
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.inset)

            Divider()
            HStack {
                Text("\(picked.count) selected").foregroundStyle(.secondary).font(.system(size: 12))
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Copy Times") { copy(slots) }.buttonStyle(.borderedProminent).disabled(picked.isEmpty)
            }.padding(14)
        }
        .frame(width: 480, height: 640)
    }

    private func label(_ h: Int) -> String { Date().settingTime(hour: h, minute: 0).formatted(.dateTime.hour()) }

    private func groupedDays(_ slots: [OpeningSlot]) -> [(Date, [OpeningSlot])] {
        Dictionary(grouping: slots) { $0.start.startOfDay }.sorted { $0.key < $1.key }.map { ($0.key, $0.value.sorted { $0.start < $1.start }) }
    }

    private func copy(_ slots: [OpeningSlot]) {
        let tz = TimeZone.current.localizedName(for: .shortStandard, locale: .current) ?? TimeZone.current.identifier
        var lines = ["I’m available at these times (\(tz)) for \(duration) minutes:", ""]
        for (day, list) in groupedDays(slots) {
            let chosen = list.filter { picked.contains($0.start) }
            guard !chosen.isEmpty else { continue }
            lines.append("• " + day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) + ": " +
                         chosen.map { timeRangeText($0.start, $0.end) }.joined(separator: ", "))
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        app.showToast("Copied \(picked.count) times")
        dismiss()
    }
}

struct TemplatesMenu: View {
    @Environment(AppState.self) private var app
    var body: some View {
        if app.templates.isEmpty { Text("No Templates") }
        ForEach(app.templates) { t in
            Button("\(t.name) · \(t.durationMinutes) min") { app.newEvent(from: t) }
        }
    }
}
