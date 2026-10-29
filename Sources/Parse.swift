import Foundation

struct RemindError: Error {
  let message: String
  let showUsage: Bool
  init(_ message: String, showUsage: Bool = false) {
    self.message = message
    self.showUsage = showUsage
  }
}

let gregorian: Calendar = {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = .current
  return calendar
}()

let weekdayNames = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
let weekdayFullNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

func weekdayNumber(_ value: String) -> Int? {
  let key = value.lowercased()
  let index = weekdayNames.firstIndex(of: key) ?? weekdayFullNames.firstIndex(of: key)
  return index.map { $0 + 1 }
}

func isDigits<S: StringProtocol>(_ text: S) -> Bool {
  !text.isEmpty && text.allSatisfy { $0.isASCII && $0.isNumber }
}

struct Args {
  var positional: [String] = []
  var flags: [String: String] = [:]
  var help = false
}

func parseArgs(_ args: [String], command: String, values: Set<String>, switches: Set<String>) throws -> Args {
  var result = Args()
  var index = 0
  while index < args.count {
    let arg = args[index]
    index += 1
    if arg == "--" {
      result.positional += args[index...]
      break
    }
    if arg == "--help" {
      result.help = true
      continue
    }
    guard arg.hasPrefix("--") else {
      result.positional.append(arg)
      continue
    }
    let key = String(arg.dropFirst(2))
    guard values.contains(key) || switches.contains(key) else { throw RemindError("Unknown option for \(command): \(arg)") }
    guard result.flags[key] == nil else { throw RemindError("Repeated option: \(arg)") }
    if switches.contains(key) {
      result.flags[key] = ""
    } else {
      guard index < args.count else { throw RemindError("Missing value for \(arg)") }
      result.flags[key] = args[index]
      index += 1
    }
  }
  return result
}

func parseTime(_ value: String, source: String = "--at") throws -> (hour: Int, minute: Int) {
  let parts = value.split(separator: ":", omittingEmptySubsequences: false)
  guard parts.count == 2, (1...2).contains(parts[0].count), parts[1].count == 2, parts.allSatisfy(isDigits),
    let hour = Int(parts[0]), let minute = Int(parts[1]), (0..<24).contains(hour), (0..<60).contains(minute)
  else { throw RemindError("\(source) must be HH:MM") }
  return (hour, minute)
}

func parseDay(_ value: String, now: Date) throws -> Date {
  let today = gregorian.startOfDay(for: now)
  switch value.lowercased() {
  case "today": return today
  case "tomorrow": return gregorian.date(byAdding: .day, value: 1, to: today)!
  default: break
  }
  if let weekday = weekdayNumber(value) {
    return (1...7).lazy.map { gregorian.date(byAdding: .day, value: $0, to: today)! }
      .first { gregorian.component(.weekday, from: $0) == weekday }!
  }
  let parts = value.split(separator: "-", omittingEmptySubsequences: false)
  let message = "--on must be YYYY-MM-DD, today, tomorrow or a weekday"
  guard parts.count == 3, parts.map(\.count) == [4, 2, 2], parts.allSatisfy(isDigits) else { throw RemindError(message) }
  let fields = DateComponents(year: Int(parts[0]), month: Int(parts[1]), day: Int(parts[2]), hour: 12)
  guard let year = fields.year, year >= 1970, let noon = gregorian.date(from: fields),
    gregorian.component(.month, from: noon) == fields.month, gregorian.component(.day, from: noon) == fields.day
  else { throw RemindError(message) }
  return gregorian.startOfDay(for: noon)
}

enum Alert: Equatable {
  case none
  case before(TimeInterval)
}

func parseAlert(_ value: String) throws -> Alert {
  if value == "none" { return .none }
  let message = "--alert must be none or a duration from 1m to 365d (30m, 2h, 1d)"
  let number = value.dropLast()
  guard let unit = value.last, number.count <= 6, isDigits(number), let amount = Double(number) else {
    throw RemindError(message)
  }
  let seconds: TimeInterval
  switch unit {
  case "m": seconds = amount * 60
  case "h": seconds = amount * 3600
  case "d": seconds = amount * 86400
  default: throw RemindError(message)
  }
  guard (60...365 * 86400).contains(seconds) else { throw RemindError(message) }
  return .before(seconds)
}

func describeAlert(_ alert: Alert) -> String {
  guard case .before(let seconds) = alert else { return "none" }
  guard seconds.isFinite, (60...365 * 86400).contains(seconds) else { return "custom" }
  let minutes = Int((seconds / 60).rounded())
  if minutes % 1440 == 0 { return "\(minutes / 1440)d" }
  if minutes % 60 == 0 { return "\(minutes / 60)h" }
  return "\(minutes)m"
}

enum Repeat: Equatable {
  case daily
  case workdays
  case yearly
  case weekly([Int])
  case monthly([Int])
}

let lastDayOfMonth = -1

func ordinal(_ day: Int) -> String {
  if day == lastDayOfMonth { return "last" }
  if (11...13).contains(day % 100) { return "\(day)th" }
  return "\(day)" + ([1: "st", 2: "nd", 3: "rd"][day % 10] ?? "th")
}

func parseMonthDay(_ value: String) throws -> Int {
  if value == "last" { return lastDayOfMonth }
  let digits = value.prefix { $0.isASCII && $0.isNumber }
  let suffix = String(value.dropFirst(digits.count))
  guard (1...2).contains(digits.count), digits.first != "0", let day = Int(digits), (1...31).contains(day),
    suffix.isEmpty || suffix == String(ordinal(day).dropFirst(digits.count))
  else { throw RemindError("--every: \(value) is not a day of the month (1st..28th or last)") }
  guard day <= 28 else { throw RemindError("--every: \(value) skips shorter months; use last") }
  return day
}

func sortedMonthDays(_ days: [Int]) -> [Int] {
  days.sorted { ($0 == lastDayOfMonth ? 32 : $0) < ($1 == lastDayOfMonth ? 32 : $1) }
}

func parseRepeat(_ value: String) throws -> Repeat {
  switch value {
  case "day": return .daily
  case "weekday": return .workdays
  case "year": return .yearly
  default: break
  }
  let parts = value.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
  if parts.contains("") { throw RemindError("--every: empty value in \(value)") }
  if parts.count > 1, let word = parts.first(where: { ["day", "weekday", "year"].contains($0) }) {
    throw RemindError("--every: \(word) can't be combined with other values")
  }
  let weekdays = parts.compactMap(weekdayNumber)
  let days: [Int]
  if weekdays.count == parts.count {
    days = weekdays
  } else if weekdays.isEmpty {
    days = try parts.map(parseMonthDay)
  } else {
    throw RemindError("--every: use weekdays (mon,wed) or days of the month (10th,25th), not both")
  }
  guard Set(days).count == days.count else { throw RemindError("--every: duplicate value in \(value)") }
  return weekdays.isEmpty ? .monthly(sortedMonthDays(days)) : .weekly(days.sorted())
}

func describeRepeat(_ recurrence: Repeat) -> String {
  switch recurrence {
  case .daily: return "day"
  case .workdays: return "weekday"
  case .yearly: return "year"
  case .weekly(let days): return days.map { weekdayNames[$0 - 1] }.joined(separator: ",")
  case .monthly(let days): return days.map(ordinal).joined(separator: ",")
  }
}

func matches(_ recurrence: Repeat, _ day: Date, anchor: Date?) -> Bool {
  let weekday = gregorian.component(.weekday, from: day)
  let dayOfMonth = gregorian.component(.day, from: day)
  switch recurrence {
  case .daily: return true
  case .workdays: return (2...6).contains(weekday)
  case .weekly(let days): return days.contains(weekday)
  case .monthly(let days):
    let lastDay = gregorian.range(of: .day, in: .month, for: day)!.count
    return days.contains(dayOfMonth) || (days.contains(lastDayOfMonth) && dayOfMonth == lastDay)
  case .yearly:
    guard let anchor else { return false }
    return gregorian.dateComponents([.month, .day], from: day) == gregorian.dateComponents([.month, .day], from: anchor)
  }
}

enum Due: Equatable {
  case timed(Date)
  case allDay(Date)

  var date: Date {
    switch self {
    case .timed(let date), .allDay(let date): return date
    }
  }
}

struct DueRequest {
  var day: Date?
  var time: (hour: Int, minute: Int)?
  var allDay = false
  var recurrence: Repeat?
}

func resolveDue(_ request: DueRequest, defaultTime: () throws -> (hour: Int, minute: Int), now: Date) throws -> Due? {
  let today = gregorian.startOfDay(for: now)
  if request.recurrence == .yearly && request.day == nil { throw RemindError("--every year needs --on") }
  if let recurrence = request.recurrence {
    let time = request.allDay ? nil : try request.time ?? defaultTime()
    return try firstOccurrence(recurrence, anchor: request.day, from: max(request.day ?? today, today), time: time, now: now)
  }
  if request.allDay { return .allDay(request.day ?? today) }
  guard request.day != nil || request.time != nil else { return nil }
  let (hour, minute) = try request.time ?? defaultTime()
  if let day = request.day {
    let due = gregorian.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    if request.time == nil && day == today && due <= now {
      throw RemindError(String(format: "%02d:%02d has passed today; pass --at or --all-day", hour, minute))
    }
    return .timed(due)
  }
  let todayAt = gregorian.date(bySettingHour: hour, minute: minute, second: 0, of: now)!
  return .timed(todayAt > now ? todayAt : gregorian.date(byAdding: .day, value: 1, to: todayAt)!)
}

func firstOccurrence(_ recurrence: Repeat, anchor: Date?, from start: Date, time: (hour: Int, minute: Int)?, now: Date)
  throws -> Due
{
  for offset in 0...366 {
    let day = gregorian.date(byAdding: .day, value: offset, to: start)!
    guard matches(recurrence, day, anchor: anchor) else { continue }
    guard let time else { return .allDay(day) }
    let candidate = gregorian.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day)!
    if candidate > now { return .timed(candidate) }
  }
  throw RemindError("Could not find the first occurrence")
}

func parseURL(_ value: String) throws -> URL {
  guard value.count <= 2048, let url = URL(string: value), let scheme = url.scheme?.lowercased(),
    ["http", "https"].contains(scheme), let host = url.host, !host.isEmpty, url.user == nil, url.password == nil
  else { throw RemindError("--url must start with https:// or http://") }
  return url
}

let priorities = ["high": 1, "medium": 5, "low": 9]

func parsePriority(_ value: String) throws -> Int {
  guard let level = priorities[value] else { throw RemindError("--priority must be high, medium or low") }
  return level
}

func describePriority(_ level: Int) -> String? {
  switch level {
  case 1...4: return "high"
  case 5: return "medium"
  case 6...9: return "low"
  default: return nil
  }
}

enum Field: String, CaseIterable {
  case note, url, priority, due, `repeat`
}

func parseClear(_ value: String) throws -> Set<Field> {
  let fields = try value.split(separator: ",", omittingEmptySubsequences: false).map { name in
    guard let field = Field(rawValue: String(name)) else {
      throw RemindError("--clear takes \(Field.allCases.map(\.rawValue).joined(separator: ","))")
    }
    return field
  }
  return Set(fields)
}

enum DueFilter: String {
  case today, week, overdue
}

func parseDueFilter(_ value: String) throws -> DueFilter {
  guard let filter = DueFilter(rawValue: value) else { throw RemindError("--due must be today, week or overdue") }
  return filter
}

func dueMatches(_ due: Due, _ filter: DueFilter, now: Date) -> Bool {
  let today = gregorian.startOfDay(for: now)
  switch (filter, due) {
  case (.overdue, .timed(let date)): return date < now
  case (.overdue, .allDay(let day)): return day < today
  case (.today, _): return due.date < gregorian.date(byAdding: .day, value: 1, to: today)!
  case (.week, _): return due.date < gregorian.date(byAdding: .day, value: 8, to: today)!
  }
}

let hiddenCategories: Set<Unicode.GeneralCategory> = [
  .control, .format, .lineSeparator, .paragraphSeparator, .privateUse, .unassigned,
]

func isHidden(_ scalar: Unicode.Scalar) -> Bool {
  hiddenCategories.contains(scalar.properties.generalCategory)
    || (0xE0100...0xE01EF).contains(scalar.value)
    || [0x115F, 0x1160, 0x3164].contains(scalar.value)
}

func checkWritable(_ text: String, _ name: String, multiline: Bool = false) throws {
  if sanitize(text, multiline: multiline) != text { throw RemindError("\(name) contains control or invisible characters") }
}

func sanitize(_ text: String, multiline: Bool = false) -> String {
  var scalars = String.UnicodeScalarView()
  for scalar in text.unicodeScalars {
    if multiline && (scalar == "\n" || scalar == "\t") {
      scalars.append(scalar)
    } else if scalar == "\n" || scalar == "\r" || scalar == "\t" {
      scalars.append(" ")
    } else if scalar == "\u{200D}" {
      scalars.append(scalar)
    } else if !isHidden(scalar) {
      scalars.append(scalar)
    }
  }
  return String(scalars)
}

struct ReminderInput {
  var title: String?
  var list: String?
  var due = DueRequest()
  var alert: Alert?
  var note: String?
  var url: URL?
  var priority: Int?
  var clear: Set<Field> = []
  var force = false
  var json = false

  var touchesDue: Bool { due.day != nil || due.time != nil || due.allDay || due.recurrence != nil }
}

func parseReminderInput(_ flags: [String: String], now: Date) throws -> ReminderInput {
  var input = ReminderInput()
  input.title = flags["title"]
  input.list = flags["list"]
  input.due.day = try flags["on"].map { try parseDay($0, now: now) }
  input.due.time = try flags["at"].map { try parseTime($0) }
  input.due.allDay = flags["all-day"] != nil
  input.due.recurrence = try flags["every"].map(parseRepeat)
  input.alert = try flags["alert"].map(parseAlert)
  input.note = flags["note"]
  input.url = try flags["url"].map(parseURL)
  input.priority = try flags["priority"].map(parsePriority)
  input.clear = try flags["clear"].map(parseClear) ?? []
  input.force = flags["force"] != nil
  input.json = flags["json"] != nil
  if input.title?.isEmpty == true { throw RemindError("--title can't be empty") }
  try input.title.map { try checkWritable($0, "--title") }
  try input.note.map { try checkWritable($0, "--note", multiline: true) }
  if input.due.recurrence == .yearly, let day = input.due.day,
    gregorian.dateComponents([.month, .day], from: day) == DateComponents(month: 2, day: 29)
  {
    throw RemindError("--every year: pick a date that exists every year")
  }
  if input.due.allDay && input.due.time != nil { throw RemindError("--all-day takes no --at") }
  if input.due.allDay && input.alert != nil { throw RemindError("--all-day reminders have no alarms; drop --alert") }
  let setting: [Field: Bool] = [
    .note: input.note != nil, .url: input.url != nil, .priority: input.priority != nil,
    .due: input.touchesDue || input.alert != nil, .repeat: input.due.recurrence != nil,
  ]
  if let conflict = Field.allCases.first(where: { input.clear.contains($0) && setting[$0] == true }) {
    throw RemindError("Can't clear and set \(conflict.rawValue) in one edit")
  }
  return input
}

func resolveEdit(
  _ input: ReminderInput, existing: Due?, existingRepeat: Repeat?, existingAlert: Alert?,
  defaultTime: () throws -> (hour: Int, minute: Int), now: Date
) throws -> (due: Due?, alert: Alert?) {
  var request = input.due
  if request.recurrence == nil { request.recurrence = existingRepeat }
  if case .allDay = existing, request.time == nil { request.allDay = true }
  request.day = request.day ?? existing.map { gregorian.startOfDay(for: $0.date) }
  if !request.allDay, request.time == nil, case .timed(let date) = existing {
    request.time = (gregorian.component(.hour, from: date), gregorian.component(.minute, from: date))
  }
  let due = try resolveDue(request, defaultTime: defaultTime, now: now)
  let carried: Alert? = { if case .timed = existing { return existingAlert } else { return nil } }()
  let alert = input.alert ?? carried
  if case .before = alert, case .allDay = due { throw RemindError("--alert needs a due time") }
  return (due, alert)
}
