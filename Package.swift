// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "RightOpCore",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .library(name: "RightOpCore", targets: ["RightOpCore"])
  ],
  targets: [
    .target(
      name: "RightOpCore",
      path: "Shared"
    ),
    .testTarget(
      name: "RightOpCoreTests",
      dependencies: ["RightOpCore"],
      path: "Tests/RightOpCoreTests"
    ),
  ]
)
