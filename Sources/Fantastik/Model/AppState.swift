import SwiftUI
import EventKit
import Observation

enum ViewMode: String, CaseIterable, Identifiable {
    case day, week, month, year, list
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var shortcut: KeyEquivalent { KeyEquivalent(Character("\(ViewMode.allCases.firstIndex(of: self)! + 1)")) }
}

struct CalendarSet: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var calendarIDs: [String]
}

struct EventTemplate: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var title: String
    var durationMinutes: Int
    var location: String = ""
    var calendarID: String?
    var alerts: [TimeInterval] = []
}

struct OpeningSlot: Identifiable, Hashable {
    let start: Date
    let end: Date
    var id: Date { start }
}

@MainActor @Observable
final class AppState {
    static let shared = AppState()

    let store = CalendarStore.shared
    private let defaults = UserDefaults.standard

    var selectedDate = Date()
    var now = Date()
    var viewMode: ViewMode { didSet { defaults.set(viewMode.rawValue, forKey: "viewMode") } }
    var selected: EventItem?
    var editor: EditorRequest?
    var searchText = ""
    var toast: String?
    var quickEntryFocusTick = 0
    var showOpenings = false
    var showTemplates = false

    var hiddenCalendarIDs: Set<String> { didSet { defaults.set(Array(hiddenCalendarIDs), forKey: "hiddenCalendarIDs") } }
    var sets: [CalendarSet] { didSet { save(sets, key: "calendarSets") } }
    var activeSetID: UUID? { didSet { defaults.set(activeSetID?.uuidString, forKey: "activeSetID") } }
    var templates: [EventTemplate] { didSet { save(templates, key: "eventTemplates") } }
    var worldClocks: [String] { didSet { defaults.set(worldClocks, forKey: "worldClocks") } }
    var showMoon: Bool { didSet { defaults.set(showMoon, forKey: "showMoon"); store.reload() } }
    var showHolidays: Bool { didSet { defaults.set(showHolidays, forKey: "showHolidays"); store.reload() } }

    @ObservationIgnored private var timer: Timer?

    init() {
        viewMode = ViewMode(rawValue: defaults.string(forKey: "viewMode") ?? "") ?? .week
        hiddenCalendarIDs = Set(defaults.stringArray(forKey: "hiddenCalendarIDs") ?? [])
        sets = Self.load([CalendarSet].self, key: "calendarSets") ?? []
        activeSetID = defaults.string(forKey: "activeSetID").flatMap(UUID.init(uuidString:))
        templates = Self.load([EventTemplate].self, key: "eventTemplates") ?? [
            EventTemplate(name: "Coffee Chat", title: "Coffee", durationMinutes: 30),
            EventTemplate(name: "Focus Block", title: "Focus Time", durationMinutes: 120),
        ]
        worldClocks = defaults.stringArray(forKey: "worldClocks") ?? ["America/Los_Angeles", "Europe/London", "Asia/Tokyo"]
        showMoon = defaults.bool(forKey: "showMoon")
        showHolidays = defaults.bool(forKey: "showHolidays")
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.now = Date() }
        }
    }

    private func save<T: Encodable>(_ v: T, key: String) {
        if let d = try? JSONEncoder().encode(v) { defaults.set(d, forKey: key) }
    }
    private static func load<T: Decodable>(_ t: T.Type, key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    // MARK: Preferences

    var defaultDuration: TimeInterval {
        let m = defaults.object(forKey: "defaultDuration") as? Int ?? 60
        return Double(m) * 60
    }
    var defaultAlertMinutes: Int { defaults.object(forKey: "defaultAlert") as? Int ?? 10 }
    var hideDeclined: Bool { defaults.object(forKey: "hideDeclined") as? Bool ?? true }

    // MARK: Calendars & visibility

    var allCalendars: [CalendarInfo] {
        var c = store.calendars
        if showMoon { c.append(InterestingCalendars.moonInfo) }
        if showHolidays { c.append(InterestingCalendars.holidayInfo) }
        return c
    }

    var activeSet: CalendarSet? { sets.first { $0.id == activeSetID } }

    func isVisible(_ id: String) -> Bool {
        if let set = activeSet { return set.calendarIDs.contains(id) }
        return !hiddenCalendarIDs.contains(id)
    }

    func setVisible(_ id: String, _ visible: Bool) {
        if let i = sets.firstIndex(where: { $0.id == activeSetID }) {
            if visible { if !sets[i].calendarIDs.contains(id) { sets[i].calendarIDs.append(id) } }
            else { sets[i].calendarIDs.removeAll { $0 == id } }
        } else if visible { hiddenCalendarIDs.remove(id) } else { hiddenCalendarIDs.insert(id) }
    }

    func saveCurrentAsSet(named name: String) {
        let ids = allCalendars.filter { isVisible($0.id) }.map(\.id)
        let s = CalendarSet(name: name, calendarIDs: ids)
        sets.append(s)
        activeSetID = s.id
    }

    func calendarInfo(forHint hint: String?, reminders: Bool = false) -> CalendarInfo? {
        let pool = reminders ? store.reminderLists : store.calendars.filter(\.isEditable)
        if let hint, !hint.isEmpty {
            let h = hint.lowercased()
            if let m = pool.first(where: { $0.title.lowercased() == h }) ?? pool.first(where: { $0.title.lowercased().hasPrefix(h) }) ?? pool.first(where: { $0.title.lowercased().contains(h) }) {
                return m
            }
        }
        let id = reminders ? store.defaultReminderListID : store.defaultCalendarID
        return pool.first { $0.id == id } ?? pool.first
    }

    // MARK: Events

    func events(from: Date, to: Date) -> [EventItem] {
        var all = store.events(from: from, to: to)
        if showMoon { all += InterestingCalendars.moon(from: from, to: to) }
        if showHolidays { all += InterestingCalendars.holidays(from: from, to: to) }
        let hide = hideDeclined
        return all.filter { isVisible($0.calendarID) && !(hide && $0.myStatus == .declined) }
            .sorted { a, b in
                if a.isAllDay != b.isAllDay { return a.isAllDay }
                if a.start != b.start { return a.start < b.start }
                return a.title < b.title
            }
    }

    func events(on day: Date) -> [EventItem] {
        let s = day.startOfDay
        return events(from: s, to: s.endOfDay).filter { $0.occurs(on: day) }
    }

    func reminders(on day: Date) -> [ReminderItem] {
        store.reminders.filter {
            guard let due = $0.due else { return false }
            return due.isSameDay(day) || ($0.isOverdue && day.isToday)
        }.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
    }

    var nextEvent: EventItem? {
        events(from: now, to: now.adding(days: 1)).first { !$0.isAllDay && $0.end > now }
    }

    // MARK: Navigation

    func step(_ n: Int) {
        switch viewMode {
        case .day: selectedDate = selectedDate.adding(days: n)
        case .week, .list: selectedDate = selectedDate.adding(days: 7 * n)
        case .month: selectedDate = selectedDate.adding(months: n)
        case .year: selectedDate = selectedDate.adding(years: n)
        }
    }

    func goToday() { selectedDate = Date() }

    func jump(to date: Date, mode: ViewMode? = nil) {
        selectedDate = date
        if let mode { viewMode = mode }
    }

    var title: String {
        switch viewMode {
        case .day: return selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
        case .week:
            let s = selectedDate.startOfWeek, e = s.adding(days: 6)
            if s.isSameMonth(e) { return "\(s.formatted(.dateTime.month(.wide).day())) – \(e.formatted(.dateTime.day().year()))" }
            return "\(s.formatted(.dateTime.month(.abbreviated).day())) – \(e.formatted(.dateTime.month(.abbreviated).day().year()))"
        case .month: return selectedDate.formatted(.dateTime.month(.wide).year())
        case .year: return selectedDate.formatted(.dateTime.year())
        case .list: return "Upcoming"
        }
    }

    // MARK: Actions

    func showToast(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            if toast == message { toast = nil }
        }
    }

    func defaultDraft(start: Date? = nil, allDay: Bool = false) -> EventDraft {
        let s = start ?? (selectedDate.isToday ? now.nextHour : selectedDate.settingTime(hour: 9, minute: 0))
        var d = EventDraft(start: s, end: s.addingTimeInterval(allDay ? 0 : defaultDuration), isAllDay: allDay)
        d.calendarID = calendarInfo(forHint: nil)?.id
        if defaultAlertMinutes >= 0 && !allDay { d.alerts = [Double(defaultAlertMinutes) * 60] }
        return d
    }

    func newEvent(at start: Date? = nil, end: Date? = nil, allDay: Bool = false) {
        var d = defaultDraft(start: start, allDay: allDay)
        if let end { d.end = end }
        editor = EditorRequest(existing: nil, draft: d)
    }

    func newEvent(from template: EventTemplate) {
        var d = defaultDraft()
        d.title = template.title; d.location = template.location
        d.end = d.start.addingTimeInterval(Double(template.durationMinutes) * 60)
        if let c = template.calendarID, store.calendars.contains(where: { $0.id == c }) { d.calendarID = c }
        if !template.alerts.isEmpty { d.alerts = template.alerts }
        editor = EditorRequest(existing: nil, draft: d)
    }

    func edit(_ item: EventItem) {
        guard item.isEditable else { return }
        selected = nil
        editor = EditorRequest(existing: item, draft: EventDraft(item: item))
    }

    func duplicate(_ item: EventItem) {
        selected = nil
        var d = EventDraft(item: item)
        d.repeatSpec = nil; d.keepOriginalRule = false
        editor = EditorRequest(existing: nil, draft: d)
    }

    func delete(_ item: EventItem, span: EKSpan = .thisEvent) {
        do { try store.delete(item, span: span); selected = nil; showToast("Deleted “\(item.title)”") }
        catch { showToast(error.localizedDescription) }
    }

    func move(_ item: EventItem, start: Date, end: Date) {
        guard item.isEditable else { return }
        do { try store.move(item, start: start, end: end) } catch { showToast(error.localizedDescription) }
    }

    func toggle(_ r: ReminderItem) { store.toggle(r) }

    /// Create an event or reminder from natural language.
    @discardableResult
    func create(from p: ParsedEntry) -> Bool {
        guard !p.title.isEmpty else { return false }
        do {
            if p.isReminder {
                let list = calendarInfo(forHint: p.calendarHint, reminders: true)
                try store.addReminder(title: p.title, due: p.start, hasTime: p.hasTime, listID: list?.id,
                                      repeatSpec: p.repeatSpec, alertOffsets: p.alertOffsets)
                showToast("Reminder added")
            } else {
                let cal = calendarInfo(forHint: p.calendarHint)
                let s = p.start ?? now.nextHour
                var d = EventDraft(start: s, end: p.end ?? s.addingTimeInterval(defaultDuration), isAllDay: p.isAllDay)
                d.title = p.title; d.location = p.location ?? ""; d.urlString = p.url?.absoluteString ?? ""
                d.calendarID = cal?.id; d.repeatSpec = p.repeatSpec
                d.alerts = p.alertOffsets.isEmpty ? (defaultAlertMinutes >= 0 && !p.isAllDay ? [Double(defaultAlertMinutes) * 60] : []) : p.alertOffsets
                try store.save(d, existing: nil)
                selectedDate = s
                showToast("Added “\(p.title)” to \(cal?.title ?? "calendar")")
            }
            return true
        } catch {
            showToast(error.localizedDescription)
            return false
        }
    }

    // MARK: Openings (free-time finder)

    func openings(duration: TimeInterval, days: Int, from: Date, workStart: Int, workEnd: Int, includeWeekends: Bool) -> [OpeningSlot] {
        var out: [OpeningSlot] = []
        for i in 0..<days {
            let day = from.startOfDay.adding(days: i)
            if !includeWeekends, [1, 7].contains(day.weekdayNumber) { continue }
            let ws = max(day.settingTime(hour: workStart, minute: 0), now), we = day.settingTime(hour: workEnd, minute: 0)
            guard ws < we else { continue }
            let busy = events(on: day).filter { !$0.isAllDay && $0.isBusy && !$0.title.isEmpty }
                .map { ($0.start, $0.lastInstant) }.sorted { $0.0 < $1.0 }
            var cursor = ws
            for (bs, be) in busy {
                if bs > cursor, bs.timeIntervalSince(cursor) >= duration { out.append(OpeningSlot(start: cursor, end: min(bs, we))) }
                cursor = max(cursor, be)
            }
            if we.timeIntervalSince(cursor) >= duration { out.append(OpeningSlot(start: cursor, end: we)) }
        }
        return out
    }
}
