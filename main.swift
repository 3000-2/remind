import EventKit
import Foundation

let store = EKEventStore()

struct Config: Decodable {
  var aliases: [String: String] = [:]
  var defaultTime = "09:00"
  var listDefaultTimes: [String: String] = [:]

  enum CodingKeys: String, CodingKey { case aliases, defaultTime, listDefaultTimes }

  init() {}

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    aliases = try container.decodeIfPresent([String: String].self, forKey: .aliases) ?? [:]
    defaultTime = try container.decodeIfPresent(String.self, forKey: .defaultTime) ?? "09:00"
    listDefaultTimes = try container.decodeIfPresent([String: String].self, forKey: .listDefaultTimes) ?? [:]
  }
}

let configPath: String = {
  let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].flatMap { $0.hasPrefix("/") ? $0 : nil }
  return (xdg ?? NSHomeDirectory() + "/.config") + "/remind/config.json"
}()

enum Settings {
  // static let is lazy, so `remind help` still works with a broken config.
  static let config: Config = {
    guard FileManager.default.fileExists(atPath: configPath) else { return Config() }
    guard let data = FileManager.default.contents(atPath: configPath) else { fail("Cannot read config: \(configPath)") }
    do { return try JSONDecoder().decode(Config.self, from: data) } catch { fail("Invalid config \(configPath): \(error)") }
  }()
}

let gregorian: Calendar = {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = .current
  return calendar
}()

let weekdays = ["sun": 1, "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7]
enum Command: String { case add, list, lists, done, delete, move }
let booleanFlags: Set<String> = ["json", "done", "force"]
let knownFlags: Set<String> = booleanFlags.union([
  "list", "on", "next", "at", "every", "alert-before", "note", "url", "priority",
])
let usage = """
remind add "title" [--list name] [--force] [--on YYYY-MM-DD|today|tomorrow] [--next mon..sun] [--at HH:MM]
                   [--every day|weekday|mon..sun|1st..31st] [--alert-before 30m|2h|1d]
                   [--note text] [--url url] [--priority high|medium|low] [--json]
remind list [--list name] [--done] [--json]
remind lists [--json]
remind done <id>...
remind delete <id>...
remind move <id> --list name [--json]
remind help
"""

let help = """
\(usage)

A date without --at uses the default time (09:00 unless configured).
--at without a date means today, or tomorrow if that time has passed.
--every starts at the first matching time after both --on/--next and now.
Put -- before a title that starts with --.
Config (optional): \(configPath)
  {"aliases": {"w": "Work"}, "defaultTime": "09:00", "listDefaultTimes": {"Work": "10:00"}}
"""

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(1)
}

func showHelp() -> Never {
  print(help)
  exit(0)
}

func isDigits(_ text: Substring) -> Bool {
  !text.isEmpty && text.allSatisfy { $0.isASCII && $0.isNumber }
}

func requestAccess() {
  let semaphore = DispatchSemaphore(value: 0)
  var granted = false
  store.requestFullAccessToReminders { ok, _ in
    granted = ok
    semaphore.signal()
  }
  semaphore.wait()
  if !granted { fail("No access to Reminders (System Settings > Privacy & Security > Reminders)") }
}

func parseFlags(_ args: [String]) -> (positional: [String], flags: [String: String]) {
  var positional: [String] = []
  var flags: [String: String] = [:]
  var index = 0
  while index < args.count {
    let arg = args[index]
    if arg == "--" {
      positional += args[(index + 1)...]
      break
    }
    if arg == "--help" { showHelp() }
    if arg.hasPrefix("--") {
      let key = String(arg.dropFirst(2))
      if !knownFlags.contains(key) { fail("Unknown option: \(arg)\n\(usage)") }
      if booleanFlags.contains(key) {
        flags[key] = "true"
      } else {
        guard index + 1 < args.count else { fail("Missing value for --\(key)") }
        flags[key] = args[index + 1]
        index += 1
      }
    } else {
      positional.append(arg)
    }
    index += 1
  }
  return (positional, flags)
}

func calendar(named raw: String?) -> EKCalendar {
  guard let raw else {
    guard let fallback = store.defaultCalendarForNewReminders() else { fail("No default list") }
    return fallback
  }
  let name = Settings.config.aliases[raw] ?? raw
  let matches = store.calendars(for: .reminder).filter { $0.title == name }
  guard let found = matches.first else { fail("List not found: \(name)") }
  if matches.count > 1 { fail("Ambiguous list: \(matches.count) lists are named \(name)") }
  return found
}

func parseTime(_ value: String, source: String = "--at") -> (Int, Int) {
  let parts = value.split(separator: ":", omittingEmptySubsequences: false)
  guard parts.count == 2, (1...2).contains(parts[0].count), parts[1].count == 2, parts.allSatisfy(isDigits),
    let hour = Int(parts[0]), let minute = Int(parts[1]), (0..<24).contains(hour), (0..<60).contains(minute)
  else { fail("\(source) must be HH:MM") }
  return (hour, minute)
}

func defaultTime(for list: EKCalendar) -> (Int, Int) {
  let config = Settings.config
  let aliasTime = config.listDefaultTimes.keys.sorted().first { config.aliases[$0] == list.title }
    .flatMap { config.listDefaultTimes[$0] }
  let value = config.listDefaultTimes[list.title] ?? aliasTime ?? config.defaultTime
  return parseTime(value, source: "Default time in \(configPath)")
}

func parseOffset(_ value: String) -> TimeInterval {
  let message = "--alert-before format: 30m|2h|1d"
  let number = value.dropLast()
  guard let unit = value.last, number.filter({ $0 == "." }).count <= 1,
    number.allSatisfy({ $0 == "." || ($0.isASCII && $0.isNumber) }), let amount = Double(number), amount > 0
  else { fail(message) }
  switch unit {
  case "m": return amount * 60
  case "h": return amount * 3600
  case "d": return amount * 86400
  default: fail(message)
  }
}

func ordinalSuffix(_ day: Int) -> String {
  if (11...13).contains(day % 100) { return "th" }
  return [1: "st", 2: "nd", 3: "rd"][day % 10] ?? "th"
}

enum Repeat {
  case daily, workdays, weekly(Int), monthly(Int)

  init(_ value: String) {
    switch value {
    case "day": self = .daily
    case "weekday": self = .workdays
    default:
      if let weekday = weekdays[value] {
        self = .weekly(weekday)
        return
      }
      let digits = value.prefix { $0.isASCII && $0.isNumber }
      let suffix = String(value.dropFirst(digits.count))
      if (1...2).contains(digits.count), digits.first != "0", let day = Int(digits), (1...31).contains(day),
        suffix.isEmpty || suffix == ordinalSuffix(day)
      {
        self = .monthly(day)
        return
      }
      fail("--every values: day|weekday|mon..sun|1st..31st")
    }
  }

  var rule: EKRecurrenceRule {
    func weekly(_ days: [Int]) -> EKRecurrenceRule {
      EKRecurrenceRule(
        recurrenceWith: .weekly, interval: 1,
        daysOfTheWeek: days.map { EKRecurrenceDayOfWeek(EKWeekday(rawValue: $0)!) },
        daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: nil)
    }
    switch self {
    case .daily: return EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)
    case .workdays: return weekly(Array(2...6))
    case .weekly(let day): return weekly([day])
    case .monthly(let day):
      return EKRecurrenceRule(
        recurrenceWith: .monthly, interval: 1, daysOfTheWeek: nil, daysOfTheMonth: [NSNumber(value: day)],
        monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: nil)
    }
  }

  func matches(_ day: Date) -> Bool {
    let weekday = gregorian.component(.weekday, from: day)
    switch self {
    case .daily: return true
    case .workdays: return (2...6).contains(weekday)
    case .weekly(let target): return weekday == target
    case .monthly(let target): return gregorian.component(.day, from: day) == target
    }
  }
}

func firstOccurrence(_ recurrence: Repeat, from start: Date, hour: Int, minute: Int) -> Date {
  for offset in 0..<366 {
    let day = gregorian.date(byAdding: .day, value: offset, to: gregorian.startOfDay(for: start))!
    let candidate = gregorian.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    if candidate > start && recurrence.matches(day) { return candidate }
  }
  fail("Could not find the first occurrence")
}

func parseDay(_ value: String) -> Date? {
  let today = gregorian.startOfDay(for: Date())
  switch value {
  case "today": return today
  case "tomorrow": return gregorian.date(byAdding: .day, value: 1, to: today)
  default:
    let parts = value.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 3, parts.map(\.count) == [4, 2, 2], parts.allSatisfy(isDigits) else { return nil }
    let fields = DateComponents(year: Int(parts[0]), month: Int(parts[1]), day: Int(parts[2]), hour: 12)
    guard let year = fields.year, year >= 1970, let noon = gregorian.date(from: fields),
      gregorian.component(.month, from: noon) == fields.month, gregorian.component(.day, from: noon) == fields.day
    else { return nil }
    return gregorian.startOfDay(for: noon)
  }
}

func startDay(_ flags: [String: String]) -> Date? {
  switch (flags["on"], flags["next"]) {
  case (.some, .some):
    fail("Use --on or --next, not both")
  case (let on?, nil):
    guard let day = parseDay(on) else { fail("--on must be YYYY-MM-DD|today|tomorrow") }
    return day
  case (nil, let next?):
    guard let target = weekdays[next] else { fail("--next values: mon..sun") }
    let today = gregorian.startOfDay(for: Date())
    return (1...7).lazy.map { gregorian.date(byAdding: .day, value: $0, to: today)! }
      .first { gregorian.component(.weekday, from: $0) == target }
  case (nil, nil):
    return nil
  }
}

func resolveDue(_ flags: [String: String], recurrence: Repeat?, defaultTime: () -> (Int, Int)) -> Date? {
  let now = Date()
  let day = startDay(flags)
  let time = flags["at"].map { parseTime($0) }
  guard recurrence != nil || day != nil || time != nil else { return nil }
  let (hour, minute) = time ?? defaultTime()
  if let recurrence {
    let start = day.map { max(gregorian.date(byAdding: .second, value: -1, to: $0)!, now) } ?? now
    return firstOccurrence(recurrence, from: start, hour: hour, minute: minute)
  }
  if let day { return gregorian.date(bySettingHour: hour, minute: minute, second: 0, of: day)! }
  let today = gregorian.date(bySettingHour: hour, minute: minute, second: 0, of: now)!
  return today > now ? today : gregorian.date(byAdding: .day, value: 1, to: today)!
}

func dueDate(of reminder: EKReminder) -> Date? {
  reminder.dueDateComponents.flatMap { ($0.calendar ?? gregorian).date(from: $0) }
}

func format(_ date: Date, json: Bool) -> String {
  if json {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = .current
    return formatter.string(from: date)
  }
  let formatter = DateFormatter()
  formatter.calendar = gregorian
  formatter.locale = .current
  formatter.dateFormat = "yyyy-MM-dd (E) HH:mm"
  return formatter.string(from: date)
}

func summary(_ rule: EKRecurrenceRule) -> String {
  let frequency: String
  switch rule.frequency {
  case .daily: frequency = "daily"
  case .weekly: frequency = "weekly"
  case .monthly: frequency = "monthly"
  case .yearly: frequency = "yearly"
  @unknown default: frequency = "custom"
  }
  let interval = rule.interval > 1 ? ["every \(rule.interval)"] : []
  let days = rule.daysOfTheWeek?.compactMap { day in
    weekdays.first { $0.value == day.dayOfTheWeek.rawValue }.map { (day.weekNumber != 0 ? "\(day.weekNumber)" : "") + $0.key }
  }
  let months = rule.monthsOfTheYear?.map { "month \($0)" }
  let dates = rule.daysOfTheMonth?.map(\.stringValue)
  let positions = rule.setPositions?.map { "position \($0)" }
  return ([frequency] + interval + [months, days, dates, positions].flatMap { $0 ?? [] }).joined(separator: " ")
}

func describe(_ reminder: EKReminder, json: Bool) -> [String: Any] {
  var row: [String: Any] = [
    "id": reminder.calendarItemIdentifier,
    "title": reminder.title ?? "",
    "list": reminder.calendar.title,
    "completed": reminder.isCompleted,
  ]
  if let due = dueDate(of: reminder) { row["due"] = format(due, json: json) }
  if let rule = reminder.recurrenceRules?.first { row["repeat"] = summary(rule) }
  if let notes = reminder.notes, !notes.isEmpty { row["note"] = notes }
  if let url = reminder.url { row["url"] = url.absoluteString }
  return row
}

func printJSON(_ value: Any) {
  let data = try! JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
  print(String(decoding: data, as: UTF8.self))
}

func printReminders(_ reminders: [EKReminder], json: Bool) {
  let rows = reminders.map { describe($0, json: json) }
  if json { return printJSON(rows) }
  for row in rows {
    let due = (row["due"] as? String).map { " · \($0)" } ?? ""
    let repeats = (row["repeat"] as? String).map { " · \($0)" } ?? ""
    print("[\(row["list"]!)] \(row["title"]!)\(due)\(repeats)  (\(row["id"]!))")
  }
}

func fetch(_ id: String) -> EKReminder {
  guard let item = store.calendarItem(withIdentifier: id) as? EKReminder else { fail("Reminder not found: \(id)") }
  return item
}

func fetchAll(_ ids: [String]) -> [EKReminder] {
  guard !ids.isEmpty else { fail(usage) }
  var seen = Set<String>()
  return ids.filter { seen.insert($0).inserted }.map(fetch)
}

func incomplete(in calendars: [EKCalendar]) -> [EKReminder] {
  fetchReminders(store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: calendars))
}

func fetchReminders(_ predicate: NSPredicate) -> [EKReminder] {
  let semaphore = DispatchSemaphore(value: 0)
  var found: [EKReminder] = []
  store.fetchReminders(matching: predicate) { result in
    found = result ?? []
    semaphore.signal()
  }
  semaphore.wait()
  return found
}

func add(_ positional: [String], _ flags: [String: String]) {
  guard positional.count == 1, let title = positional.first, !title.isEmpty else {
    fail("add takes one quoted title\n\(usage)")
  }
  let target = calendar(named: flags["list"])
  if flags["force"] == nil, incomplete(in: [target]).contains(where: { $0.title == title }) {
    fail("Already exists: [\(target.title)] \(title) (use --force to add anyway)")
  }
  let recurrence = flags["every"].map(Repeat.init)
  let reminder = EKReminder(eventStore: store)
  reminder.title = title
  reminder.calendar = target
  reminder.notes = flags["note"]
  reminder.url = flags["url"].flatMap(URL.init(string:))
  if let priority = flags["priority"] {
    guard let level = ["high": 1, "medium": 5, "low": 9][priority] else { fail("--priority: high|medium|low") }
    reminder.priority = level
  }
  if let due = resolveDue(flags, recurrence: recurrence, defaultTime: { defaultTime(for: target) }) {
    reminder.dueDateComponents = gregorian.dateComponents(
      [.calendar, .timeZone, .year, .month, .day, .hour, .minute], from: due)
    reminder.addAlarm(EKAlarm(relativeOffset: 0))
    if let before = flags["alert-before"] { reminder.addAlarm(EKAlarm(relativeOffset: -parseOffset(before))) }
  } else if flags["alert-before"] != nil {
    fail("--alert-before requires a date or time")
  }
  if let recurrence { reminder.addRecurrenceRule(recurrence.rule) }
  do { try store.save(reminder, commit: true) } catch { fail("Save failed: \(error.localizedDescription)") }
  printReminders([reminder], json: flags["json"] != nil)
}

func list(_ flags: [String: String]) {
  let calendars = flags["list"].map { [calendar(named: $0)] } ?? store.calendars(for: .reminder)
  let predicate = flags["done"] != nil
    ? store.predicateForCompletedReminders(withCompletionDateStarting: nil, ending: nil, calendars: calendars)
    : store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: calendars)
  let sorted = fetchReminders(predicate).sorted {
    (dueDate(of: $0) ?? .distantFuture) < (dueDate(of: $1) ?? .distantFuture)
  }
  printReminders(sorted, json: flags["json"] != nil)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { fail(usage) }
if ["help", "-h", "--help"].contains(command) { showHelp() }
guard let parsed = Command(rawValue: command) else { fail("Unknown command: \(command)\n\(usage)") }
let (positional, flags) = parseFlags(Array(arguments.dropFirst()))
requestAccess()

switch parsed {
case .add:
  add(positional, flags)
case .list:
  list(flags)
case .lists:
  let titles = store.calendars(for: .reminder).map(\.title)
  if flags["json"] != nil { printJSON(titles) } else { titles.forEach { print($0) } }
case .done:
  let items = fetchAll(positional)
  do {
    for item in items {
      item.isCompleted = true
      try store.save(item, commit: false)
    }
    try store.commit()
  } catch { fail("Complete failed: \(error.localizedDescription)") }
  items.forEach { print("Completed: \($0.title ?? "")") }
case .delete:
  let items = fetchAll(positional)
  do {
    for item in items { try store.remove(item, commit: false) }
    try store.commit()
  } catch { fail("Delete failed: \(error.localizedDescription)") }
  items.forEach { print("Deleted: \($0.title ?? "")") }
case .move:
  guard positional.count == 1, let id = positional.first, let target = flags["list"] else { fail(usage) }
  let item = fetch(id)
  item.calendar = calendar(named: target)
  do { try store.save(item, commit: true) } catch { fail("Move failed: \(error.localizedDescription)") }
  printReminders([item], json: flags["json"] != nil)
}
