import Foundation

struct ParsedEntry {
    var title = ""
    var start: Date?
    var end: Date?
    var isAllDay = false
    var hasDate = false
    var hasTime = false
    var location: String?
    var calendarHint: String?
    var repeatSpec: RepeatSpec?
    var alertOffsets: [TimeInterval] = []
    var invitees: [String] = []
    var url: URL?
    var isReminder = false
}

/// Fantastical-style natural language parser: "Lunch with Sam tomorrow at noon at Café Lomi /Personal every week".
struct EntryParser {
    var now = Date()
    var reference = Date()
    var defaultDuration: TimeInterval = 3600

    private static let wd = "(?:mon(?:day)?|tue(?:s(?:day)?)?|wed(?:nesday)?|thu(?:r(?:s(?:day)?)?)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?)"
    private static let mo = "(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)"
    private static let numWords: [String: Double] = ["a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "ten": 10,
                                                      "fifteen": 15, "twenty": 20, "thirty": 30, "half": 0.5]

    private final class Work {
        var s: String
        init(_ s: String) { self.s = s }

        @discardableResult
        func take(_ pattern: String, validate: (([String]) -> Bool)? = nil) -> [String]? {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
            let ns = s as NSString
            guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
            var caps: [String] = []
            for i in 0..<m.numberOfRanges {
                let r = m.range(at: i)
                caps.append(r.location == NSNotFound ? "" : ns.substring(with: r))
            }
            if let validate, !validate(caps) { return nil }
            s = ns.replacingCharacters(in: m.range, with: " ")
            return caps
        }
    }

    static func weekdayNumber(_ s: String) -> Int? {
        ["sun": 1, "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7][String(s.lowercased().prefix(3))]
    }
    static func monthNumber(_ s: String) -> Int? {
        ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6, "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12][String(s.lowercased().prefix(3))]
    }

    private func meridiemHour(_ h: Int, _ mer: String) -> Int {
        let m = mer.lowercased().replacingOccurrences(of: ".", with: "")
        if m == "pm" { return h == 12 ? 12 : h + 12 }
        if m == "am" { return h == 12 ? 0 : h }
        if h >= 13 || h == 0 { return h }
        if h >= 1 && h <= 6 { return h + 12 }
        return h
    }

    func parse(_ input: String) -> ParsedEntry {
        let cal = appCalendar()
        let w = Work(input)
        var p = ParsedEntry()

        // Reminder prefix
        if w.take("^\\s*(?:remind me to|remind me about|remind me|reminder:?|todo:?|task:?)\\s+") != nil { p.isReminder = true }

        // URL
        if let c = w.take("https?://\\S+") { p.url = URL(string: c[0]) }

        // Invitees
        while let c = w.take("(?:\\bwith\\s+)?([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,})") { p.invitees.append(c[1]) }

        // Calendar
        if let c = w.take("(?:^|\\s)/\"([^\"]+)\"") { p.calendarHint = c[1] }
        else if let c = w.take("(?:^|\\s)/([A-Za-z][\\w-]*)") { p.calendarHint = c[1] }

        // Alerts
        let unitSecs: (String) -> Double = { u in
            let l = u.lowercased()
            if l.hasPrefix("m") { return 60 }
            if l.hasPrefix("h") { return 3600 }
            if l.hasPrefix("d") { return 86400 }
            return 604800
        }
        while let c = w.take("(?:\\b(?:alert|remind|notify)(?:\\s+me)?\\s+)?\\b(\\d+)\\s*(minutes?|mins?|hours?|hrs?|days?|weeks?)\\s+before\\b") {
            p.alertOffsets.append((Double(c[1]) ?? 0) * unitSecs(c[2]))
        }

        // Recurrence
        let dayList = "(\(Self.wd)(?:\\s*(?:,|and|&)\\s*\(Self.wd))*)"
        func weekdays(in s: String) -> [Int] {
            guard let re = try? NSRegularExpression(pattern: Self.wd, options: .caseInsensitive) else { return [] }
            let ns = s as NSString
            return Array(Set(re.matches(in: s, range: NSRange(location: 0, length: ns.length)).compactMap { Self.weekdayNumber(ns.substring(with: $0.range)) })).sorted()
        }
        func freq(_ s: String) -> RepeatSpec.Freq {
            let l = s.lowercased()
            if l.hasPrefix("d") { return .daily }
            if l.hasPrefix("w") { return .weekly }
            if l.hasPrefix("m") { return .monthly }
            return .yearly
        }
        var impliedWeekday: Int?
        if let c = w.take("\\bevery\\s+(?:other|second|2nd)\\s+(day|week|month|year)\\b") {
            p.repeatSpec = RepeatSpec(freq: freq(c[1]), interval: 2)
        } else if let c = w.take("\\bevery\\s+(\\d+)\\s*(days?|weeks?|months?|years?)\\b") {
            p.repeatSpec = RepeatSpec(freq: freq(c[2]), interval: max(1, Int(c[1]) ?? 1))
        } else if w.take("\\b(?:every\\s+weekday|weekdays)\\b") != nil {
            p.repeatSpec = RepeatSpec(freq: .weekly, weekdays: [2, 3, 4, 5, 6])
        } else if let c = w.take("\\bevery\\s+\(dayList)\\b") {
            let days = weekdays(in: c[1])
            p.repeatSpec = RepeatSpec(freq: .weekly, weekdays: days)
            impliedWeekday = days.first
        } else if let c = w.take("\\b(?:every\\s+(day|week|month|year)|(daily|weekly|monthly|yearly|annually))\\b") {
            p.repeatSpec = RepeatSpec(freq: freq(c[1].isEmpty ? c[2] : c[1]))
        }

        // Duration
        var duration: TimeInterval?
        var spanDays: Int?
        if let c = w.take("\\bfor\\s+(\\d+(?:\\.\\d+)?)\\s*(?:hours?|hrs?|h)(?:\\s*(?:and\\s*)?(\\d+)\\s*(?:minutes?|mins?|m))?\\b") {
            duration = (Double(c[1]) ?? 1) * 3600 + (Double(c[2]) ?? 0) * 60
        } else if let c = w.take("\\bfor\\s+(\\d+)\\s*(?:minutes?|mins?|m)\\b") {
            duration = (Double(c[1]) ?? 30) * 60
        } else if let c = w.take("\\bfor\\s+(\\d+)\\s*days?\\b") {
            spanDays = Int(c[1])
        } else if w.take("\\bfor\\s+half\\s+an?\\s+hour\\b") != nil {
            duration = 1800
        } else if w.take("\\bfor\\s+an?\\s+hour\\b") != nil {
            duration = 3600
        }

        var forcedAllDay = w.take("\\ball[- ]day\\b") != nil

        // noon / midnight
        _ = w.take("\\b(at|from|to|until|till|-)\\s*noon\\b") .map { w.s = " \($0[1]) 12:00pm " + w.s }
        _ = w.take("\\b(at|from|to|until|till|-)\\s*midnight\\b").map { w.s = " \($0[1]) 12:00am " + w.s }
        if let c = w.take("\\b(today|tomorrow|tmrw|\(Self.wd))\\s+noon\\b") { w.s = " \(c[1]) 12:00pm " + w.s }

        // Time range
        var startTime: (Int, Int)?
        var endTime: (Int, Int)?
        let timeRange = "\\b(?:from\\s+)?(\\d{1,2})(?::(\\d{2}))?\\s*(am|pm|a\\.m\\.|p\\.m\\.)?\\s*(?:-|–|to|until|till)\\s*(\\d{1,2})(?::(\\d{2}))?\\s*(am|pm|a\\.m\\.|p\\.m\\.)?(?![\\d/])"
        if let c = w.take(timeRange, validate: { c in !c[3].isEmpty || !c[6].isEmpty || !c[2].isEmpty || !c[5].isEmpty }) {
            var sm = c[3], em = c[6]
            let inheritedStart = sm.isEmpty && !em.isEmpty
            if sm.isEmpty { sm = em }
            if em.isEmpty { em = sm }
            var sh = meridiemHour(Int(c[1]) ?? 0, sm)
            var eh = meridiemHour(Int(c[4]) ?? 0, em)
            if inheritedStart, sh * 60 + (Int(c[2]) ?? 0) >= eh * 60 + (Int(c[5]) ?? 0), sh >= 12 { sh -= 12 }
            if c[6].isEmpty, !c[3].isEmpty, eh * 60 + (Int(c[5]) ?? 0) <= sh * 60 + (Int(c[2]) ?? 0), eh < 12 { eh += 12 }
            startTime = (sh % 24, Int(c[2]) ?? 0)
            endTime = (eh % 24, Int(c[5]) ?? 0)
        }

        // Single time
        var relativeStart: Date?
        if startTime == nil {
            if let c = w.take("\\b(?:(?:at|@|from|around)\\s*)?(\\d{1,2})(?::(\\d{2}))?\\s*(am|pm|a\\.m\\.|p\\.m\\.)(?!\\w)") {
                startTime = (meridiemHour(Int(c[1]) ?? 0, c[3]) % 24, Int(c[2]) ?? 0)
            } else if let c = w.take("\\b(?:at|@)\\s*(\\d{1,2})(?::(\\d{2}))?\\b(?!\\s*(?:st|nd|rd|th|/|-\\d|\\d))") {
                startTime = (meridiemHour(Int(c[1]) ?? 0, "") % 24, Int(c[2]) ?? 0)
            } else if let c = w.take("\\b(\\d{1,2}):([0-5]\\d)\\b") {
                startTime = (meridiemHour(Int(c[1]) ?? 0, "") % 24, Int(c[2]) ?? 0)
            } else if let c = w.take("\\bin\\s+(\\d+(?:\\.\\d+)?|an?|half an?|one|two|three|four|five|ten|fifteen|twenty|thirty)\\s*(minutes?|mins?|hours?|hrs?)\\b") {
                let key = c[1].lowercased().replacingOccurrences(of: " an", with: "").replacingOccurrences(of: " a", with: "")
                let n = Double(c[1]) ?? Self.numWords[key] ?? 1
                relativeStart = now.addingTimeInterval(n * (c[2].lowercased().hasPrefix("h") ? 3600 : 60))
            }
        }

        // Dates
        var day: Date?
        let today = now.startOfDay
        var tonight = false

        func yearResolved(month: Int, dayNum: Int, year: Int?) -> Date? {
            var comps = DateComponents(year: year ?? cal.component(.year, from: now), month: month, day: dayNum)
            guard var d = cal.date(from: comps) else { return nil }
            if year == nil, d < today { comps.year! += 1; d = cal.date(from: comps) ?? d }
            return d
        }
        func upcoming(weekday: Int, includeToday: Bool) -> Date {
            var d = includeToday ? today : today.adding(days: 1)
            while d.weekdayNumber != weekday { d = d.adding(days: 1) }
            return d
        }

        if let c = w.take("\\b(\\d{4})-(\\d{2})-(\\d{2})\\b") {
            day = cal.date(from: DateComponents(year: Int(c[1]), month: Int(c[2]), day: Int(c[3])))
        } else if let c = w.take("\\b(\\d{1,2})/(\\d{1,2})(?:/(\\d{2,4}))?\\b") {
            var a = Int(c[1]) ?? 1, b = Int(c[2]) ?? 1
            if a > 12 { swap(&a, &b) }
            var y = Int(c[3]); if let yy = y, yy < 100 { y = 2000 + yy }
            day = yearResolved(month: a, dayNum: b, year: y)
        } else if let c = w.take("\\b(?:on\\s+)?\(Self.mo)\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?(?:,?\\s+(\\d{4}))?\\b"),
                  let m = Self.monthNumber(c[1]) {
            day = yearResolved(month: m, dayNum: Int(c[2]) ?? 1, year: Int(c[3]))
        } else if let c = w.take("\\b(?:on\\s+)?(?:the\\s+)?(\\d{1,2})(?:st|nd|rd|th)?\\s+(?:of\\s+)?\(Self.mo)(?:,?\\s+(\\d{4}))?\\b"),
                  let m = Self.monthNumber(c[2]) {
            day = yearResolved(month: m, dayNum: Int(c[1]) ?? 1, year: Int(c[3]))
        } else if let c = w.take("\\bin\\s+(\\d+|an?|one|two|three|four|five)\\s*(days?|weeks?|months?)\\b") {
            let n = Int(c[1]) ?? Int(Self.numWords[c[1].lowercased()] ?? 1)
            let u = c[2].lowercased()
            day = u.hasPrefix("d") ? today.adding(days: n) : u.hasPrefix("w") ? today.adding(days: 7 * n) : today.adding(months: n)
        } else if w.take("\\bnext\\s+week\\b") != nil {
            day = today.startOfWeek.adding(days: 7)
        } else if w.take("\\bnext\\s+month\\b") != nil {
            day = today.startOfMonth.adding(months: 1)
        } else if let c = w.take("\\b(today|tomorrow|tmrw|tonight)\\b") {
            let l = c[1].lowercased()
            day = l == "today" || l == "tonight" ? today : today.adding(days: 1)
            tonight = l == "tonight"
        } else if let c = w.take("\\b(?:on\\s+)?(?:(next|this|coming)\\s+)?(\(Self.wd))\\b"), let n = Self.weekdayNumber(c[2]) {
            let mod = c[1].lowercased()
            var d = upcoming(weekday: n, includeToday: mod == "this")
            if mod == "next", d.startOfWeek == today.startOfWeek { d = d.adding(days: 7) }
            day = d
        } else if let c = w.take("\\bon\\s+the\\s+(\\d{1,2})(?:st|nd|rd|th)\\b") {
            let n = Int(c[1]) ?? 1
            var d = today
            for _ in 0..<62 { if d.dayNumber == n { break }; d = d.adding(days: 1) }
            day = d
        }
        if forcedAllDay == false, spanDays != nil { forcedAllDay = true }

        // Location
        var tail = ""
        let trimmedWork = w.s.trimmingCharacters(in: .whitespacesAndNewlines)
        var titleSource = trimmedWork
        if let re = try? NSRegularExpression(pattern: "\\s(?:at|@)\\s+(.+?)\\s*$", options: .caseInsensitive) {
            let ns = trimmedWork as NSString
            if let m = re.firstMatch(in: trimmedWork, range: NSRange(location: 0, length: ns.length)) {
                var loc = ns.substring(with: m.range(at: 1))
                titleSource = ns.substring(to: m.range.location)
                if let r = loc.range(of: " with ", options: .caseInsensitive) {
                    tail = " " + loc[r.lowerBound...]
                    loc = String(loc[..<r.lowerBound])
                }
                p.location = loc.trimmingCharacters(in: .whitespaces)
            }
        }

        // Title cleanup
        var title = (titleSource + tail).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        title = title.replacingOccurrences(of: "^(?:(?:on|at|from|to|until|till|with|and|by|for|@|-|,)\\s+)+", with: "", options: [.regularExpression, .caseInsensitive])
        title = title.replacingOccurrences(of: "(?:\\s+(?:on|at|from|to|until|till|with|and|by|for|@|-|,))+$", with: "", options: [.regularExpression, .caseInsensitive])
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let f = title.first { title = f.uppercased() + title.dropFirst() }
        p.title = title

        // Resolve dates
        if let relativeStart {
            p.start = relativeStart; p.hasDate = true; p.hasTime = true
            p.end = relativeStart.addingTimeInterval(duration ?? defaultDuration)
            return p
        }
        if day == nil, startTime == nil, let wdn = impliedWeekday { day = upcoming(weekday: wdn, includeToday: true) }
        if tonight, startTime == nil { startTime = (19, 0) }

        let refDay = reference.startOfDay
        if let day { p.hasDate = true; p.start = day }
        if let startTime {
            p.hasTime = true
            var base = day ?? refDay
            var s = base.settingTime(hour: startTime.0, minute: startTime.1)
            if day == nil, base.isToday, s < now.addingTimeInterval(-300) { base = base.adding(days: 1); s = base.settingTime(hour: startTime.0, minute: startTime.1) }
            if day == nil { p.hasDate = base != refDay || reference.isToday == false ? true : false }
            p.start = s
            if let endTime {
                var e = s.startOfDay.settingTime(hour: endTime.0, minute: endTime.1)
                if e <= s { e = e.adding(days: 1) }
                p.end = e
            } else {
                p.end = s.addingTimeInterval(duration ?? defaultDuration)
            }
            return p
        }
        if let day {
            if forcedAllDay || (!p.isReminder && duration == nil) {
                p.isAllDay = !p.isReminder
                p.start = day
                p.end = day.adding(days: max(0, (spanDays ?? 1) - 1))
            } else if duration != nil {
                let s = day.settingTime(hour: 9, minute: 0)
                p.start = s; p.end = s.addingTimeInterval(duration!); p.hasTime = true
            } else {
                p.start = day
            }
            return p
        }
        // No date information at all.
        if forcedAllDay {
            p.isAllDay = true; p.start = refDay; p.end = refDay
        } else if !p.isReminder {
            let s = reference.isToday ? now.nextHour : refDay.settingTime(hour: 9, minute: 0)
            p.start = s; p.end = s.addingTimeInterval(duration ?? defaultDuration)
        }
        return p
    }
}
