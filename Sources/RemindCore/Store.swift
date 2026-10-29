import EventKit
import Foundation

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

func loadConfig() throws -> Config {
  guard FileManager.default.fileExists(atPath: configPath) else { return Config() }
  guard let data = FileManager.default.contents(atPath: configPath) else {
    throw RemindError("Cannot read \(configPath)")
  }
  do { return try JSONDecoder().decode(Config.self, from: data) } catch {
    throw RemindError("Invalid config \(configPath): \(error.localizedDescription)")
  }
}

struct Reminders {
  let store = EKEventStore()
  let config: Config

  func requestAccess() async throws {
    guard (try? await store.requestFullAccessToReminders()) == true else {
      throw RemindError("No access to Reminders (System Settings > Privacy & Security > Reminders)")
    }
  }

  var lists: [EKCalendar] { store.calendars(for: .reminder) }

  func calendar(named raw: String?) throws -> EKCalendar {
    guard let raw else {
      guard let fallback = store.defaultCalendarForNewReminders() else { throw RemindError("No default list") }
      return fallback
    }
    let name = config.aliases[raw] ?? raw
    let matches = lists.filter { $0.title == name }
    guard let found = matches.first else { throw RemindError("List not found: \(name)") }
    if matches.count > 1 { throw RemindError("Ambiguous list: \(matches.count) lists are named \(name)") }
    return found
  }

  func defaultTime(for list: EKCalendar) throws -> (hour: Int, minute: Int) {
    let aliasTime = config.listDefaultTimes.keys.sorted().first { config.aliases[$0] == list.title }
      .flatMap { config.listDefaultTimes[$0] }
    let value = config.listDefaultTimes[list.title] ?? aliasTime ?? config.defaultTime
    return try parseTime(value, source: "Default time in \(configPath)")
  }

  func createList(_ name: String) throws -> EKCalendar {
    if lists.contains(where: { $0.title == name }) { throw RemindError("List already exists: \(name)") }
    if config.aliases[name] != nil { throw RemindError("\(name) is an alias in \(configPath)") }
    guard let source = store.defaultCalendarForNewReminders()?.source else { throw RemindError("No default list") }
    let list = EKCalendar(for: .reminder, eventStore: store)
    list.title = name
    list.source = source
    try store.saveCalendar(list, commit: true)
    return list
  }

  func fetch(_ id: String) throws -> EKReminder {
    guard let item = store.calendarItem(withIdentifier: id) as? EKReminder else {
      throw RemindError("Reminder not found: \(id)")
    }
    return item
  }

  func fetchAll(_ ids: [String]) throws -> [EKReminder] {
    var seen = Set<String>()
    return try ids.filter { seen.insert($0).inserted }.map(fetch)
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

  func incomplete(in calendars: [EKCalendar]) -> [EKReminder] {
    fetchReminders(store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: calendars))
  }

  func completed(in calendars: [EKCalendar]) -> [EKReminder] {
    fetchReminders(
      store.predicateForCompletedReminders(withCompletionDateStarting: nil, ending: nil, calendars: calendars))
  }
}

func currentDue(_ reminder: EKReminder) -> Due? {
  guard let components = reminder.dueDateComponents,
    let date = (components.calendar ?? gregorian).date(from: components)
  else { return nil }
  return components.hour == nil ? .allDay(date) : .timed(date)
}

func setDue(_ reminder: EKReminder, _ due: Due?) {
  switch due {
  case nil:
    reminder.dueDateComponents = nil
  case .timed(let date):
    reminder.dueDateComponents = gregorian.dateComponents(
      [.calendar, .timeZone, .year, .month, .day, .hour, .minute], from: date)
  case .allDay(let date):
    reminder.dueDateComponents = gregorian.dateComponents([.year, .month, .day], from: date)
  }
}

func currentAlert(_ reminder: EKReminder) -> Alert? {
  let alarms = (reminder.alarms ?? []).filter { $0.structuredLocation == nil }
  if alarms.isEmpty { return Alert.none }
  return alarms.map(\.relativeOffset).filter { $0 < 0 }.min().map { .before(-$0) }
}

func applyAlarms(_ reminder: EKReminder, alert: Alert?, due: Due?) {
  reminder.alarms = reminder.alarms?.filter { $0.structuredLocation != nil }
  guard case .timed = due, alert != Alert.none else { return }
  reminder.addAlarm(EKAlarm(relativeOffset: 0))
  if case .before(let seconds) = alert { reminder.addAlarm(EKAlarm(relativeOffset: -seconds)) }
}

func rule(for recurrence: Repeat) -> EKRecurrenceRule {
  func rule(_ frequency: EKRecurrenceFrequency, weekdays: [Int]? = nil, monthDays: [Int]? = nil) -> EKRecurrenceRule {
    EKRecurrenceRule(
      recurrenceWith: frequency, interval: 1,
      daysOfTheWeek: weekdays?.map { EKRecurrenceDayOfWeek(EKWeekday(rawValue: $0)!) },
      daysOfTheMonth: monthDays?.map { NSNumber(value: $0) },
      monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: nil)
  }
  switch recurrence {
  case .daily: return rule(.daily)
  case .workdays: return rule(.weekly, weekdays: Array(2...6))
  case .yearly: return rule(.yearly)
  case .weekly(let days): return rule(.weekly, weekdays: days)
  case .monthly(let days): return rule(.monthly, monthDays: days)
  }
}

func knownRepeat(_ reminder: EKReminder) -> Repeat? {
  guard let rules = reminder.recurrenceRules, rules.count == 1, let rule = rules.first, rule.interval == 1,
    rule.recurrenceEnd == nil, rule.setPositions == nil, rule.monthsOfTheYear == nil, rule.weeksOfTheYear == nil,
    rule.daysOfTheYear == nil, rule.daysOfTheWeek?.contains(where: { $0.weekNumber != 0 }) != true
  else { return nil }
  let due = currentDue(reminder)?.date
  let weekdays = rule.daysOfTheWeek?.map(\.dayOfTheWeek.rawValue)
  let monthDays = rule.daysOfTheMonth?.map(\.intValue)
  switch rule.frequency {
  case .daily:
    return weekdays == nil && monthDays == nil ? .daily : nil
  case .weekly:
    guard monthDays == nil, let days = weekdays ?? due.map({ [gregorian.component(.weekday, from: $0)] }) else {
      return nil
    }
    return Set(days) == Set(2...6) ? .workdays : .weekly(days.sorted())
  case .monthly:
    guard weekdays == nil, let days = monthDays ?? due.map({ [gregorian.component(.day, from: $0)] }),
      days.allSatisfy({ $0 == lastDayOfMonth || (1...28).contains($0) })
    else { return nil }
    return .monthly(sortedMonthDays(days))
  case .yearly:
    return weekdays == nil && monthDays == nil ? .yearly : nil
  @unknown default:
    return nil
  }
}

let isoStyle = Date.ISO8601FormatStyle(timeSeparator: .colon, timeZoneSeparator: .colon, timeZone: .current)

func dateFormatter(_ format: String, locale: Locale) -> DateFormatter {
  let formatter = DateFormatter()
  formatter.calendar = gregorian
  formatter.locale = locale
  formatter.dateFormat = format
  return formatter
}

let jsonDayFormatter = dateFormatter("yyyy-MM-dd", locale: Locale(identifier: "en_US_POSIX"))
let textTimeFormatter = dateFormatter("yyyy-MM-dd (E) HH:mm", locale: .current)
let textDayFormatter = dateFormatter("yyyy-MM-dd (E)", locale: .current)

func format(_ due: Due, json: Bool) -> String {
  switch (due, json) {
  case (.timed(let date), true): return date.formatted(isoStyle)
  case (.allDay(let day), true): return jsonDayFormatter.string(from: day)
  case (.timed(let date), false): return textTimeFormatter.string(from: date)
  case (.allDay(let day), false): return textDayFormatter.string(from: day)
  }
}

func row(_ reminder: EKReminder, json: Bool) -> [String: Any] {
  var row: [String: Any] = [
    "id": reminder.calendarItemIdentifier,
    "title": reminder.title ?? "",
    "list": reminder.calendar.title,
    "completed": reminder.isCompleted,
  ]
  if let due = currentDue(reminder) {
    row["due"] = format(due, json: json)
    if case .timed = due, let alert = currentAlert(reminder) {
      row["alert"] = describeAlert(alert)
    }
  }
  if reminder.hasRecurrenceRules { row["repeat"] = knownRepeat(reminder).map(describeRepeat) ?? "custom" }
  if let priority = describePriority(reminder.priority) { row["priority"] = priority }
  if let notes = reminder.notes, !notes.isEmpty { row["note"] = notes }
  if let url = reminder.url { row["url"] = url.absoluteString }
  if let completedAt = reminder.completionDate, reminder.isCompleted {
    row["completedAt"] = completedAt.formatted(isoStyle)
  }
  return row.mapValues { ($0 as? String).map { sanitize($0, multiline: json) } ?? $0 }
}

func printJSON(_ value: Any) {
  let data = try! JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
  print(String(decoding: data, as: UTF8.self))
}

func printReminders(_ reminders: [EKReminder], json: Bool) {
  let rows = reminders.map { row($0, json: json) }
  if json { return printJSON(rows) }
  for row in rows {
    let details = [row["due"], row["repeat"], row["completed"] as? Bool == true ? "done" : nil]
      .compactMap { $0 as? String }
    let suffix = details.map { " · \($0)" }.joined()
    print("[\(row["list"]!)] \(row["title"]!)\(suffix)  (\(row["id"]!))")
  }
}
