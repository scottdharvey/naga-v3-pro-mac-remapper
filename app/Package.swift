// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NagaRemapper",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "NagaRemapper", targets: ["NagaRemapper"])],
    targets: [
        .target(name: "NagaKit", linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "NagaRemapper", dependencies: ["NagaKit"])
    ]
)
