import Foundation
import Testing

@testable import RemindCore

func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
  gregorian.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

let now = date(2026, 10, 29, 16)
let nine: @Sendable () throws -> (hour: Int, minute: Int) = { (9, 0) }

func expectError(
  _ fragment: String, sourceLocation: SourceLocation = #_sourceLocation, _ body: () throws -> Any?
) {
  let error = #expect(throws: RemindError.self, sourceLocation: sourceLocation) { _ = try body() }
  #expect(error?.message.contains(fragment) == true, "\(error?.message ?? "no error")", sourceLocation: sourceLocation)
}

func due(_ flags: [String: String]) throws -> Due? {
  try resolveDue(parseReminderInput(flags, now: now).due, defaultTime: nine, now: now)
}

func edited(_ flags: [String: String], existing: Due?, repeat existingRepeat: Repeat? = nil, alert: Alert? = nil)
  throws -> (due: Due?, alert: Alert?)
{
  try resolveEdit(
    parseReminderInput(flags, now: now), existing: existing, existingRepeat: existingRepeat, existingAlert: alert,
    defaultTime: nine, now: now)
}

@Suite struct Dates {
  @Test func days() throws {
    #expect(try parseDay("today", now: now) == date(2026, 10, 29))
    #expect(try parseDay("tomorrow", now: now) == date(2026, 10, 30))
    #expect(try parseDay("mon", now: now) == date(2026, 11, 2))
    #expect(try parseDay("thu", now: now) == date(2026, 11, 5), "same weekday means next week")
    #expect(try parseDay("Friday", now: now) == date(2026, 10, 30))
    #expect(try parseDay("2026-11-16", now: now) == date(2026, 11, 16))
  }

  @Test(arguments: ["2026-13-01", "2026-02-30", "0000-01-01", "26-1-1", "2026-1-01", "someday"])
  func badDays(_ value: String) {
    expectError("--on must be") { try parseDay(value, now: now) }
  }

  @Test func time() throws {
    #expect(try parseTime("9:05") == (9, 5))
  }

  @Test(arguments: ["+9:05", "09::00", "24:00", "9", "09:5"])
  func badTimes(_ value: String) {
    expectError("HH:MM") { try parseTime(value) }
  }
}

@Suite struct Alerts {
  @Test func parse() throws {
    #expect(try parseAlert("none") == Alert.none)
    #expect(try parseAlert("30m") == .before(1800))
    #expect(try parseAlert("1d") == .before(86400))
  }

  @Test(arguments: ["0m", "366d", "9999999d", "1.5h", "1w", "-1d", "d"])
  func badAlerts(_ value: String) {
    expectError("--alert must be") { try parseAlert(value) }
  }

  @Test func describe() {
    #expect(describeAlert(.before(7200)) == "2h")
    #expect(describeAlert(.before(5400)) == "90m")
    #expect(describeAlert(.before(.infinity)) == "custom")
    #expect(describeAlert(.before(1e300)) == "custom")
  }
}

@Suite struct Repeats {
  @Test func parse() throws {
    #expect(try parseRepeat("day") == .daily)
    #expect(try parseRepeat("weekday") == .workdays)
    #expect(try parseRepeat("year") == .yearly)
    #expect(try parseRepeat("wed,mon") == .weekly([2, 4]))
    #expect(try parseRepeat("last,10th") == .monthly([10, -1]))
    #expect(try parseRepeat("25") == .monthly([25]))
  }

  @Test func roundTrip() throws {
    #expect(try describeRepeat(parseRepeat("25th,last,10th")) == "10th,25th,last")
    #expect(try describeRepeat(parseRepeat("fri,mon")) == "mon,fri")
  }

  @Test(arguments: [
    ("31st", "use last"), ("2st", "not a day of the month"), ("01", "not a day of the month"),
    ("mon,15th", "not both"), ("mon,mon", "duplicate"), ("foo", "not a day of the month"),
    ("mon,", "empty value"), ("weekday,sat", "can't be combined"),
  ])
  func badRepeats(_ value: String, _ fragment: String) {
    expectError(fragment) { try parseRepeat(value) }
  }
}

@Suite struct DueResolution {
  @Test func add() throws {
    #expect(try due(["on": "2026-11-16", "at": "10:00"]) == .timed(date(2026, 11, 16, 10)))
    #expect(try due(["at": "23:00"]) == .timed(date(2026, 10, 29, 23)))
    #expect(try due(["at": "08:00"]) == .timed(date(2026, 10, 30, 8)), "a passed time means tomorrow")
    #expect(try due(["on": "fri"]) == .timed(date(2026, 10, 30, 9)))
    #expect(try due([:]) == nil)
    #expect(try due(["on": "today", "at": "08:00"]) == .timed(date(2026, 10, 29, 8)))
  }

  @Test func allDay() throws {
    #expect(try due(["all-day": ""]) == .allDay(date(2026, 10, 29)))
    #expect(try due(["all-day": "", "on": "2026-11-16"]) == .allDay(date(2026, 11, 16)))
  }

  @Test func repeating() throws {
    #expect(try due(["on": "2026-11-12", "every": "mon"]) == .timed(date(2026, 11, 16, 9)))
    #expect(try due(["every": "last"]) == .timed(date(2026, 10, 31, 9)))
    #expect(try due(["every": "day", "at": "08:00"]) == .timed(date(2026, 10, 30, 8)))
    #expect(try due(["every": "year", "on": "2027-03-15"]) == .timed(date(2027, 3, 15, 9)))
    #expect(try due(["every": "fri", "all-day": ""]) == .allDay(date(2026, 10, 30)))
    #expect(try due(["every": "day", "all-day": ""]) == .allDay(date(2026, 10, 29)))
  }

  @Test func errors() {
    expectError("needs --on") { try due(["every": "year"]) }
    expectError("09:00 has passed today") { try due(["on": "today"]) }
    expectError("exists every year") { try due(["on": "2028-02-29", "every": "year"]) }
  }
}

@Suite struct EditMerge {
  let timed = Due.timed(date(2027, 3, 15, 10))
  let allDay = Due.allDay(date(2027, 3, 15))

  @Test func keepsTheOtherPart() throws {
    #expect(try edited(["at": "15:00"], existing: timed).due == .timed(date(2027, 3, 15, 15)))
    #expect(try edited(["on": "2027-04-01"], existing: timed).due == .timed(date(2027, 4, 1, 10)))
    #expect(try edited(["on": "today"], existing: .timed(date(2026, 10, 1, 8))).due == .timed(date(2026, 10, 29, 8)))
  }

  @Test func switchesKind() throws {
    #expect(try edited(["all-day": ""], existing: timed).due == .allDay(date(2027, 3, 15)))
    #expect(try edited(["at": "11:00"], existing: allDay).due == .timed(date(2027, 3, 15, 11)))
    #expect(try edited(["on": "2027-04-01"], existing: allDay).due == .allDay(date(2027, 4, 1)))
  }

  @Test func alerts() throws {
    #expect(try edited(["at": "15:00"], existing: timed, alert: .before(86400)).alert == .before(86400))
    #expect(try edited(["at": "11:00"], existing: allDay, alert: Alert.none).alert == nil)
    expectError("needs a due time") { try edited(["alert": "1d", "on": "2027-04-01"], existing: allDay) }
  }

  @Test func repeating() throws {
    #expect(
      try edited(["on": "2027-03-17"], existing: timed, repeat: .weekly([2])).due == .timed(date(2027, 3, 22, 10)))
    #expect(try edited(["every": "wed"], existing: timed).due == .timed(date(2027, 3, 17, 10)))
    #expect(try edited(["on": "2027-04-01"], existing: nil).due == .timed(date(2027, 4, 1, 9)))
  }
}

@Suite struct Inputs {
  @Test func url() throws {
    #expect(try parseURL("https://example.com/a?b=1").host == "example.com")
    #expect(try parseURL("HTTPS://example.com").host == "example.com")
  }

  @Test(arguments: [
    "https://bank.com@evil.com", "javascript:alert(1)", "shortcuts://run", "naver.me/x", "https:///x", "tel:123",
  ])
  func badURLs(_ value: String) {
    expectError("--url must") { try parseURL(value) }
  }

  @Test func clear() throws {
    #expect(try parseClear("note,url") == [.note, .url])
    expectError("--clear takes") { try parseClear("foo") }
    expectError("--clear takes") { try parseClear("") }
    expectError("--clear takes") { try parseClear(",") }
  }

  @Test(arguments: [
    (["all-day": "", "at": "10:00"], "no --at"),
    (["all-day": "", "alert": "1d"], "no alarms"),
    (["clear": "note", "note": "x"], "clear and set note"),
    (["clear": "due", "on": "today"], "clear and set due"),
    (["clear": "due", "alert": "1d"], "clear and set due"),
    (["clear": "repeat", "every": "day"], "clear and set repeat"),
    (["title": ""], "empty"),
    (["title": "a\u{202E}b"], "invisible"),
    (["note": "a\u{1b}b"], "invisible"),
  ])
  func badInputs(_ flags: [String: String], _ fragment: String) {
    expectError(fragment) { try parseReminderInput(flags, now: now) }
  }

  @Test func noteKeepsNewline() throws {
    #expect(try parseReminderInput(["note": "a\nb"], now: now).note == "a\nb")
  }
}

@Suite struct Filters {
  @Test func dueWindows() {
    #expect(dueMatches(.timed(date(2026, 10, 29, 10)), .overdue, now: now))
    #expect(!dueMatches(.timed(date(2026, 10, 29, 18)), .overdue, now: now))
    #expect(!dueMatches(.allDay(date(2026, 10, 29)), .overdue, now: now))
    #expect(dueMatches(.timed(date(2026, 10, 1)), .today, now: now))
    #expect(!dueMatches(.timed(date(2026, 10, 30, 9)), .today, now: now))
    #expect(dueMatches(.timed(date(2026, 11, 5, 23)), .week, now: now))
    #expect(!dueMatches(.timed(date(2026, 11, 6, 9)), .week, now: now))
  }
}

@Suite struct Sanitize {
  @Test func removesHiddenCharacters() {
    #expect(sanitize("a\u{1b}]52;c;x\u{7}b") == "a]52;c;xb")
    #expect(sanitize("a\u{202E}b\u{200B}c") == "abc")
    #expect(sanitize("a\u{E0041}b") == "ab")
    #expect(sanitize("a\u{2028}b\u{2029}c\u{3164}d\u{E0100}e") == "abcde")
  }

  @Test func keepsVisibleText() {
    #expect(sanitize("👨\u{200D}👩") == "👨\u{200D}👩")
    #expect(sanitize("\u{2764}\u{FE0F}") == "\u{2764}\u{FE0F}")
    #expect(sanitize("a\nb\rc") == "a b c")
    #expect(sanitize("a\nb\u{1b}", multiline: true) == "a\nb")
  }
}

@Suite struct Arguments {
  let values: Set<String> = ["note"]
  let switches: Set<String> = ["json"]

  func parse(_ args: [String]) throws -> Args {
    try parseArgs(args, command: "add", values: values, switches: switches)
  }

  @Test func parses() throws {
    #expect(try parse(["--", "--x"]).positional == ["--x"])
    #expect(try parse(["--help"]).help)
    #expect(try parse(["--note", "--json"]).flags["note"] == "--json")
  }

  @Test func errors() {
    expectError("Repeated") { try parse(["--json", "--json"]) }
    expectError("Unknown option for add") { try parse(["--at"]) }
    expectError("Missing value") { try parse(["--note"]) }
  }
}

@Suite struct Output {
  @Test func isoMatchesFoundationFormatter() {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = .current
    let value = date(2027, 3, 15, 10)
    #expect(format(.timed(value), json: true) == formatter.string(from: value))
    #expect(format(.allDay(value), json: true) == "2027-03-15")
  }
}
