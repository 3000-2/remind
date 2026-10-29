import EventKit
import Foundation

let usage = """
remind add "title" [--list L] [--on DATE] [--at HH:MM | --all-day] [--every SPEC] [--alert none|30m|2h|1d]
                   [--note text] [--url https://...] [--priority high|medium|low] [--force] [--json]
remind edit <id> [--title text] [--list L] [options of add] [--clear note,url,priority,due,repeat] [--json]
remind list [--list L] [--due today|week|overdue] [--search text] [--done] [--json]
remind lists [--json]
remind lists add <name>
remind done <id>... [--json]
remind undone <id>... [--json]
remind delete <id>...
remind help
"""

let help = """
\(usage)

DATE  YYYY-MM-DD, today, tomorrow, or a weekday (mon = the next Monday after today)
SPEC  day, weekday, year, mon,wed,fri, or 10th,25th,last

A date without --at uses the default time (09:00 unless configured). --at alone means today, or tomorrow if passed.
A due time gets an on-time alarm. --alert 1d adds one early alarm; --alert none sets no time alarm.
--all-day sets a date with no time and no alarm. --every year needs --on.
edit changes only the options given. On a repeating reminder, --on moves to the first repeat day on or after it.
undone works on non-repeating reminders.
--due today and week include overdue reminders. --done shows the newest 50.
Put -- before a title that starts with --.
Config (optional): \(configPath)
  {"aliases": {"w": "Work"}, "defaultTime": "09:00", "listDefaultTimes": {"Work": "10:00"}}
"""

enum Command: String {
  case add, edit, list, lists, done, undone, delete

  var values: Set<String> {
    switch self {
    case .add: return ["list", "on", "at", "every", "alert", "note", "url", "priority"]
    case .edit: return ["title", "list", "on", "at", "every", "alert", "note", "url", "priority", "clear"]
    case .list: return ["list", "due", "search"]
    case .lists, .done, .undone, .delete: return []
    }
  }

  var switches: Set<String> {
    switch self {
    case .add: return ["all-day", "force", "json"]
    case .edit: return ["all-day", "json"]
    case .list: return ["done", "json"]
    case .lists, .done, .undone: return ["json"]
    case .delete: return []
    }
  }
}

struct ListQuery {
  var list: String?
  var due: DueFilter?
  var search: String?
  var done: Bool
  var json: Bool
}

enum Action {
  case add(String, ReminderInput)
  case edit(String, ReminderInput)
  case list(ListQuery)
  case lists(json: Bool)
  case createList(String)
  case done([String], json: Bool)
  case undone([String], json: Bool)
  case delete([String])
}

func fail(_ message: String, showUsage: Bool = false) -> Never {
  let text = sanitize(message) + (showUsage ? "\n\(usage)" : "")
  FileHandle.standardError.write(Data((text + "\n").utf8))
  exit(1)
}

func ids(_ args: Args, _ command: Command) throws -> [String] {
  guard !args.positional.isEmpty else { throw RemindError("\(command.rawValue) needs at least one id", showUsage: true) }
  return args.positional
}

func makeAction(_ command: Command, _ args: Args, now: Date) throws -> Action {
  let json = args.flags["json"] != nil
  switch command {
  case .add:
    guard args.positional.count == 1, let title = args.positional.first, !title.isEmpty else {
      throw RemindError("add takes one quoted title", showUsage: true)
    }
    try checkWritable(title, "title")
    let input = try parseReminderInput(args.flags, now: now)
    if input.alert != nil && !input.touchesDue { throw RemindError("--alert needs a date or time") }
    return .add(title, input)
  case .edit:
    guard args.positional.count == 1, let id = args.positional.first else {
      throw RemindError("edit takes one id", showUsage: true)
    }
    guard !args.flags.keys.filter({ $0 != "json" }).isEmpty else { throw RemindError("edit: nothing to change") }
    return .edit(id, try parseReminderInput(args.flags, now: now))
  case .list:
    guard args.positional.isEmpty else { throw RemindError("list takes no arguments", showUsage: true) }
    let query = ListQuery(
      list: args.flags["list"], due: try args.flags["due"].map(parseDueFilter), search: args.flags["search"],
      done: args.flags["done"] != nil, json: json)
    if query.done && query.due != nil { throw RemindError("--done and --due can't be combined") }
    return .list(query)
  case .lists:
    switch args.positional {
    case []: return .lists(json: json)
    case let rest where rest.count == 2 && rest[0] == "add" && !json:
      guard !rest[1].isEmpty else { throw RemindError("List name can't be empty") }
      try checkWritable(rest[1], "List name")
      return .createList(rest[1])
    default: throw RemindError("lists takes no arguments, or add <name>", showUsage: true)
    }
  case .done: return .done(try ids(args, command), json: json)
  case .undone: return .undone(try ids(args, command), json: json)
  case .delete: return .delete(try ids(args, command))
  }
}

func add(_ title: String, _ input: ReminderInput, _ reminders: Reminders, now: Date) throws {
  let target = try reminders.calendar(named: input.list)
  if !input.force && reminders.incomplete(in: [target]).contains(where: { $0.title == title }) {
    throw RemindError("Already exists: [\(target.title)] \(title) (use --force to add anyway)")
  }
  let due = try resolveDue(input.due, defaultTime: { try reminders.defaultTime(for: target) }, now: now)
  let item = EKReminder(eventStore: reminders.store)
  item.title = title
  item.calendar = target
  item.notes = input.note
  item.url = input.url
  item.priority = input.priority ?? 0
  setDue(item, due)
  applyAlarms(item, alert: input.alert, due: due)
  if let recurrence = input.due.recurrence { item.addRecurrenceRule(rule(for: recurrence)) }
  try reminders.store.save(item, commit: true)
  printReminders([item], json: input.json)
}

func edit(_ id: String, _ input: ReminderInput, _ reminders: Reminders, now: Date) throws {
  let item = try reminders.fetch(id)
  if let title = input.title { item.title = title }
  if let list = input.list { item.calendar = try reminders.calendar(named: list) }
  if let note = input.note { item.notes = note }
  if let url = input.url { item.url = url }
  if let priority = input.priority { item.priority = priority }
  if input.clear.contains(.note) { item.notes = nil }
  if input.clear.contains(.url) { item.url = nil }
  if input.clear.contains(.priority) { item.priority = 0 }
  if input.clear.contains(.repeat) || input.clear.contains(.due) { item.recurrenceRules = nil }
  if input.clear.contains(.due) {
    setDue(item, nil)
    applyAlarms(item, alert: nil, due: nil)
  } else if input.touchesDue {
    let (due, alert) = try resolveEdit(
      input, existing: currentDue(item), existingRepeat: knownRepeat(item), existingAlert: currentAlert(item),
      defaultTime: { try reminders.defaultTime(for: item.calendar) }, now: now)
    setDue(item, due)
    applyAlarms(item, alert: alert, due: due)
    if let recurrence = input.due.recurrence { item.recurrenceRules = [rule(for: recurrence)] }
  } else if let alert = input.alert {
    guard case .timed = currentDue(item) else { throw RemindError("--alert needs a reminder with a due time") }
    applyAlarms(item, alert: alert, due: currentDue(item))
  }
  try reminders.store.save(item, commit: true)
  printReminders([item], json: input.json)
}

func list(_ query: ListQuery, _ reminders: Reminders, now: Date) throws {
  let calendars = try query.list.map { [try reminders.calendar(named: $0)] } ?? reminders.lists
  var items = query.done ? reminders.completed(in: calendars) : reminders.incomplete(in: calendars)
  if let filter = query.due {
    items = items.filter { currentDue($0).map { dueMatches($0, filter, now: now) } ?? false }
  }
  if let search = query.search {
    items = items.filter { "\($0.title ?? "")\n\($0.notes ?? "")".localizedCaseInsensitiveContains(search) }
  }
  if query.done {
    items.sort { ($0.completionDate ?? .distantPast) > ($1.completionDate ?? .distantPast) }
    if items.count > 50 { FileHandle.standardError.write(Data("(showing 50 of \(items.count))\n".utf8)) }
    items = Array(items.prefix(50))
  } else {
    items.sort { (currentDue($0)?.date ?? .distantFuture) < (currentDue($1)?.date ?? .distantFuture) }
  }
  printReminders(items, json: query.json)
}

func complete(_ ids: [String], _ reminders: Reminders, json: Bool) throws {
  let items = try reminders.fetchAll(ids)
  for item in items {
    item.isCompleted = true
    try reminders.store.save(item, commit: false)
  }
  try reminders.store.commit()
  printReminders((try? reminders.fetchAll(ids)) ?? items, json: json)
}

func uncomplete(_ ids: [String], _ reminders: Reminders, json: Bool) throws {
  let items = try reminders.fetchAll(ids)
  for item in items {
    if item.hasRecurrenceRules { throw RemindError("Repeating reminder: uncheck it in the Reminders app (\(item.title ?? ""))") }
  }
  for item in items {
    item.isCompleted = false
    try reminders.store.save(item, commit: false)
  }
  try reminders.store.commit()
  printReminders(items, json: json)
}

func delete(_ ids: [String], _ reminders: Reminders) throws {
  let items = try reminders.fetchAll(ids)
  let lines = items.map { "Deleted: [\(sanitize($0.calendar.title))] \(sanitize($0.title ?? "")) (\($0.calendarItemIdentifier))" }
  for item in items { try reminders.store.remove(item, commit: false) }
  try reminders.store.commit()
  lines.forEach { print($0) }
}

func showLists(_ reminders: Reminders, json: Bool) {
  let defaultID = reminders.store.defaultCalendarForNewReminders()?.calendarIdentifier
  let rows = reminders.lists.map { (name: sanitize($0.title, multiline: json), isDefault: $0.calendarIdentifier == defaultID) }
  if json { return printJSON(rows.map { ["name": $0.name, "default": $0.isDefault] }) }
  rows.forEach { print($0.isDefault ? "\($0.name) (default)" : $0.name) }
}

func run(_ action: Action, _ reminders: Reminders, now: Date) throws {
  switch action {
  case .add(let title, let input): try add(title, input, reminders, now: now)
  case .edit(let id, let input): try edit(id, input, reminders, now: now)
  case .list(let query): try list(query, reminders, now: now)
  case .lists(let json): showLists(reminders, json: json)
  case .createList(let name): print("Created: \(sanitize(try reminders.createList(name).title))")
  case .done(let ids, let json): try complete(ids, reminders, json: json)
  case .undone(let ids, let json): try uncomplete(ids, reminders, json: json)
  case .delete(let ids): try delete(ids, reminders)
  }
}

let arguments = Array(CommandLine.arguments.dropFirst())
let now = Date()
do {
  guard let name = arguments.first else { throw RemindError("No command", showUsage: true) }
  if ["help", "-h", "--help"].contains(name) {
    guard arguments.count == 1 else { throw RemindError("help takes no arguments") }
    print(help)
    exit(0)
  }
  guard let command = Command(rawValue: name) else { throw RemindError("Unknown command: \(name)", showUsage: true) }
  let args = try parseArgs(
    Array(arguments.dropFirst()), command: name, values: command.values, switches: command.switches)
  if args.help {
    print(help)
    exit(0)
  }
  let action = try makeAction(command, args, now: now)
  let reminders = Reminders(config: try loadConfig())
  try reminders.requestAccess()
  try run(action, reminders, now: now)
} catch let error as RemindError {
  fail(error.message, showUsage: error.showUsage)
} catch {
  fail(error.localizedDescription)
}
