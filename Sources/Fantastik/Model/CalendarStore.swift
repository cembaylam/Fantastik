import EventKit
import SwiftUI
import Observation

enum AccessState { case unknown, granted, denied, demo }

enum StoreError: LocalizedError {
    case noCalendar, notFound
    var errorDescription: String? {
        switch self {
        case .noCalendar: "No writable calendar is available."
        case .notFound: "The event could not be found."
        }
    }
}

nonisolated func fetchAllReminders(ek: EKEventStore) async -> [ReminderItem] {
    let pred = ek.predicateForReminders(in: nil)
    return await withCheckedContinuation { cont in
        ek.fetchReminders(matching: pred) { res in
            let cutoff = Date().addingTimeInterval(-86400)
            let items: [ReminderItem] = (res ?? []).compactMap { r in
                if r.isCompleted, (r.completionDate ?? .distantPast) < cutoff { return nil }
                var due: Date?
                var hasTime = false
                if let comps = r.dueDateComponents {
                    due = Calendar.current.date(from: comps)
                    hasTime = comps.hour != nil
                }
                let color = Color(nsColor: NSColor(cgColor: r.calendar.cgColor) ?? .systemBlue)
                return ReminderItem(id: r.calendarItemIdentifier, title: r.title ?? "", due: due, hasTime: hasTime,
                                    isCompleted: r.isCompleted, listTitle: r.calendar.title, color: color,
                                    priority: r.priority, notes: r.notes ?? "")
            }
            cont.resume(returning: items)
        }
    }
}

@MainActor @Observable
final class CalendarStore {
    static let shared = CalendarStore()

    let ek = EKEventStore()
    private(set) var access: AccessState = .unknown
    private(set) var calendars: [CalendarInfo] = []
    private(set) var reminderLists: [CalendarInfo] = []
    private(set) var reminders: [ReminderItem] = []
    private(set) var revision = 0
    private(set) var remindersGranted = false

    @ObservationIgnored private var cache: [String: [EventItem]] = [:]
    @ObservationIgnored private var ekByID: [String: EKEvent] = [:]
    @ObservationIgnored var demoCreated: [EventItem] = []
    @ObservationIgnored private var observer: NSObjectProtocol?

    var isDemo: Bool { access == .demo }

    init() {
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: ek, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            access = .granted
            remindersGranted = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
            reload()
        case .denied, .restricted: access = .denied
        default: access = .unknown
        }
    }

    // MARK: Access

    func requestAccess() async {
        let granted = (try? await ek.requestFullAccessToEvents()) ?? false
        access = granted ? .granted : .denied
        if granted {
            remindersGranted = (try? await ek.requestFullAccessToReminders()) ?? false
            reload()
        }
    }

    func enableDemo() {
        access = .demo
        calendars = Self.demoCalendars
        reminderLists = [Self.demoCalendars[1]]
        reminders = Self.demoReminders()
        remindersGranted = true
        reload()
    }

    func reload() {
        cache.removeAll()
        if access == .granted {
            calendars = ek.calendars(for: .event).map(Self.info)
            reminderLists = remindersGranted ? ek.calendars(for: .reminder).map(Self.info) : []
            ekByID.removeAll()
        }
        revision += 1
        if access == .granted && remindersGranted {
            Task { reminders = await fetchAllReminders(ek: ek); revision += 1 }
        }
    }

    private static func info(_ c: EKCalendar) -> CalendarInfo {
        CalendarInfo(id: c.calendarIdentifier, title: c.title,
                     color: Color(nsColor: NSColor(cgColor: c.cgColor) ?? .systemRed),
                     sourceTitle: c.source?.title ?? "Other", isEditable: c.allowsContentModifications)
    }

    var defaultCalendarID: String? {
        if isDemo { return Self.demoCalendars[0].id }
        return ek.defaultCalendarForNewEvents?.calendarIdentifier ?? calendars.first(where: \.isEditable)?.id
    }

    var defaultReminderListID: String? {
        if isDemo { return Self.demoCalendars[1].id }
        return ek.defaultCalendarForNewReminders()?.calendarIdentifier ?? reminderLists.first?.id
    }

    // MARK: Fetching

    func events(from: Date, to: Date) -> [EventItem] {
        _ = revision
        let key = "\(Int(from.timeIntervalSince1970))-\(Int(to.timeIntervalSince1970))"
        if let hit = cache[key] { return hit }
        let result: [EventItem]
        switch access {
        case .demo:
            result = (demoGenerate(from: from, to: to) + demoCreated.filter { $0.start < to && $0.lastInstant >= from })
        case .granted:
            let cals = ek.calendars(for: .event)
            let pred = ek.predicateForEvents(withStart: from, end: to, calendars: cals)
            result = ek.events(matching: pred).filter { $0.status != .canceled }.map(makeItem)
        default: result = []
        }
        if cache.count > 80 { cache.removeAll() }
        cache[key] = result
        return result
    }

    func search(_ text: String) -> [EventItem] {
        let q = text.lowercased()
        guard !q.isEmpty else { return [] }
        let from = Date().adding(days: -365), to = Date().adding(days: 730)
        let all: [EventItem]
        if isDemo {
            all = demoGenerate(from: from, to: to) + demoCreated
        } else if access == .granted {
            let pred = ek.predicateForEvents(withStart: from, end: to, calendars: nil)
            all = ek.events(matching: pred).map(makeItem)
        } else { all = [] }
        return all.filter { $0.title.lowercased().contains(q) || $0.location.lowercased().contains(q) || $0.notes.lowercased().contains(q) }
            .sorted { $0.start < $1.start }
    }

    private func makeItem(_ e: EKEvent) -> EventItem {
        let id = "\(e.eventIdentifier ?? e.calendarItemIdentifier)|\(Int(e.startDate.timeIntervalSince1970))"
        ekByID[id] = e
        let rule = e.recurrenceRules?.first
        let spec = rule.flatMap { RepeatSpec(rule: $0) }
        let attendees: [Attendee] = (e.attendees ?? []).map { p in
            let st: Attendee.Status
            switch p.participantStatus {
            case .accepted: st = .accepted
            case .declined: st = .declined
            case .tentative: st = .tentative
            default: st = .pending
            }
            return Attendee(name: p.name ?? "Unknown", status: st, isOrganizer: p.participantRole == .chair, isMe: p.isCurrentUser)
        }
        let c = e.calendar!
        return EventItem(
            id: id, eventID: e.eventIdentifier ?? e.calendarItemIdentifier,
            title: e.title ?? "", location: e.location ?? "", notes: e.notes ?? "", url: e.url,
            start: e.startDate, end: e.endDate, isAllDay: e.isAllDay,
            calendarID: c.calendarIdentifier, calendarTitle: c.title,
            color: Color(nsColor: NSColor(cgColor: c.cgColor) ?? .systemRed),
            isRecurring: rule != nil || e.hasRecurrenceRules,
            repeatSpec: spec, hasComplexRule: rule != nil && spec == nil,
            repeatSummary: spec?.summary ?? (rule != nil ? "Repeats" : nil),
            attendees: attendees,
            alarmOffsets: (e.alarms ?? []).compactMap { $0.relativeOffset <= 0 ? -$0.relativeOffset : nil },
            timeZoneID: e.timeZone?.identifier,
            isEditable: c.allowsContentModifications, isBusy: e.availability != .free)
    }

    private func ekEvent(for item: EventItem) -> EKEvent? {
        if let e = ekByID[item.id] { return e }
        let pred = ek.predicateForEvents(withStart: item.start.addingTimeInterval(-1), end: item.start.addingTimeInterval(86400), calendars: nil)
        return ek.events(matching: pred).first { $0.eventIdentifier == item.eventID && abs($0.startDate.timeIntervalSince(item.start)) < 1 }
            ?? ek.event(withIdentifier: item.eventID)
    }

    // MARK: Mutations

    @discardableResult
    func save(_ d: EventDraft, existing: EventItem?, span: EKSpan = .thisEvent) throws -> EventItem? {
        let allDayEnd = d.end.startOfDay.endOfDay.addingTimeInterval(-1)
        if isDemo {
            var item = existing ?? EventItem(
                id: "demo-new-\(UUID().uuidString)", eventID: UUID().uuidString, title: "", location: "", notes: "", url: nil,
                start: d.start, end: d.end, isAllDay: d.isAllDay, calendarID: "", calendarTitle: "", color: .red,
                isRecurring: false, repeatSpec: nil, hasComplexRule: false, repeatSummary: nil, attendees: [],
                alarmOffsets: [], timeZoneID: nil, isEditable: true, isBusy: true)
            let cal = calendars.first { $0.id == d.calendarID } ?? calendars[0]
            item.title = d.title; item.location = d.location; item.notes = d.notes
            item.url = URL(string: d.urlString)
            item.start = d.isAllDay ? d.start.startOfDay : d.start
            item.end = d.isAllDay ? allDayEnd : d.end
            item.isAllDay = d.isAllDay
            item.calendarID = cal.id; item.calendarTitle = cal.title; item.color = cal.color
            item.alarmOffsets = d.alerts; item.repeatSpec = d.repeatSpec
            item.isRecurring = d.repeatSpec != nil; item.repeatSummary = d.repeatSpec?.summary
            item.isBusy = d.isBusy
            if existing != nil { demoCreated.removeAll { $0.id == item.id } }
            demoCreated.append(item)
            reload()
            return item
        }

        let ev: EKEvent
        if let existing {
            guard let found = ekEvent(for: existing) else { throw StoreError.notFound }
            ev = found
        } else {
            ev = EKEvent(eventStore: ek)
        }
        guard let cal = ek.calendar(withIdentifier: d.calendarID ?? "") ?? ek.defaultCalendarForNewEvents else { throw StoreError.noCalendar }
        ev.calendar = cal
        ev.title = d.title.isEmpty ? "New Event" : d.title
        ev.location = d.location.isEmpty ? nil : d.location
        ev.notes = d.notes.isEmpty ? nil : d.notes
        ev.url = URL(string: d.urlString.trimmingCharacters(in: .whitespaces))
        ev.isAllDay = d.isAllDay
        ev.startDate = d.isAllDay ? d.start.startOfDay : d.start
        ev.endDate = d.isAllDay ? allDayEnd : max(d.end, d.start.addingTimeInterval(60))
        ev.timeZone = d.timeZoneID.flatMap { TimeZone(identifier: $0) }
        ev.availability = d.isBusy ? .busy : .free
        ev.alarms = d.alerts.map { EKAlarm(relativeOffset: -$0) }
        if !d.keepOriginalRule {
            ev.recurrenceRules = d.repeatSpec.map { [$0.ekRule()] }
        }
        try ek.save(ev, span: span, commit: true)
        reload()
        return nil
    }

    func delete(_ item: EventItem, span: EKSpan = .thisEvent) throws {
        if isDemo { demoCreated.removeAll { $0.id == item.id }; reload(); return }
        guard let ev = ekEvent(for: item) else { throw StoreError.notFound }
        try ek.remove(ev, span: span, commit: true)
        reload()
    }

    func move(_ item: EventItem, start: Date, end: Date) throws {
        if isDemo {
            if let i = demoCreated.firstIndex(of: item) { demoCreated[i].start = start; demoCreated[i].end = end; reload() }
            return
        }
        guard let ev = ekEvent(for: item) else { throw StoreError.notFound }
        ev.startDate = start; ev.endDate = end
        try ek.save(ev, span: .thisEvent, commit: true)
        reload()
    }

    // MARK: Reminders

    func toggle(_ r: ReminderItem) {
        if isDemo {
            if let i = reminders.firstIndex(of: r) { reminders[i].isCompleted.toggle(); revision += 1 }
            return
        }
        guard let rem = ek.calendarItem(withIdentifier: r.id) as? EKReminder else { return }
        rem.isCompleted.toggle()
        try? ek.save(rem, commit: true)
        reload()
    }

    func deleteReminder(_ r: ReminderItem) {
        if isDemo { reminders.removeAll { $0.id == r.id }; revision += 1; return }
        guard let rem = ek.calendarItem(withIdentifier: r.id) as? EKReminder else { return }
        try? ek.remove(rem, commit: true)
        reload()
    }

    func addReminder(title: String, due: Date?, hasTime: Bool, listID: String?, repeatSpec: RepeatSpec?, alertOffsets: [TimeInterval]) throws {
        if isDemo {
            let list = reminderLists.first
            reminders.append(ReminderItem(id: UUID().uuidString, title: title, due: due, hasTime: hasTime, isCompleted: false,
                                          listTitle: list?.title ?? "Reminders", color: list?.color ?? .blue, priority: 0, notes: ""))
            revision += 1
            return
        }
        let r = EKReminder(eventStore: ek)
        r.title = title
        guard let cal = ek.calendar(withIdentifier: listID ?? "") ?? ek.defaultCalendarForNewReminders() else { throw StoreError.noCalendar }
        r.calendar = cal
        if let due {
            let comps: Set<Calendar.Component> = hasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
            r.dueDateComponents = Calendar.current.dateComponents(comps, from: due)
            if hasTime { r.addAlarm(EKAlarm(absoluteDate: due)) }
        }
        if let repeatSpec { r.addRecurrenceRule(repeatSpec.ekRule()) }
        try ek.save(r, commit: true)
        reload()
    }
}
