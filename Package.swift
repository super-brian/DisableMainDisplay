// swift-tools-version:5.9
import PackageDescription

let package = Package(
  name: "DisableMainDisplay",
  platforms: [.macOS(.v13)],
  targets: [
    .executableTarget(
      name: "DisableMainDisplay",
      path: "Sources"
    )
  ]
)
