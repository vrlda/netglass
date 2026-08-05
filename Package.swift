// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Netglass",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "FlowModel", path: "packages/FlowModel/Sources/FlowModel"),
        .target(name: "Persistence",
                dependencies: ["FlowModel"],
                path: "packages/Persistence/Sources/Persistence",
                linkerSettings: [.linkedLibrary("sqlite3")]),
        .target(name: "FlowSource",
                dependencies: ["FlowModel"],
                path: "packages/FlowSource/Sources/FlowSource",
                linkerSettings: [.linkedLibrary("proc")]),
        .executableTarget(name: "flowdump",
                          dependencies: ["FlowModel", "Persistence", "FlowSource"],
                          path: "tools/flowdump/Sources/flowdump"),
        .executableTarget(name: "NetglassMac",
                          dependencies: ["FlowModel", "Persistence", "FlowSource"],
                          path: "apps/NetglassMac/Sources/NetglassMac"),
        .testTarget(name: "NetglassMacTests", dependencies: ["NetglassMac"],
                    path: "apps/NetglassMac/Tests/NetglassMacTests"),
        .testTarget(name: "FlowModelTests", dependencies: ["FlowModel"],
                    path: "packages/FlowModel/Tests"),
        .testTarget(name: "PersistenceTests", dependencies: ["Persistence"],
                    path: "packages/Persistence/Tests"),
        .testTarget(name: "FlowSourceTests",
                    dependencies: ["FlowModel", "FlowSource"],
                    path: "packages/FlowSource/Tests/FlowSourceTests"),
        .testTarget(name: "flowdumpTests", dependencies: ["flowdump"],
                    path: "tools/flowdump/Tests/flowdumpTests"),
    ]
)
