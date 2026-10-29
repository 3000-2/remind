import Foundation

var failures = 0

func expect(_ name: String, _ condition: Bool) {
  if !condition {
    failures += 1
    print("FAIL: \(name)")
  }
}

func expectError(_ name: String, _ fragment: String, _ body: () throws -> Any?) {
  do {
    let value = try body()
    failures += 1
    print("FAIL: \(name) returned \(String(describing: value))")
  } catch let error as RemindError {
    expect("\(name) message: \(error.message)", error.message.contains(fragment))
  } catch {
    expect("\(name) threw \(error)", false)
  }
}

func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
  gregorian.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

let now = date(2026, 10, 29, 16)
let nine: () throws -> (hour: Int, minute: Int) = { (9, 0) }

func due(_ flags: [String: String]) throws -> Due? {
  try resolveDue(parseReminderInput(flags, now: now).due, defaultTime: nine, now: now)
}

expect("today", try parseDay("today", now: now) == date(2026, 10, 29))
expect("tomorrow", try parseDay("tomorrow", now: now) == date(2026, 10, 30))
expect("mon", try parseDay("mon", now: now) == date(2026, 11, 2))
expect("same weekday is next week", try parseDay("thu", now: now) == date(2026, 11, 5))
expect("full weekday name", try parseDay("Friday", now: now) == date(2026, 10, 30))
expect("iso day", try parseDay("2026-11-16", now: now) == date(2026, 11, 16))
for bad in ["2026-13-01", "2026-02-30", "0000-01-01", "26-1-1", "2026-1-01", "someday"] {
  expectError("day \(bad)", "--on must be") { try parseDay(bad, now: now) }
}

expect("time", try parseTime("9:05") == (9, 5))
for bad in ["+9:05", "09::00", "24:00", "9", "09:5"] {
  expectError("time \(bad)", "HH:MM") { try parseTime(bad) }
}

expect("alert none", try parseAlert("none") == Alert.none)
expect("alert 30m", try parseAlert("30m") == .before(1800))
expect("alert 1d", try parseAlert("1d") == .before(86400))
for bad in ["0m", "366d", "9999999d", "1.5h", "1w", "-1d", "d"] {
  expectError("alert \(bad)", "--alert must be") { try parseAlert(bad) }
}
expect("describe 2h", describeAlert(.before(7200)) == "2h")
expect("describe 90m", describeAlert(.before(5400)) == "90m")

expect("every day", try parseRepeat("day") == .daily)
expect("every weekday", try parseRepeat("weekday") == .workdays)
expect("every year", try parseRepeat("year") == .yearly)
expect("every wed,mon", try parseRepeat("wed,mon") == .weekly([2, 4]))
expect("every last,10th", try parseRepeat("last,10th") == .monthly([10, -1]))
expect("every 25", try parseRepeat("25") == .monthly([25]))
expect("round trip", try describeRepeat(parseRepeat("25th,last,10th")) == "10th,25th,last")
expect("round trip weekdays", try describeRepeat(parseRepeat("fri,mon")) == "mon,fri")
expectError("every 31st", "use last") { try parseRepeat("31st") }
expectError("every 2st", "not a day of the month") { try parseRepeat("2st") }
expectError("every 01", "not a day of the month") { try parseRepeat("01") }
expectError("every mixed", "not both") { try parseRepeat("mon,15th") }
expectError("every duplicate", "duplicate") { try parseRepeat("mon,mon") }
expectError("every foo", "not a day of the month") { try parseRepeat("foo") }

expect("on + at", try due(["on": "2026-11-16", "at": "10:00"]) == .timed(date(2026, 11, 16, 10)))
expect("at later today", try due(["at": "23:00"]) == .timed(date(2026, 10, 29, 23)))
expect("at passed means tomorrow", try due(["at": "08:00"]) == .timed(date(2026, 10, 30, 8)))
expect("on uses default time", try due(["on": "fri"]) == .timed(date(2026, 10, 30, 9)))
expect("no date", try due([:]) == nil)
expect("all-day today", try due(["all-day": ""]) == .allDay(date(2026, 10, 29)))
expect("all-day on", try due(["all-day": "", "on": "2026-11-16"]) == .allDay(date(2026, 11, 16)))
expect("every mon from thu", try due(["on": "2026-11-12", "every": "mon"]) == .timed(date(2026, 11, 16, 9)))
expect("every last", try due(["every": "last"]) == .timed(date(2026, 10, 31, 9)))
expect("every day passed time", try due(["every": "day", "at": "08:00"]) == .timed(date(2026, 10, 30, 8)))
expect("every year", try due(["every": "year", "on": "2027-03-15"]) == .timed(date(2027, 3, 15, 9)))
expect("all-day every fri", try due(["every": "fri", "all-day": ""]) == .allDay(date(2026, 10, 30)))
expect("all-day every day", try due(["every": "day", "all-day": ""]) == .allDay(date(2026, 10, 29)))
expectError("every year without on", "needs --on") { try due(["every": "year"]) }

expect("url https", try parseURL("https://example.com/a?b=1").host == "example.com")
expect("url uppercase scheme", try parseURL("HTTPS://example.com").host == "example.com")
for bad in ["https://bank.com@evil.com", "javascript:alert(1)", "shortcuts://run", "naver.me/x", "https:///x", "tel:123"] {
  expectError("url \(bad)", "--url must") { try parseURL(bad) }
}

expect("clear", try parseClear("note,url") == [.note, .url])
expectError("clear foo", "--clear takes") { try parseClear("foo") }
expectError("all-day + at", "no --at") { try parseReminderInput(["all-day": "", "at": "10:00"], now: now) }
expectError("all-day + alert", "no alarms") { try parseReminderInput(["all-day": "", "alert": "1d"], now: now) }
expectError("clear + set note", "clear and set note") { try parseReminderInput(["clear": "note", "note": "x"], now: now) }
expectError("clear due + on", "clear and set due") { try parseReminderInput(["clear": "due", "on": "today"], now: now) }
expectError("clear due + alert", "clear and set due") { try parseReminderInput(["clear": "due", "alert": "1d"], now: now) }
expectError("clear repeat + every", "clear and set repeat") {
  try parseReminderInput(["clear": "repeat", "every": "day"], now: now)
}
expectError("empty title", "empty") { try parseReminderInput(["title": ""], now: now) }

expect("overdue timed", dueMatches(.timed(date(2026, 10, 29, 10)), .overdue, now: now))
expect("not overdue later today", !dueMatches(.timed(date(2026, 10, 29, 18)), .overdue, now: now))
expect("all-day today not overdue", !dueMatches(.allDay(date(2026, 10, 29)), .overdue, now: now))
expect("today includes overdue", dueMatches(.timed(date(2026, 10, 1)), .today, now: now))
expect("today excludes tomorrow", !dueMatches(.timed(date(2026, 10, 30, 9)), .today, now: now))
expect("week includes day 7", dueMatches(.timed(date(2026, 11, 5, 23)), .week, now: now))
expect("week excludes day 8", !dueMatches(.timed(date(2026, 11, 6, 9)), .week, now: now))

expect("sanitize escape", sanitize("a\u{1b}]52;c;x\u{7}b") == "a]52;c;xb")
expect("sanitize bidi and zero width", sanitize("a\u{202E}b\u{200B}c") == "abc")
expect("sanitize tag characters", sanitize("a\u{E0041}b") == "ab")
expect("sanitize keeps zwj", sanitize("👨\u{200D}👩") == "👨\u{200D}👩")
expect("sanitize newline", sanitize("a\nb\rc") == "a b c")
expect("sanitize multiline", sanitize("a\nb\u{1b}", multiline: true) == "a\nb")

let values: Set<String> = ["note"]
let switches: Set<String> = ["json"]
expect("args --", try parseArgs(["--", "--x"], command: "add", values: values, switches: switches).positional == ["--x"])
expect("args help", try parseArgs(["--help"], command: "add", values: values, switches: switches).help)
expect("args value", try parseArgs(["--note", "--json"], command: "add", values: values, switches: switches).flags["note"] == "--json")
expectError("args repeated", "Repeated") { try parseArgs(["--json", "--json"], command: "add", values: values, switches: switches) }
expectError("args unknown", "Unknown option for add") { try parseArgs(["--at"], command: "add", values: values, switches: switches) }
expectError("args missing", "Missing value") { try parseArgs(["--note"], command: "add", values: values, switches: switches) }

func edited(_ flags: [String: String], existing: Due?, repeat existingRepeat: Repeat? = nil, alert: Alert? = nil)
  throws -> (due: Due?, alert: Alert?)
{
  try resolveEdit(
    parseReminderInput(flags, now: now), existing: existing, existingRepeat: existingRepeat, existingAlert: alert,
    defaultTime: nine, now: now)
}

let timed = Due.timed(date(2027, 3, 15, 10))
let allDay = Due.allDay(date(2027, 3, 15))
expect("edit --at keeps day", try edited(["at": "15:00"], existing: timed).due == .timed(date(2027, 3, 15, 15)))
expect("edit --on keeps time", try edited(["on": "2027-04-01"], existing: timed).due == .timed(date(2027, 4, 1, 10)))
expect("edit timed to all-day", try edited(["all-day": ""], existing: timed).due == .allDay(date(2027, 3, 15)))
expect("edit all-day + --at", try edited(["at": "11:00"], existing: allDay).due == .timed(date(2027, 3, 15, 11)))
expect("edit all-day + --on stays all-day", try edited(["on": "2027-04-01"], existing: allDay).due == .allDay(date(2027, 4, 1)))
expect("edit keeps alert", try edited(["at": "15:00"], existing: timed, alert: .before(86400)).alert == .before(86400))
expect("all-day to timed gets default alarm", try edited(["at": "11:00"], existing: allDay, alert: Alert.none).alert == nil)
expect("edit repeating --on snaps", try edited(["on": "2027-03-17"], existing: timed, repeat: .weekly([2])).due == .timed(date(2027, 3, 22, 10)))
expect("edit --every from existing", try edited(["every": "wed"], existing: timed).due == .timed(date(2027, 3, 17, 10)))
expect("edit no due + --on uses default", try edited(["on": "2027-04-01"], existing: nil).due == .timed(date(2027, 4, 1, 9)))
expectError("edit --alert on all-day", "needs a due time") { try edited(["alert": "1d", "on": "2027-04-01"], existing: allDay) }
expect("edit past existing time kept", try edited(["on": "today"], existing: .timed(date(2026, 10, 1, 8))).due == .timed(date(2026, 10, 29, 8)))

expectError("on today past default", "09:00 has passed today") { try due(["on": "today"]) }
expect("on today with --at past is allowed", try due(["on": "today", "at": "08:00"]) == .timed(date(2026, 10, 29, 8)))
expectError("yearly feb 29", "exists every year") { try due(["on": "2028-02-29", "every": "year"]) }
expectError("every empty", "empty value") { try parseRepeat("mon,") }
expectError("every word in list", "can't be combined") { try parseRepeat("weekday,sat") }
expectError("clear empty", "--clear takes") { try parseClear("") }
expectError("clear comma", "--clear takes") { try parseClear(",") }
expect("alert custom", describeAlert(.before(.infinity)) == "custom" && describeAlert(.before(1e300)) == "custom")
expect("sanitize separators", sanitize("a\u{2028}b\u{2029}c\u{3164}d\u{E0100}e") == "abcde")
expect("sanitize keeps emoji presentation", sanitize("\u{2764}\u{FE0F}") == "\u{2764}\u{FE0F}")
expectError("writable title", "invisible") { try parseReminderInput(["title": "a\u{202E}b"], now: now) }
expectError("writable note", "invisible") { try parseReminderInput(["note": "a\u{1b}b"], now: now) }
expect("note keeps newline", try parseReminderInput(["note": "a\nb"], now: now).note == "a\nb")

print(failures == 0 ? "All tests passed" : "\(failures) failed")
exit(failures == 0 ? 0 : 1)
