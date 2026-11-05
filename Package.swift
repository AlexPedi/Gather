// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Gather", platforms: [.macOS(.v14)],
    products: [.executable(name: "Gather", targets: ["Gather"])],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
        .target(name: "GatherCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "Gather", dependencies: ["GatherCore"]),
        .target(name: "GatherTestSupport", dependencies: ["GatherCore", "CSQLite"], path: "Tests/Support"),
        .executableTarget(name: "GatherChecks", dependencies: ["GatherTestSupport"], path: "Tests/GatherChecks"),
        .testTarget(name: "GatherCoreTests", dependencies: ["GatherTestSupport"])
    ]
)
