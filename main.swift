import EventKit
import Foundation

let store = EKEventStore()
let listAliases = ["개인": "미리 알림", "personal": "미리 알림", "work": "업무"]
let weekdays = ["sun": 1, "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7]
let knownFlags: Set<String> = [
  "list", "on", "next", "at", "every", "alert-before", "note", "url", "priority", "json", "done", "force",
]
let usage = """
remind add "title" [--list name] [--force] [--on YYYY-MM-DD|today|tomorrow] [--next mon..sun] [--at HH:MM]
                   [--every day|weekday|mon..sun|1st..31st] [--alert-before 30m|2h|1d]
                   [--note text] [--url url] [--priority high|medium|low]
remind list [--list name] [--done] [--json]
remind lists
remind done <id>...
remind delete <id>...
remind move <id> --list name
"""

func fail(_ message: String) -> Never {
  FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
  exit(1)
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
    if arg.hasPrefix("--") {
      let key = String(arg.dropFirst(2))
      if !knownFlags.contains(key) { fail("Unknown option: \(arg)\n\(usage)") }
      if ["json", "done", "force"].contains(key) {
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
  let name = listAliases[raw] ?? raw
  guard let found = store.calendars(for: .reminder).first(where: { $0.title == name }) else {
    fail("List not found: \(name)")
  }
  return found
}

func parseTime(_ value: String) -> (Int, Int) {
  let parts = value.split(separator: ":").compactMap { Int($0) }
  guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else {
    fail("--at must be HH:MM")
  }
  return (parts[0], parts[1])
}

func parseOffset(_ value: String) -> TimeInterval {
  guard let unit = value.last, let amount = Double(value.dropLast()) else { fail("--alert-before format: 30m|2h|1d") }
  switch unit {
  case "m": return amount * 60
  case "h": return amount * 3600
  case "d": return amount * 86400
  default: fail("--alert-before format: 30m|2h|1d")
  }
}

func recurrence(_ value: String) -> EKRecurrenceRule {
  if value == "day" {
    return EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)
  }
  if value == "weekday" {
    let days = (2...6).map { EKRecurrenceDayOfWeek(EKWeekday(rawValue: $0)!) }
    return EKRecurrenceRule(
      recurrenceWith: .weekly, interval: 1, daysOfTheWeek: days, daysOfTheMonth: nil,
      monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: nil)
  }
  if let weekday = weekdays[value] {
    return EKRecurrenceRule(
      recurrenceWith: .weekly, interval: 1, daysOfTheWeek: [EKRecurrenceDayOfWeek(EKWeekday(rawValue: weekday)!)],
      daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: nil)
  }
  let digits = value.prefix { $0.isNumber }
  if let day = Int(digits), (1...31).contains(day) {
    return EKRecurrenceRule(
      recurrenceWith: .monthly, interval: 1, daysOfTheWeek: nil, daysOfTheMonth: [NSNumber(value: day)],
      monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: nil)
  }
  fail("--every values: day|weekday|mon..sun|1st..31st")
}

func firstOccurrence(every: String, from start: Date, hour: Int, minute: Int) -> Date {
  let cal = Calendar.current
  for offset in 0..<366 {
    let day = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: start))!
    let candidate = cal.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    if candidate <= start { continue }
    let weekday = cal.component(.weekday, from: day)
    let dayOfMonth = cal.component(.day, from: day)
    switch every {
    case "day": return candidate
    case "weekday": if (2...6).contains(weekday) { return candidate }
    default:
      if let target = weekdays[every], target == weekday { return candidate }
      if let target = Int(every.prefix { $0.isNumber }), target == dayOfMonth { return candidate }
    }
  }
  fail("Could not find the first occurrence")
}

func resolveDue(_ flags: [String: String], defaultTime: (Int, Int)) -> Date? {
  let cal = Calendar.current
  let now = Date()
  let time = flags["at"].map(parseTime)
  if let every = flags["every"] {
    let (hour, minute) = time ?? defaultTime
    let start = flags["on"].flatMap { parseDay($0) }.map { cal.date(byAdding: .second, value: -1, to: $0)! } ?? now
    return firstOccurrence(every: every, from: start, hour: hour, minute: minute)
  }
  var day: Date?
  if let on = flags["on"] {
    guard let parsed = parseDay(on) else { fail("--on must be YYYY-MM-DD|today|tomorrow") }
    day = parsed
  }
  if let next = flags["next"] {
    guard let target = weekdays[next] else { fail("--next values: mon..sun") }
    day = (1...7).lazy.map { cal.date(byAdding: .day, value: $0, to: cal.startOfDay(for: now))! }
      .first { cal.component(.weekday, from: $0) == target }
  }
  if day == nil && time == nil { return nil }
  let (hour, minute) = time ?? defaultTime
  if let day { return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day)! }
  let today = cal.date(bySettingHour: hour, minute: minute, second: 0, of: now)!
  return today > now ? today : cal.date(byAdding: .day, value: 1, to: today)!
}

func parseDay(_ value: String) -> Date? {
  let cal = Calendar.current
  switch value {
  case "today": return cal.startOfDay(for: Date())
  case "tomorrow": return cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))
  default:
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.timeZone = .current
    return formatter.date(from: value)
  }
}

func format(_ date: Date?) -> String {
  guard let date else { return "" }
  let formatter = DateFormatter()
  formatter.dateFormat = "yyyy-MM-dd (E) HH:mm"
  formatter.locale = .current
  return formatter.string(from: date)
}

func describe(_ reminder: EKReminder) -> [String: Any] {
  var row: [String: Any] = [
    "id": reminder.calendarItemIdentifier,
    "title": reminder.title ?? "",
    "list": reminder.calendar.title,
    "completed": reminder.isCompleted,
  ]
  if let due = reminder.dueDateComponents?.date { row["due"] = format(due) }
  if let rule = reminder.recurrenceRules?.first {
    row["repeat"] = rule.description.components(separatedBy: "RRULE ").last ?? rule.description
  }
  if let notes = reminder.notes, !notes.isEmpty { row["note"] = notes }
  if let url = reminder.url { row["url"] = url.absoluteString }
  return row
}

func printRows(_ rows: [[String: Any]], json: Bool) {
  if json {
    let data = try! JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
    print(String(data: data, encoding: .utf8)!)
    return
  }
  for row in rows {
    let due = (row["due"] as? String).map { " · \($0)" } ?? ""
    let repeats = row["repeat"] != nil ? " · repeats" : ""
    print("[\(row["list"]!)] \(row["title"]!)\(due)\(repeats)  (\(row["id"]!))")
  }
}

func fetch(_ id: String) -> EKReminder {
  guard let item = store.calendarItem(withIdentifier: id) as? EKReminder else { fail("Reminder not found: \(id)") }
  return item
}

func add(_ positional: [String], _ flags: [String: String]) {
  guard let title = positional.first, !title.isEmpty else { fail(usage) }
  let reminder = EKReminder(eventStore: store)
  let target = calendar(named: flags["list"])
  if flags["force"] == nil, !incomplete(in: [target]).filter({ $0.title == title }).isEmpty {
    fail("Already exists: [\(target.title)] \(title) (use --force to add anyway)")
  }
  reminder.title = title
  reminder.calendar = target
  reminder.notes = flags["note"]
  reminder.url = flags["url"].flatMap(URL.init(string:))
  if let priority = flags["priority"] {
    guard let level = ["high": 1, "medium": 5, "low": 9][priority] else { fail("--priority: high|medium|low") }
    reminder.priority = level
  }
  if let due = resolveDue(flags, defaultTime: target.title == "업무" ? (10, 0) : (9, 0)) {
    reminder.dueDateComponents = Calendar.current.dateComponents(
      [.year, .month, .day, .hour, .minute, .timeZone], from: due)
    reminder.addAlarm(EKAlarm(relativeOffset: 0))
    if let before = flags["alert-before"] { reminder.addAlarm(EKAlarm(relativeOffset: -parseOffset(before))) }
  } else if flags["alert-before"] != nil || flags["every"] != nil {
    fail("--alert-before/--every require a date or time")
  }
  if let every = flags["every"] { reminder.addRecurrenceRule(recurrence(every)) }
  do { try store.save(reminder, commit: true) } catch { fail("Save failed: \(error.localizedDescription)") }
  printRows([describe(reminder)], json: flags["json"] != nil)
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

func list(_ flags: [String: String]) {
  let calendars = flags["list"].map { [calendar(named: $0)] } ?? store.calendars(for: .reminder)
  let predicate = flags["done"] != nil
    ? store.predicateForCompletedReminders(withCompletionDateStarting: nil, ending: nil, calendars: calendars)
    : store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: calendars)
  let sorted = fetchReminders(predicate).sorted {
    ($0.dueDateComponents?.date ?? .distantFuture) < ($1.dueDateComponents?.date ?? .distantFuture)
  }
  printRows(sorted.map(describe), json: flags["json"] != nil)
}

requestAccess()
let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { fail(usage) }
let (positional, flags) = parseFlags(Array(arguments.dropFirst()))

switch command {
case "add":
  add(positional, flags)
case "list":
  list(flags)
case "lists":
  for item in store.calendars(for: .reminder) { print(item.title) }
case "done":
  for id in positional {
    let item = fetch(id)
    item.isCompleted = true
    try? store.save(item, commit: true)
    print("Completed: \(item.title ?? id)")
  }
case "delete":
  for id in positional {
    let item = fetch(id)
    do { try store.remove(item, commit: true) } catch { fail("Delete failed: \(error.localizedDescription)") }
    print("Deleted: \(item.title ?? id)")
  }
case "move":
  guard let id = positional.first, let target = flags["list"] else { fail(usage) }
  let item = fetch(id)
  item.calendar = calendar(named: target)
  do { try store.save(item, commit: true) } catch { fail("Move failed: \(error.localizedDescription)") }
  printRows([describe(item)], json: false)
default:
  fail(usage)
}
