import SwiftUI
import MapKit
import EventKit

func alertText(_ secs: TimeInterval) -> String {
    if secs == 0 { return "At time of event" }
    func plural(_ n: Int, _ u: String) -> String { "\(n) \(u)\(n == 1 ? "" : "s") before" }
    if secs < 3600 { return plural(Int(secs / 60), "minute") }
    if secs < 86400 { return plural(Int(secs / 3600), "hour") }
    if secs < 604800 { return plural(Int(secs / 86400), "day") }
    return plural(Int(secs / 604800), "week")
}

extension View {
    func eventPopover(_ item: EventItem, edge: Edge = .trailing) -> some View {
        modifier(EventPopoverModifier(item: item, edge: edge))
    }
}

private struct EventPopoverModifier: ViewModifier {
    @Environment(AppState.self) private var app
    let item: EventItem
    let edge: Edge

    func body(content: Content) -> some View {
        content.popover(isPresented: Binding(
            get: { app.selected?.id == item.id },
            set: { if !$0, app.selected?.id == item.id { app.selected = nil } }
        ), arrowEdge: edge) {
            EventDetailView(item: item)
        }
    }
}

/// Premium: travel time to the event location, via MapKit.
@MainActor @Observable
final class TravelEstimator {
    var minutes: Int?
    var loading = false

    func estimate(to place: String) async {
        guard !place.isEmpty else { return }
        loading = true; defer { loading = false }
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = place
        guard let dest = try? await MKLocalSearch(request: req).start().mapItems.first else { return }
        let dr = MKDirections.Request()
        dr.source = MKMapItem.forCurrentLocation()
        dr.destination = dest
        dr.transportType = .automobile
        if let eta = try? await MKDirections(request: dr).calculateETA() {
            minutes = Int((eta.expectedTravelTime / 60).rounded())
        }
    }
}

struct EventDetailView: View {
    @Environment(AppState.self) private var app
    let item: EventItem
    @State private var travel = TravelEstimator()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title.isEmpty ? "(No title)" : item.title).font(.system(size: 17, weight: .bold)).textSelection(.enabled)
                    Text(item.start.formatted(.dateTime.weekday(.wide).month(.wide).day().year())).font(.system(size: 12.5)).foregroundStyle(.secondary)
                    Text(item.timeSummary).font(.system(size: 12.5)).foregroundStyle(.secondary)
                    if let r = item.repeatSummary {
                        Label(r, systemImage: "repeat").font(.system(size: 11.5)).foregroundStyle(.secondary)
                    }
                    if let tz = item.timeZoneID, tz != TimeZone.current.identifier, !item.isAllDay {
                        Label(tz.replacingOccurrences(of: "_", with: " "), systemImage: "globe").font(.system(size: 11.5)).foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, 10)
            }
            .background(alignment: .leading) { Capsule().fill(item.color).frame(width: 4) }

            if let m = item.meeting {
                Button { NSWorkspace.shared.open(m.url) } label: {
                    Label("Join \(m.service) Meeting", systemImage: "video.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
            }

            if !item.location.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        if let q = item.location.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                           let u = URL(string: "https://maps.apple.com/?q=\(q)") { NSWorkspace.shared.open(u) }
                    } label: { Label(item.location, systemImage: "mappin.and.ellipse").multilineTextAlignment(.leading) }
                        .buttonStyle(.plain).font(.system(size: 12.5))
                    if let mins = travel.minutes {
                        let leave = item.start.addingTimeInterval(-Double(mins) * 60)
                        Label("\(mins) min drive · leave by \(leave.timeText)", systemImage: "car.fill")
                            .font(.system(size: 11.5)).foregroundStyle(.secondary)
                    }
                }
                .task(id: item.id) { if item.start > app.now, item.meeting == nil { await travel.estimate(to: item.location) } }
            }

            infoRows

            if !item.attendees.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(item.attendees.count) Invitees").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    ForEach(item.attendees.prefix(8)) { a in
                        HStack(spacing: 6) {
                            Image(systemName: a.symbol).foregroundStyle(a.tint).font(.system(size: 11))
                            Text(a.name + (a.isOrganizer ? " (organizer)" : "")).font(.system(size: 12))
                        }
                    }
                    if item.attendees.count > 8 { Text("+\(item.attendees.count - 8) more").font(.system(size: 11)).foregroundStyle(.secondary) }
                }
            }

            if !item.notes.isEmpty {
                ScrollView { Text(item.notes).font(.system(size: 12)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: 110)
                    .padding(8).background(RoundedRectangle(cornerRadius: 8).fill(Theme.subtleFill))
            }

            Divider()
            HStack {
                if item.isEditable { Button("Edit") { app.edit(item) }.keyboardShortcut("e", modifiers: .command) }
                Button("Duplicate") { app.duplicate(item) }
                Spacer()
                if item.isEditable {
                    if item.isRecurring {
                        Menu("Delete") {
                            Button("This Event Only") { app.delete(item, span: .thisEvent) }
                            Button("This and Future Events") { app.delete(item, span: .futureEvents) }
                        }.fixedSize()
                    } else {
                        Button("Delete", role: .destructive) { app.delete(item) }
                    }
                }
            }
            .controlSize(.regular)
        }
        .padding(16)
        .frame(width: 340)
    }

    @ViewBuilder private var infoRows: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(item.alarmOffsets.sorted(), id: \.self) { a in
                Label(alertText(a), systemImage: "bell").font(.system(size: 12))
            }
            Label {
                Text(item.calendarTitle)
            } icon: {
                Circle().fill(item.color).frame(width: 9, height: 9)
            }.font(.system(size: 12))
            if let u = item.url, item.meeting == nil {
                Link(destination: u) { Label(u.absoluteString, systemImage: "link").lineLimit(1) }.font(.system(size: 12))
            }
            if !item.isBusy { Label("Shown as free", systemImage: "circle.dashed").font(.system(size: 12)).foregroundStyle(.secondary) }
        }
        .foregroundStyle(.secondary)
    }
}
