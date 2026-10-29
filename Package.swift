// swift-tools-version: 6.1
import PackageDescription

let package = Package(
  name: "remind",
  platforms: [.macOS(.v14)],
  targets: [
    .target(name: "RemindCore"),
    .executableTarget(name: "remind", dependencies: ["RemindCore"]),
    .testTarget(name: "RemindCoreTests", dependencies: ["RemindCore"]),
  ]
)
