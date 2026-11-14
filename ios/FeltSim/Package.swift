// swift-tools-version:6.0
import PackageDescription

let package = Package(
  name: "FeltSim",
  platforms: [.iOS(.v17), .macOS(.v14)],
  products: [.library(name: "FeltSim", targets: ["FeltSim"])],
  targets: [
    .target(name: "FeltSim"),
    .testTarget(name: "FeltSimTests", dependencies: ["FeltSim"], resources: [.copy("Fixtures")]),
  ]
)
