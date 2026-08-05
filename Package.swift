// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Netglass",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "FlowModel"),
        .target(
            name: "Persistence",
            dependencies: ["FlowModel"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "flowdump",
            dependencies: ["FlowModel", "Persistence"],
            linkerSettings: [.linkedLibrary("proc")]
        ),
        .testTarget(name: "FlowModelTests", dependencies: ["FlowModel"]),
        .testTarget(name: "PersistenceTests", dependencies: ["Persistence"]),
        .testTarget(name: "flowdumpTests", dependencies: ["flowdump"]),
    ]
)
