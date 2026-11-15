// swift-tools-version:6.0
import PackageDescription

let package = Package(
  name: "FeltSim",
  platforms: [.iOS(.v17), .macOS(.v14)],
  products: [
    .library(name: "FeltSim", targets: ["FeltSim"]),
    .library(name: "FeltRender", targets: ["FeltRender"]),
  ],
  targets: [
    .target(name: "FeltSim"),
    /* section 4 of index.html on CoreGraphics (empty where there is none, as on Linux) */
    .target(name: "FeltRender", dependencies: ["FeltSim"]),
    .testTarget(name: "FeltSimTests", dependencies: ["FeltSim", "FeltRender"], resources: [.copy("Fixtures")]),
    .testTarget(name: "FeltRenderTests", dependencies: ["FeltRender", "FeltSim"], resources: [.copy("Fixtures")]),
  ]
)
