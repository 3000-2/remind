import Foundation
import Testing

let testList = "remind-test"

final class ProductsMarker {}

let binary = Bundle(for: ProductsMarker.self).bundleURL.deletingLastPathComponent().appendingPathComponent("remind")

let configHome: URL = {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent("remind-e2e-config")
  let config = #"{"aliases": {"t": "\#(testList)"}, "listDefaultTimes": {"t": "10:00"}}"#
  try? FileManager.default.createDirectory(
    at: directory.appendingPathComponent("remind"), withIntermediateDirectories: true)
  try? config.write(to: directory.appendingPathComponent("remind/config.json"), atomically: true, encoding: .utf8)
  return directory
}()

struct Run {
  let status: Int32
  let out: String
  let err: String
}

@discardableResult
func remind(_ arguments: [String]) throws -> Run {
  let process = Process()
  process.executableURL = binary
  process.arguments = arguments
  process.environment = ProcessInfo.processInfo.environment.merging(["XDG_CONFIG_HOME": configHome.path]) { $1 }
  let output = Pipe()
  let errors = Pipe()
  process.standardOutput = output
  process.standardError = errors
  try process.run()
  let out = output.fileHandleForReading.readDataToEndOfFile()
  let err = errors.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()
  return Run(
    status: process.terminationStatus, out: String(decoding: out, as: UTF8.self),
    err: String(decoding: err, as: UTF8.self))
}

@discardableResult
func remind(_ arguments: String...) throws -> Run { try remind(arguments) }

func rows(_ arguments: [String]) throws -> [[String: Any]] {
  let run = try remind(arguments + ["--json"])
  try #require(run.status == 0, "\(arguments): \(run.err)")
  return try #require(try JSONSerialization.jsonObject(with: Data(run.out.utf8)) as? [[String: Any]])
}

func rows(_ arguments: String...) throws -> [[String: Any]] { try rows(arguments) }

func row(_ arguments: String...) throws -> [String: Any] { try #require(try rows(arguments).first) }

func expectFailure(_ fragment: String, _ arguments: String..., sourceLocation: SourceLocation = #_sourceLocation) throws
{
  let run = try remind(arguments)
  #expect(run.status == 1 && run.err.contains(fragment), "\(run.err)", sourceLocation: sourceLocation)
}

func purgeTestList() throws {
  for flags in [[], ["--done"]] {
    for pass in 0... {
      let found = try rows(["list", "--list", testList] + flags)
      try #require(found.allSatisfy { $0["list"] as? String == testList }, "list --list leaked other lists")
      if found.isEmpty { break }
      try #require(pass < 10, "\(testList) didn't empty after 10 passes")
      try #require(try remind(["delete"] + found.compactMap { $0["id"] as? String }).status == 0)
    }
  }
}

@Suite struct CommandLineContract {
  @Test(arguments: [
    (["help", "x"], "help takes no arguments"),
    (["lists", "rm", "x"], "lists takes no arguments"),
    (["move", "x"], "Unknown command: move"),
    (["list", "extra"], "list takes no arguments"),
    ([], "No command"),
  ])
  func rejectsWithUsage(_ arguments: [String], _ message: String) throws {
    let run = try remind(arguments)
    #expect(run.status == 1 && run.out.isEmpty)
    #expect(run.err.hasPrefix(message), "\(run.err)")
    if message != "help takes no arguments" {
      #expect(run.err.contains("\nremind add \"title\" [--list L]"), "\(run.err)")
    }
  }

  @Test func help() throws {
    let run = try remind("help")
    #expect(run.status == 0 && run.err.isEmpty)
    #expect(run.out.hasPrefix("remind add \"title\" [--list L]") && run.out.contains("Config (optional):"))
  }
}

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["REMIND_E2E"] == "1"))
struct EndToEnd {
  init() throws {
    if try remind("list", "--list", testList).status != 0 {
      try #require(try remind("lists", "add", testList).status == 0)
    }
    try purgeTestList()
  }

  @Test func addAndEdit() throws {
    defer { try? purgeTestList() }
    let added = try row("add", "A", "--list", "t", "--on", "2027-03-15", "--alert", "none")
    #expect((added["due"] as? String)?.hasPrefix("2027-03-15T10:00") == true)
    #expect(added["alert"] as? String == "none")
    let id = try #require(added["id"] as? String)

    try expectFailure("Already exists", "add", "A", "--list", "t", "--on", "2027-03-15")
    #expect((try row("edit", id, "--at", "15:00")["due"] as? String)?.hasPrefix("2027-03-15T15:00") == true)
    #expect(try row("edit", id, "--all-day")["due"] as? String == "2027-03-15")
    let timed = try row("edit", id, "--at", "11:00", "--alert", "2h")
    #expect((timed["due"] as? String)?.hasPrefix("2027-03-15T11:00") == true && timed["alert"] as? String == "2h")
    let renamed = try row("edit", id, "--title", "A2", "--note", "hi", "--priority", "low")
    #expect(renamed["title"] as? String == "A2" && renamed["note"] as? String == "hi")
    #expect(renamed["priority"] as? String == "low")
    let cleared = try row("edit", id, "--clear", "note,priority")
    #expect(cleared["note"] == nil && cleared["priority"] == nil)
    #expect(try rows("list", "--list", testList, "--search", "a2").count == 1)
  }

  @Test func repeating() throws {
    defer { try? purgeTestList() }
    let weekly = try row(
      "add", "B", "--list", testList, "--on", "2027-03-12", "--every", "mon", "--at", "08:30", "--alert", "1d",
      "--url", "https://example.com")
    #expect((weekly["due"] as? String)?.hasPrefix("2027-03-15T08:30") == true)
    #expect(weekly["repeat"] as? String == "mon" && weekly["alert"] as? String == "1d")
    let weeklyID = try #require(weekly["id"] as? String)
    #expect((try row("edit", weeklyID, "--every", "wed")["due"] as? String)?.hasPrefix("2027-03-17T08:30") == true)

    let monthly = try row("add", "C", "--list", testList, "--on", "2027-03-01", "--every", "10th,last", "--all-day")
    #expect(monthly["due"] as? String == "2027-03-10" && monthly["repeat"] as? String == "10th,last")
    let monthlyID = try #require(monthly["id"] as? String)
    #expect(try row("done", monthlyID)["due"] as? String == "2027-03-31")
    try expectFailure("Repeating reminder", "undone", monthlyID)
  }

  @Test func doneAndUndone() throws {
    defer { try? purgeTestList() }
    let id = try #require(try row("add", "D", "--list", testList, "--on", "2027-04-01")["id"] as? String)
    #expect(try row("done", id)["completed"] as? Bool == true)
    #expect(try rows("list", "--list", testList, "--done").count == 1)
    #expect(try row("undone", id)["completed"] as? Bool == false)
    #expect(try row("undone", id)["completed"] as? Bool == false)
  }

}
