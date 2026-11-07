// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HashFleetCore",
    platforms: [.iOS(.v17), .macOS(.v14), .watchOS("26.5")],
    products: [
        .library(name: "HashFleetCore", targets: ["HashFleetCore"]),
        .library(name: "HashFleetWatchCore", targets: ["HashFleetWatchCore"]),
        .executable(name: "hashfleet", targets: ["hashfleet"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "HashFleetCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        // The Watch reads HTTP snapshots without the desktop database or WebSocket stack.
        .target(name: "HashFleetWatchCore"),
        .testTarget(name: "HashFleetWatchCoreTests", dependencies: ["HashFleetWatchCore"]),
        .executableTarget(name: "hashfleet", dependencies: ["HashFleetCore"]),
        .testTarget(name: "HashFleetCoreTests", dependencies: ["HashFleetCore"])
    ]
)
