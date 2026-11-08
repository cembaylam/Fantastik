import XCTest
@testable import Fantastik

final class ParserTests: XCTestCase {
    // Sunday 8 Nov 2026, 10:00
    let now = appCalendar().date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 10))!

    func parse(_ s: String) -> ParsedEntry { EntryParser(now: now, reference: now).parse(s) }
    func hm(_ d: Date?) -> String { d.map { "\(appCalendar().component(.hour, from: $0)):\(String(format: "%02d", appCalendar().component(.minute, from: $0)))" } ?? "nil" }

    func testLunchTomorrowNoon() {
        let p = parse("Lunch with Sam tomorrow at noon at Café Lomi")
        XCTAssertEqual(p.title, "Lunch with Sam")
        XCTAssertEqual(p.location, "Café Lomi")
        XCTAssertEqual(hm(p.start), "12:00")
        XCTAssertEqual(hm(p.end), "13:00")
        XCTAssertTrue(p.start!.isSameDay(now.adding(days: 1)))
    }

    func testRangeAndWeekday() {
        let p = parse("Dentist friday 3-4pm")
        XCTAssertEqual(p.title, "Dentist")
        XCTAssertEqual(hm(p.start), "15:00")
        XCTAssertEqual(hm(p.end), "16:00")
        XCTAssertEqual(p.start!.weekdayNumber, 6)
    }

    func testDurationCalendarAlert() {
        let p = parse("Planning meeting Dec 5 at 2pm for 90 minutes /Work alert 15 minutes before")
        XCTAssertEqual(p.title, "Planning meeting")
        XCTAssertEqual(hm(p.start), "14:00")
        XCTAssertEqual(hm(p.end), "15:30")
        XCTAssertEqual(p.calendarHint, "Work")
        XCTAssertEqual(p.alertOffsets, [900])
        XCTAssertEqual(appCalendar().component(.month, from: p.start!), 12)
    }

    func testRecurrence() {
        let p = parse("Standup every weekday at 9:30am")
        XCTAssertEqual(p.title, "Standup")
        XCTAssertEqual(p.repeatSpec?.weekdays, [2, 3, 4, 5, 6])
        XCTAssertEqual(hm(p.start), "9:30")
        let q = parse("Gym every Monday and Wednesday at 6pm")
        XCTAssertEqual(q.repeatSpec?.weekdays, [2, 4])
    }

    func testAllDayAndReminder() {
        let p = parse("Mom's birthday on 14 Nov")
        XCTAssertTrue(p.isAllDay)
        XCTAssertEqual(p.title, "Mom's birthday")
        let r = parse("Remind me to call the bank tomorrow at 4pm")
        XCTAssertTrue(r.isReminder)
        XCTAssertEqual(r.title, "Call the bank")
        XCTAssertEqual(hm(r.start), "16:00")
    }

    func testRelative() {
        let p = parse("Tea in 2 hours")
        XCTAssertEqual(hm(p.start), "12:00")
        XCTAssertEqual(p.title, "Tea")
    }
}
